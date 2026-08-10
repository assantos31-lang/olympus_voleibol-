import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../pages/athlete_financial_page.dart';
import '../services/financial_access_service.dart';

class FinancialAccessGate extends StatefulWidget {
  const FinancialAccessGate({super.key, required this.child});

  final Widget child;

  @override
  State<FinancialAccessGate> createState() => _FinancialAccessGateState();
}

class _FinancialAccessGateState extends State<FinancialAccessGate>
    with WidgetsBindingObserver {
  final SupabaseClient _supabase = Supabase.instance.client;
  late final FinancialAccessService _service = FinancialAccessService();
  StreamSubscription<AuthState>? _authSubscription;
  RealtimeChannel? _recordsChannel;
  RealtimeChannel? _settingsChannel;
  RealtimeChannel? _blocksChannel;
  Timer? _refreshDebounce;
  Timer? _fallbackTimer;
  FinancialAccessStatus _status = FinancialAccessStatus.unrestricted;
  String? _boundUserId;
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _authSubscription = _supabase.auth.onAuthStateChange.listen((_) {
      unawaited(_bindCurrentUser());
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_bindCurrentUser());
    });
    _fallbackTimer = Timer.periodic(
      const Duration(seconds: 20),
      (_) => unawaited(_refresh()),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_refresh());
  }

  Future<void> _bindCurrentUser() async {
    final userId = _supabase.auth.currentUser?.id;
    if (_boundUserId == userId) {
      await _refresh();
      return;
    }
    _boundUserId = userId;
    await _removeChannels();
    if (userId == null) {
      if (mounted && _status.blocked) {
        setState(() => _status = FinancialAccessStatus.unrestricted);
      }
      return;
    }

    _recordsChannel = _supabase
        .channel('financial-access-records-$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'financial_records',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'athlete_id',
            value: userId,
          ),
          callback: (_) => _scheduleRefresh(),
        )
        .subscribe();
    _settingsChannel = _supabase
        .channel('financial-access-settings-$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'financial_access_settings',
          callback: (_) => _scheduleRefresh(),
        )
        .subscribe();
    _blocksChannel = _supabase
        .channel('financial-training-block-$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'financial_training_blocks',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'athlete_id',
            value: userId,
          ),
          callback: (_) => _scheduleRefresh(),
        )
        .subscribe();
    await _refresh();
  }

  void _scheduleRefresh() {
    _refreshDebounce?.cancel();
    _refreshDebounce = Timer(
      const Duration(milliseconds: 250),
      () => unawaited(_refresh()),
    );
  }

  Future<void> _refresh() async {
    if (_refreshing || _supabase.auth.currentUser == null) return;
    _refreshing = true;
    try {
      final next = await _service.getCurrentAccessStatus();
      if (!mounted) return;
      if (next.blocked != _status.blocked ||
          next.enforcementEnabled != _status.enforcementEnabled ||
          next.selectedForBlock != _status.selectedForBlock ||
          next.overdueCount != _status.overdueCount ||
          next.overdueAmount != _status.overdueAmount) {
        setState(() => _status = next);
      }
    } catch (_) {
      // Falha de rede nunca deve bloquear quem estava com acesso liberado.
    } finally {
      _refreshing = false;
    }
  }

  Future<void> _removeChannels() async {
    final records = _recordsChannel;
    final settings = _settingsChannel;
    final blocks = _blocksChannel;
    _recordsChannel = null;
    _settingsChannel = null;
    _blocksChannel = null;
    if (records != null) await _supabase.removeChannel(records);
    if (settings != null) await _supabase.removeChannel(settings);
    if (blocks != null) await _supabase.removeChannel(blocks);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _authSubscription?.cancel();
    _refreshDebounce?.cancel();
    _fallbackTimer?.cancel();
    unawaited(_removeChannels());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_status.blocked) return widget.child;
    return AthleteFinancialPage(
      financialRestrictionActive: true,
      overdueRestrictionCount: _status.overdueCount,
    );
  }
}
