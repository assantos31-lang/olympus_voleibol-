import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_masked_text2/flutter_masked_text2.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';
import '../services/auth_service.dart';
import '../services/chat_service.dart';
import '../services/permission_service.dart';
import 'athlete_agenda_page.dart';
import 'athlete_financial_page.dart';
import 'athlete_messages_page.dart';
import 'athlete_statistics_page.dart';
import 'athlete_coach_evaluation_page.dart';
import 'chat_rooms_page.dart';
import 'admin_competitions_page.dart';
import 'admin_birthdays_page.dart';

class AthleteDashboardPage extends StatefulWidget {
  const AthleteDashboardPage({super.key});

  @override
  State<AthleteDashboardPage> createState() => _AthleteDashboardPageState();
}

class _AthleteDashboardPageState extends State<AthleteDashboardPage>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  final supabase = Supabase.instance.client;
  final _authService = AuthService();
  final ChatService _chatService = ChatService();
  final PermissionService _permissionService = PermissionService();
  Map<String, dynamic>? _profile;
  bool _isLoading = true;
  bool _isBackgroundReady = false;
  int _pendingCount = 0;
  int _pendingTrainingCount = 0;
  int _pendingFriendlyCount = 0;
  int _pendingCompetitionCount = 0;
  int _overdueFinancialCount = 0;
  int _newFinancialCount = 0;
  Map<int, int> _overdueByMonth = {};
  List<Map<String, dynamic>> _weekEvents = [];
  List<Map<String, dynamic>> _todayBirthdays = [];
  bool _isLoadingTodayBirthdays = true;
  late final AnimationController _birthdayBadgeController;
  late final Animation<double> _birthdayBadgeScale;
  late final AnimationController _presenceBlinkController;
  late final Animation<double> _presenceBlinkOpacity;
  int _messageUnreadCount = 0;
  int _chatUnreadCount = 0;
  int _competitionNewCount = 0;
  int? _currentUserRankingPosition;
  String? _currentUserRankingMovement;
  List<Map<String, dynamic>> _genderRanking = [];
  List<Map<String, dynamic>> _fullGenderRanking = [];
  List<Map<String, dynamic>> _monthlyHistory = [];
  bool _isRankingExpanded = false;
  bool _isFullRankingExpanded = false;
  bool _isRankingRulesExpanded = false;
  bool _isMonthlyHistoryExpanded = false;
  DateTime? _lastCompetitionsViewedAt;
  RealtimeChannel? _messagesRealtimeChannel;
  RealtimeChannel? _messageThreadsRealtimeChannel;
  RealtimeChannel? _messageParticipantsRealtimeChannel;
  RealtimeChannel? _competitionsRealtimeChannel;
  RealtimeChannel? _convocationsRealtimeChannel;
  RealtimeChannel? _financialRealtimeChannel;
  RealtimeChannel? _checkinsRealtimeChannel;
  RealtimeChannel? _profilesRealtimeChannel;
  RealtimeChannel? _monthlyHistoryRealtimeChannel;
  RealtimeChannel? _trainingEvaluationsRealtimeChannel;
  Timer? _dashboardBadgeFallbackTimer;

  int _confirmedPresenceCount = 0;
  int _acceptedButAbsentCount = 0;
  int _rejectedPresenceCount = 0;
  int _monthlyTrainingTotal = 0;
  int _monthlyPresenceCount = 0;
  int _monthlyAbsenceCount = 0;
  int _annualTrainingTotal = 0;
  int _annualPresenceCount = 0;
  int _annualAbsenceCount = 0;
  double _annualPresencePercent = 0;
  int _currentStreak = 0;
  double _monthlyPresencePercent = 0;
  bool _showingLevelUpDialog = false;
  bool _canAccessBirthdays = false;
  bool _canAccessChat = true;

  static const Color olympusBlue = Color(0xFF1E3A5F);
  static const Color olympusGold = Color(0xFFD4AF37);
  static const Color olympusLightBlue = Color(0xFF2C5F8D);
  static const String _eventsEmbedFk = 'convocations_event_id_fkey';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    if (!_isBackgroundReady) {
      precacheImage(
        const AssetImage('assets/images/monte_olimpo_v2.png'),
        context,
      ).whenComplete(() {
        if (mounted) {
          setState(() {
            _isBackgroundReady = true;
          });
        }
      });
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _birthdayBadgeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
    _birthdayBadgeScale = Tween<double>(begin: 1.0, end: 1.08).animate(
      CurvedAnimation(
        parent: _birthdayBadgeController,
        curve: Curves.easeInOut,
      ),
    );
    _presenceBlinkController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 760),
    )..repeat(reverse: true);
    _presenceBlinkOpacity = Tween<double>(begin: 0.42, end: 1.0).animate(
      CurvedAnimation(
        parent: _presenceBlinkController,
        curve: Curves.easeInOut,
      ),
    );
    _refreshDashboard();
  }

  Future<void> _refreshDashboard() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _isLoadingTodayBirthdays = true;
    });

    await Future.wait([
      _loadProfile(),
      _loadTodayBirthdays(),
      _loadBirthdaysPermission(),
      _loadChatPermission(),
    ]);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshDashboard();
    }
  }

  Future<void> _loadBirthdaysPermission() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    try {
      final hasAccess =
          await _permissionService.hasAccess(user.id, 'birthdays');
      if (!mounted) return;
      setState(() {
        _canAccessBirthdays = hasAccess;
      });
    } catch (e) {
      debugPrint('Erro ao carregar permissão de aniversariantes: $e');
      if (!mounted) return;
      setState(() {
        _canAccessBirthdays = false;
      });
    }
  }

  Future<void> _loadChatPermission() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    try {
      final hasAccess = await _permissionService.hasAccess(user.id, 'chat');
      if (!mounted) return;
      setState(() {
        _canAccessChat = hasAccess;
      });
    } catch (e) {
      debugPrint('Erro ao carregar permissão de chat: $e');
      if (!mounted) return;
      setState(() {
        _canAccessChat = true;
      });
    }
  }

  void _navigateToBirthdays() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const AdminBirthdaysPage(),
      ),
    );
  }

  Future<void> _loadProfile() async {
    final user = supabase.auth.currentUser;

    if (user == null) {
      if (mounted) {
        setState(() {
          _profile = null;
          _isLoading = false;
        });
      }
      return;
    }

    final profile = await _authService.getUserProfile(user.id);
    if (mounted) {
      setState(() {
        _profile = profile;
        _isLoading = false;
      });
      _checkAndShowLevelUp(profile);
      _loadPendingCount();
      _loadOverdueFinancialCount();
      _loadNewFinancialCount();
      _loadWeekEvents();
      _loadAttendanceAndPerformance();
      _loadGenderRanking(profile);
      _loadMonthlyHistory();
      _loadMessageUnreadCount();
      _loadChatUnreadCount();
      _loadCompetitionNewCount();
      _setupRealtimeListeners();
    }
  }

  int _parsePerformanceLevelRank(dynamic value) {
    if (value == null) return 1;
    if (value is int) return value;
    return int.tryParse(value.toString()) ?? 1;
  }

  String _getPerformanceLevelLabelFromRank(int rank) {
    switch (rank) {
      case 1:
        return 'Iniciante';
      case 2:
        return 'Participante';
      case 3:
        return 'Regular';
      case 4:
        return 'Comprometido';
      case 5:
        return 'Dedicado';
      case 6:
        return 'Atleta Bronze';
      case 7:
        return 'Atleta Prata';
      case 8:
        return 'Atleta Ouro';
      case 9:
        return 'Elite';
      default:
        return 'Lenda';
    }
  }

  Future<void> _checkAndShowLevelUp(Map<String, dynamic>? profile) async {
    if (!mounted || profile == null || _showingLevelUpDialog) return;

    final user = supabase.auth.currentUser;
    if (user == null) return;

    final currentRank = _parsePerformanceLevelRank(
      profile['performance_level_rank'],
    );
    final currentLevel =
        (profile['performance_level'] ?? '').toString().trim().isNotEmpty
            ? profile['performance_level'].toString().trim()
            : _getPerformanceLevelLabelFromRank(currentRank);

    final metadata = user.userMetadata ?? {};
    final lastSeenRank = _parsePerformanceLevelRank(
      metadata['last_seen_performance_level_rank'],
    );

    if (currentRank <= lastSeenRank) return;

    _showingLevelUpDialog = true;

    if (!mounted) return;

    showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierLabel: 'level-up',
      barrierColor: Colors.black.withOpacity(0.72),
      pageBuilder: (context, animation, secondaryAnimation) {
        final firstName =
            profile['full_name']?.toString().split(' ').first ?? 'Atleta';

        Future.delayed(const Duration(seconds: 3), () {
          if (Navigator.of(context).canPop()) {
            Navigator.of(context).pop();
          }
        });

        return SafeArea(
          child: Center(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 24),
              padding: const EdgeInsets.fromLTRB(24, 26, 24, 22),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(28),
                border: Border.all(
                  color: olympusGold.withOpacity(0.85),
                  width: 1.6,
                ),
                gradient: const LinearGradient(
                  colors: [
                    Color(0xFF0D223B),
                    Color(0xFF123861),
                    Color(0xFF235E94),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.35),
                    blurRadius: 24,
                    offset: const Offset(0, 12),
                  ),
                  BoxShadow(
                    color: olympusGold.withOpacity(0.18),
                    blurRadius: 28,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 88,
                    height: 88,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        colors: [
                          Color(0xFFF0D771),
                          Color(0xFFB48A23),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: olympusGold.withOpacity(0.40),
                          blurRadius: 18,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.emoji_events_rounded,
                      color: olympusBlue,
                      size: 42,
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'PARABÉNS!',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Color(0xFFFFE082),
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.1,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '$firstName, você subiu de nível!',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(999),
                      color: olympusGold.withOpacity(0.16),
                      border: Border.all(
                        color: olympusGold.withOpacity(0.50),
                      ),
                    ),
                    child: Text(
                      currentLevel.toUpperCase(),
                      style: const TextStyle(
                        color: Color(0xFFFFF2B8),
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Seu desempenho evoluiu. Continue assim para alcançar o próximo patamar.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.88),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutBack,
        );
        return FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.88, end: 1.0).animate(curved),
            child: child,
          ),
        );
      },
      transitionDuration: const Duration(milliseconds: 380),
    ).then((_) {
      _showingLevelUpDialog = false;
    });

    try {
      await supabase.auth.updateUser(
        UserAttributes(
          data: {
            ...metadata,
            'last_seen_performance_level_rank': currentRank,
          },
        ),
      );
    } catch (e) {
      debugPrint('Erro ao salvar último nível visualizado: $e');
    }
  }

  void _setupRealtimeListeners() {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    // Realtime dos badges:
    // - Usa canais sem filtro quando possível para evitar falhas silenciosas
    //   de filtro por UUID em alguns ambientes.
    // - Cada callback recarrega apenas os contadores afetados.
    // - O timer é fallback leve para quando o websocket oscila no celular.

    _messageParticipantsRealtimeChannel ??= supabase
        .channel('athlete-dashboard-message-participants-${user.id}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'app_message_participants',
          callback: (_) {
            _loadMessageUnreadCount();
          },
        )
        .subscribe((status, [error]) {
      debugPrint(
        'Realtime app_message_participants status: $status error: $error',
      );
      if (status == RealtimeSubscribeStatus.subscribed) {
        _loadMessageUnreadCount();
      }
    });

    _messagesRealtimeChannel ??= supabase
        .channel('athlete-dashboard-messages-${user.id}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'app_messages',
          callback: (_) {
            _loadMessageUnreadCount();
          },
        )
        .subscribe((status, [error]) {
      debugPrint('Realtime app_messages status: $status error: $error');
    });

    _messageThreadsRealtimeChannel ??= supabase
        .channel('athlete-dashboard-message-threads-${user.id}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'app_message_threads',
          callback: (_) {
            _loadMessageUnreadCount();
          },
        )
        .subscribe((status, [error]) {
      debugPrint(
        'Realtime app_message_threads status: $status error: $error',
      );
    });

    _competitionsRealtimeChannel ??= supabase
        .channel('athlete-dashboard-events-${user.id}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'events',
          callback: (_) {
            _loadCompetitionNewCount();
            _loadPendingCount();
            _loadWeekEvents();
            _loadAttendanceAndPerformance();
            _loadGenderRanking(_profile);
            _loadMonthlyHistory();
          },
        )
        .subscribe((status, [error]) {
      debugPrint('Realtime events status: $status error: $error');
    });

    _convocationsRealtimeChannel ??= supabase
        .channel('athlete-dashboard-convocations-${user.id}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'convocations',
          callback: (_) {
            _loadPendingCount();
            _loadWeekEvents();
            _loadAttendanceAndPerformance();
            _loadGenderRanking(_profile);
            _loadMonthlyHistory();
          },
        )
        .subscribe((status, [error]) {
      debugPrint('Realtime convocations status: $status error: $error');
    });

    _financialRealtimeChannel ??= supabase
        .channel('athlete-dashboard-financial-${user.id}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'financial_records',
          callback: (_) {
            _loadOverdueFinancialCount();
            _loadNewFinancialCount();
          },
        )
        .subscribe((status, [error]) {
      debugPrint('Realtime financial_records status: $status error: $error');
    });

    _checkinsRealtimeChannel ??= supabase
        .channel('athlete-dashboard-checkins-${user.id}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'checkins',
          callback: (_) {
            _loadAttendanceAndPerformance();
            _loadGenderRanking(_profile);
            _loadMonthlyHistory();
          },
        )
        .subscribe((status, [error]) {
      debugPrint('Realtime checkins status: $status error: $error');
    });

    _profilesRealtimeChannel ??= supabase
        .channel('athlete-dashboard-profiles-${user.id}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'profiles',
          callback: (_) {
            _loadProfile();
            _loadTodayBirthdays();
            _loadBirthdaysPermission();
            _loadGenderRanking(_profile);
          },
        )
        .subscribe((status, [error]) {
      debugPrint('Realtime profiles status: $status error: $error');
    });

    _monthlyHistoryRealtimeChannel ??= supabase
        .channel('athlete-dashboard-monthly-history-${user.id}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'athlete_monthly_history',
          callback: (_) {
            _loadMonthlyHistory();
            _loadGenderRanking(_profile);
          },
        )
        .subscribe((status, [error]) {
      debugPrint(
        'Realtime athlete_monthly_history status: $status error: $error',
      );
    });

    _trainingEvaluationsRealtimeChannel ??= supabase
        .channel('athlete-dashboard-training-evaluations-${user.id}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'training_evaluations',
          callback: (_) {
            _loadGenderRanking(_profile);
            _loadMonthlyHistory();
          },
        )
        .subscribe((status, [error]) {
      debugPrint(
        'Realtime training_evaluations status: $status error: $error',
      );
    });

    _dashboardBadgeFallbackTimer ??= Timer.periodic(
      const Duration(seconds: 10),
      (_) => _refreshRealtimeBadgesFallback(),
    );
  }

  Future<void> _refreshRealtimeBadgesFallback() async {
    if (!mounted) return;

    await Future.wait([
      _loadMessageUnreadCount(),
      _loadChatUnreadCount(),
      _loadCompetitionNewCount(),
      _loadPendingCount(),
      _loadOverdueFinancialCount(),
      _loadNewFinancialCount(),
      _loadWeekEvents(),
      _loadAttendanceAndPerformance(),
      _loadGenderRanking(_profile),
      _loadMonthlyHistory(),
      _loadTodayBirthdays(),
      _loadBirthdaysPermission(),
    ]);
  }

  Future<void> _loadMessageUnreadCount() async {
    try {
      final user = supabase.auth.currentUser;
      if (user == null) return;

      final response = await supabase
          .from('app_message_participants')
          .select('unread_count')
          .eq('user_id', user.id);

      final unreadTotal = List<Map<String, dynamic>>.from(response).fold<int>(
        0,
        (sum, row) => sum + (((row['unread_count'] ?? 0) as num).toInt()),
      );

      if (mounted) {
        setState(() {
          _messageUnreadCount = unreadTotal;
        });
      }
    } catch (e) {
      debugPrint('Erro ao carregar mensagens não lidas: $e');
    }
  }

  Future<void> _loadChatUnreadCount() async {
    final total = await _chatService.getTotalUnreadCount();
    if (!mounted) return;

    setState(() => _chatUnreadCount = total);
  }

  DateTime? _getPersistedCompetitionsViewedAt() {
    final user = supabase.auth.currentUser;
    final raw = user?.userMetadata?['last_competitions_viewed_at'];
    if (raw == null) return null;
    return DateTime.tryParse(raw.toString())?.toLocal();
  }

  Future<void> _loadCompetitionNewCount() async {
    try {
      final response = await supabase
          .from('events')
          .select('id, created_at, event_type')
          .inFilter('event_type', ['campeonato', 'amistoso']);

      final referenceDate = _lastCompetitionsViewedAt ??
          _getPersistedCompetitionsViewedAt() ??
          DateTime.now().subtract(const Duration(days: 7));

      int count = 0;
      for (final row in List<Map<String, dynamic>>.from(response)) {
        final createdAt =
            DateTime.tryParse((row['created_at'] ?? '').toString())?.toLocal();
        if (createdAt != null && createdAt.isAfter(referenceDate)) {
          count++;
        }
      }

      if (mounted) {
        setState(() {
          _competitionNewCount = count;
        });
      }
    } catch (e) {
      debugPrint('Erro ao carregar novidades de competições: $e');
    }
  }

  Future<void> _loadPendingCount() async {
    try {
      final user = supabase.auth.currentUser;
      if (user != null) {
        final response = await supabase.from('convocations').select('''
status,
events!$_eventsEmbedFk (
id,
event_type,
event_date,
event_time
)
''').eq('user_id', user.id).eq('status', 'pending');

        int pendingTraining = 0;
        int pendingFriendly = 0;
        int pendingCompetition = 0;

        for (final item in List<Map<String, dynamic>>.from(response)) {
          final event = item['events'];
          if (event == null) continue;

          final eventMap = Map<String, dynamic>.from(event);

          if (!_isPendingConvocationStillActionable(eventMap)) {
            continue;
          }

          final eventType =
              (eventMap['event_type'] ?? '').toString().toLowerCase().trim();

          if (eventType.contains('treino')) {
            pendingTraining++;
            continue;
          }

          if (eventType == 'amistoso') {
            pendingFriendly++;
            continue;
          }

          if (eventType.contains('liga') || eventType.contains('campeonato')) {
            pendingCompetition++;
          }
        }

        if (mounted) {
          setState(() {
            _pendingTrainingCount = pendingTraining;
            _pendingFriendlyCount = pendingFriendly;
            _pendingCompetitionCount = pendingCompetition;
            _pendingCount =
                pendingTraining + pendingFriendly + pendingCompetition;
          });
        }
      }
    } catch (e) {
      debugPrint('Erro ao carregar pendentes: $e');
    }
  }

  Future<void> _loadOverdueFinancialCount() async {
    try {
      final user = supabase.auth.currentUser;
      if (user != null) {
        final response = await supabase
            .from('financial_records')
            .select('day, month, year, status')
            .eq('athlete_id', user.id)
            .eq('status', 'pending');

        Map<int, int> overdueByMonth = {};
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);

        for (var record in response) {
          final day = record['day'] ?? 10;
          final month = record['month'];
          final year = record['year'];
          final dueDate = DateTime(year, month, day);

          if (today.isAfter(dueDate)) {
            overdueByMonth[month] = (overdueByMonth[month] ?? 0) + 1;
          }
        }

        if (mounted) {
          setState(() {
            _overdueByMonth = overdueByMonth;
            _overdueFinancialCount =
                overdueByMonth.values.fold(0, (a, b) => a + b);
          });
        }
      }
    } catch (e) {
      debugPrint('Erro ao carregar atrasos financeiros: $e');
    }
  }

  DateTime? _getPersistedFinancialViewedAt() {
    final user = supabase.auth.currentUser;
    final raw = user?.userMetadata?['last_financial_viewed_at'];
    if (raw == null) return null;
    return DateTime.tryParse(raw.toString())?.toLocal();
  }

  Future<void> _loadNewFinancialCount() async {
    try {
      final user = supabase.auth.currentUser;
      if (user == null) return;

      final referenceDate = _getPersistedFinancialViewedAt() ??
          DateTime.now().subtract(const Duration(days: 7));

      final response = await supabase
          .from('financial_records')
          .select('id, created_at, status')
          .eq('athlete_id', user.id);

      int count = 0;
      for (final row in List<Map<String, dynamic>>.from(response)) {
        final status = (row['status'] ?? '').toString();
        if (status == 'approved') continue;

        final createdAt =
            DateTime.tryParse((row['created_at'] ?? '').toString())?.toLocal();

        if (createdAt != null && createdAt.isAfter(referenceDate)) {
          count++;
        }
      }

      if (mounted) {
        setState(() {
          _newFinancialCount = count;
        });
      }
    } catch (e) {
      debugPrint('Erro ao carregar novos débitos financeiros: $e');
    }
  }

  String _normalizarCheckInStatus(dynamic status) {
    final value = (status ?? '').toString().trim().toLowerCase();
    if (value.isEmpty) return '';
    if ([
      'ok',
      'realizado',
      'realizado com sucesso',
      'checked_in',
      'checkin_realizado',
      'success',
      'completed',
      'done',
    ].contains(value)) {
      return 'realizado';
    }
    if (['pending', 'pendente'].contains(value)) {
      return 'pendente';
    }
    return value;
  }

  bool _isCheckInRealizado(dynamic status) {
    return _normalizarCheckInStatus(status) == 'realizado';
  }

  String _getStreakLabel() {
    if (_currentStreak <= 0) return '🔥 Inicie sua sequência';
    if (_currentStreak == 1) return '🔥 1 treino seguido';
    return '🔥 $_currentStreak treinos seguidos';
  }

  Color _getPresencePercentColor(double percent) {
    final roundedPercent = percent.round();

    if (roundedPercent >= 100) {
      return Colors.greenAccent;
    }

    if (roundedPercent >= 76) {
      return olympusGold;
    }

    return Colors.redAccent;
  }

  Color _getAbsenceCardColor() {
    if (_monthlyAbsenceCount <= 0) {
      return Colors.greenAccent;
    }

    final totalConsidered = _monthlyPresenceCount + _monthlyAbsenceCount;
    if (totalConsidered <= 0) {
      return Colors.greenAccent;
    }

    final presencePercent = (_monthlyPresenceCount / totalConsidered) * 100;

    if (presencePercent >= 76 && presencePercent <= 99) {
      return olympusGold;
    }

    return Colors.redAccent;
  }

  Map<String, dynamic>? _getNextTrainingEvent() {
    final now = DateTime.now();
    final upcomingTrainings = _weekEvents.where((event) {
      final eventType =
          (event['event_type'] ?? '').toString().toLowerCase().trim();
      final eventDateTime = event['event_datetime'];
      return eventType.contains('treino') &&
          eventDateTime is DateTime &&
          !eventDateTime.isBefore(now);
    }).toList()
      ..sort(
        (a, b) => (a['event_datetime'] as DateTime)
            .compareTo(b['event_datetime'] as DateTime),
      );

    if (upcomingTrainings.isEmpty) return null;
    return upcomingTrainings.first;
  }

  DateTime? _parseCheckInDateTime(dynamic rawValue) {
    if (rawValue == null) return null;
    final raw = rawValue.toString().trim();
    if (raw.isEmpty) return null;
    return DateTime.tryParse(raw)?.toLocal();
  }

  bool _isCheckInWithinRankingWindow(
    DateTime eventDateTime,
    DateTime checkInDateTime,
  ) {
    final openTime = eventDateTime.subtract(const Duration(minutes: 10));
    final closeTime = eventDateTime.add(const Duration(minutes: 30));
    return !checkInDateTime.isBefore(openTime) &&
        !checkInDateTime.isAfter(closeTime);
  }

  int _calculateRankingPoints(
    DateTime eventDateTime,
    DateTime checkInDateTime,
  ) {
    if (!_isCheckInWithinRankingWindow(eventDateTime, checkInDateTime)) {
      return 0;
    }

    final premiumLimit = eventDateTime.add(const Duration(minutes: 10));
    if (!checkInDateTime.isAfter(premiumLimit)) {
      return 2;
    }

    return 1;
  }

  String _getRankingScoreSummary(Map<String, dynamic> athlete) {
    final totalPoints = ((athlete['total_points'] ?? 0) as num).toInt();
    final presenceCount = ((athlete['presence_count'] ?? 0) as num).toInt();
    final firstCheckins = ((athlete['first_checkins'] ?? 0) as num).toInt();

    final firstCheckinsLabel = firstCheckins == 1
        ? '1 primeira chegada'
        : '$firstCheckins primeiras chegadas';

    return '$totalPoints pts • $presenceCount treinos • $firstCheckinsLabel';
  }

  Future<void> _loadGenderRanking(Map<String, dynamic>? profile) async {
    try {
      final user = supabase.auth.currentUser;
      if (user == null || profile == null) return;

      final gender = (profile['gender'] ?? '').toString().trim();
      if (gender.isEmpty) {
        if (mounted) {
          setState(() {
            _genderRanking = [];
            _fullGenderRanking = [];
            _currentUserRankingPosition = null;
            _currentUserRankingMovement = null;
          });
        }
        return;
      }

      final now = DateTime.now();
      final previousMonth = now.month == 1 ? 12 : now.month - 1;
      final previousYear = now.month == 1 ? now.year - 1 : now.year;

      final response = await supabase.rpc(
        'get_monthly_gender_ranking',
        params: {
          'p_gender': gender,
          'p_reference_month': now.month,
          'p_reference_year': now.year,
          'p_previous_month': previousMonth,
          'p_previous_year': previousYear,
        },
      );

      final rankingRows = List<Map<String, dynamic>>.from(response);

      int? currentPosition;
      String? currentMovement;

      for (final row in rankingRows) {
        final athleteId = (row['id'] ?? '').toString();
        if (athleteId == user.id) {
          currentPosition = ((row['ranking_position'] ?? 0) as num).toInt();
          currentMovement = (row['movement'] ?? '').toString();
          break;
        }
      }

      if (mounted) {
        setState(() {
          _fullGenderRanking = rankingRows;
          _genderRanking = rankingRows.take(5).toList();
          _currentUserRankingPosition = currentPosition;
          _currentUserRankingMovement = currentMovement;
        });
      }
    } catch (e) {
      debugPrint('Erro ao carregar ranking por gênero: $e');
      if (mounted) {
        setState(() {
          _genderRanking = [];
          _fullGenderRanking = [];
          _currentUserRankingPosition = null;
          _currentUserRankingMovement = null;
        });
      }
    }
  }

  Widget _buildRankingAthleteTile(
      Map<String, dynamic> athlete, String? userId) {
    final isMe = (athlete['id'] ?? '').toString() == userId;
    final position = ((athlete['ranking_position'] ?? 0) as num).toInt();
    final avatarUrl = (athlete['avatar_url'] ?? '').toString().trim();
    final firstName = (athlete['first_name'] ?? 'Atleta').toString();

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: isMe
            ? olympusGold.withOpacity(0.12)
            : olympusBlue.withOpacity(0.04),
        border: Border.all(
          color: isMe
              ? olympusGold.withOpacity(0.40)
              : olympusBlue.withOpacity(0.08),
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 34,
            child: Text(
              _getRankingMedal(position),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: position <= 3 ? 18 : 13,
                fontWeight: FontWeight.w800,
                color: olympusBlue,
              ),
            ),
          ),
          const SizedBox(width: 8),
          CircleAvatar(
            radius: 16,
            backgroundColor: olympusBlue.withOpacity(0.12),
            backgroundImage:
                avatarUrl.isNotEmpty ? NetworkImage(avatarUrl) : null,
            child: avatarUrl.isEmpty
                ? Text(
                    firstName.isNotEmpty ? firstName[0].toUpperCase() : '?',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      color: olympusBlue,
                    ),
                  )
                : null,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              isMe ? '$firstName (você)' : firstName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: olympusBlue,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                _getRankingScoreSummary(athlete),
                maxLines: 2,
                textAlign: TextAlign.right,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Colors.grey[700],
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                _getRankingMovementLabel(athlete['movement']),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: _getRankingMovementColor(athlete['movement']),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _getRankingGenderTitle() {
    final gender = (_profile?['gender'] ?? '').toString().trim();
    if (gender.isEmpty) return 'Ranking do mês';
    return 'Ranking do mês • $gender';
  }

  String _getRankingMedal(int position) {
    switch (position) {
      case 1:
        return '🥇';
      case 2:
        return '🥈';
      case 3:
        return '🥉';
      default:
        return '${position}º';
    }
  }

  String _getRankingMovementLabel(dynamic value) {
    final movement = (value ?? '').toString().trim();
    if (movement.isEmpty) return '';
    return movement;
  }

  Color _getRankingMovementColor(dynamic value) {
    final movement = (value ?? '').toString().trim();
    if (movement.startsWith('🔼')) return Colors.green;
    if (movement.startsWith('🔽')) return Colors.red;
    if (movement.startsWith('🆕')) return olympusGold;
    return Colors.grey;
  }

  String _getRetrospectiveHeadline(Map<String, dynamic> item) {
    final presencePercent = ((item['presence_percent'] ?? 0) as num).toDouble();
    final rankingPosition = ((item['ranking_position'] ?? 0) as num).toInt();
    if (rankingPosition == 1 && presencePercent > 0) {
      return '🏆 Você liderou o mês';
    }
    if (presencePercent >= 80) {
      return '🔥 Mês de alto rendimento';
    }
    if (presencePercent >= 50) {
      return '📈 Você manteve boa regularidade';
    }
    if (presencePercent > 0) {
      return '💪 Seu mês contou como progresso';
    }
    return '🌱 Todo ciclo é chance de recomeço';
  }

  String _getRetrospectiveSupportText(Map<String, dynamic> item) {
    final presencePercent = ((item['presence_percent'] ?? 0) as num).toDouble();
    final rankingPosition = ((item['ranking_position'] ?? 0) as num).toInt();
    final totalTrainings = ((item['total_trainings'] ?? 0) as num).toInt();
    if (totalTrainings == 0) {
      return 'Este mês não teve treinos registrados para o seu histórico.';
    }
    if (rankingPosition == 1 && presencePercent > 0) {
      return 'Você terminou o mês em 1º lugar no ranking e deixou sua marca.';
    }
    if (presencePercent >= 80) {
      return 'Sua consistência foi destaque. Continue assim no próximo mês.';
    }
    if (presencePercent >= 50) {
      return 'Você ficou presente em boa parte dos treinos e construiu regularidade.';
    }
    if (presencePercent > 0) {
      return 'Mesmo com oscilações, você somou presença e experiência no mês.';
    }
    return 'Nem todo mês sai como esperado, mas o próximo pode ser sua virada.';
  }

  void _showMonthlyRetrospective(Map<String, dynamic> item) {
    final year = (item['reference_year'] ?? 0) as int;
    final month = (item['reference_month'] ?? 1) as int;
    final presenceCount = ((item['presence_count'] ?? 0) as num).toInt();
    final absenceCount = ((item['absence_count'] ?? 0) as num).toInt();
    final totalTrainings = ((item['total_trainings'] ?? 0) as num).toInt();
    final rankingPosition = item['ranking_position'] == null
        ? '-'
        : '${((item['ranking_position'] ?? 0) as num).toInt()}º';
    final presencePercent = ((item['presence_percent'] ?? 0) as num).toDouble();
    final streak = ((item['current_streak'] ?? 0) as num).toInt();
    final level = (item['performance_level'] ?? 'Iniciante').toString();
    final label = _getMonthlyHistoryLabel(month, year);

    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.62),
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(26),
            border: Border.all(
              color: olympusGold.withOpacity(0.55),
              width: 1.4,
            ),
            gradient: const LinearGradient(
              colors: [
                Color(0xFF0D223B),
                Color(0xFF123861),
                Color(0xFF235E94),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.30),
                blurRadius: 24,
                offset: const Offset(0, 12),
              ),
              BoxShadow(
                color: olympusGold.withOpacity(0.14),
                blurRadius: 22,
                spreadRadius: 1,
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const LinearGradient(
                          colors: [
                            Color(0xFFF0D771),
                            Color(0xFFB48A23),
                          ],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: olympusGold.withOpacity(0.35),
                            blurRadius: 10,
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.auto_awesome_rounded,
                        color: olympusBlue,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Retrospectiva de $label',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded),
                      color: Colors.white70,
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    color: Colors.white.withOpacity(0.08),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.10),
                    ),
                  ),
                  child: Column(
                    children: [
                      Text(
                        _getRetrospectiveHeadline(item),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Color(0xFFFFE082),
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _getRetrospectiveSupportText(item),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.88),
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _buildHistoryTag(
                      'Presenças',
                      '$presenceCount/$totalTrainings',
                      const Color(0xFF1F9D55),
                    ),
                    _buildHistoryTag(
                      'Taxa',
                      '${presencePercent.toStringAsFixed(0)}%',
                      olympusGold,
                    ),
                    _buildHistoryTag(
                      'Faltas',
                      '$absenceCount',
                      const Color(0xFFE15A5A),
                    ),
                    _buildHistoryTag(
                      'Streak',
                      '$streak',
                      const Color(0xFFEF8B17),
                    ),
                    _buildHistoryTag(
                      'Nível',
                      level,
                      const Color(0xFF4FA3FF),
                    ),
                    _buildHistoryTag(
                      'Ranking',
                      rankingPosition,
                      const Color(0xFF7B61FF),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    style: TextButton.styleFrom(
                      foregroundColor: olympusGold,
                    ),
                    child: const Text(
                      'Fechar',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGenderRankingCard() {
    if (_genderRanking.isEmpty && _monthlyHistory.isEmpty) {
      return const SizedBox.shrink();
    }

    final userId = supabase.auth.currentUser?.id;
    final currentUserInTop = _genderRanking.any(
      (athlete) => (athlete['id'] ?? '').toString() == userId,
    );
    final hasMoreRanking = _fullGenderRanking.length > 5;
    final remainingRanking = hasMoreRanking
        ? _fullGenderRanking.skip(5).toList()
        : <Map<String, dynamic>>[];

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.94),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(0.74)),
        boxShadow: [
          BoxShadow(
            color: olympusGold.withOpacity(0.10),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _getRankingGenderTitle(),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: olympusBlue.withOpacity(0.85),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(
                  _currentUserRankingPosition != null
                      ? 'Sua posição atual: ${_currentUserRankingPosition}º ${_getRankingMovementLabel(_currentUserRankingMovement)}'
                      : 'Sua posição atual: -',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: olympusBlue.withOpacity(0.75),
                  ),
                ),
              ),
              TextButton(
                onPressed: () {
                  setState(() {
                    _isRankingRulesExpanded = !_isRankingRulesExpanded;
                  });
                },
                style: TextButton.styleFrom(
                  foregroundColor: olympusBlue,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                ),
                child: Text(
                  _isRankingRulesExpanded ? 'Ocultar regras' : 'Ver regras',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              TextButton(
                onPressed: () {
                  setState(() {
                    _isRankingExpanded = !_isRankingExpanded;
                    if (!_isRankingExpanded) {
                      _isFullRankingExpanded = false;
                    }
                  });
                },
                style: TextButton.styleFrom(
                  foregroundColor: olympusGold,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                ),
                child: Text(
                  _isRankingExpanded ? 'Ocultar' : 'Ver ranking',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          if (_isRankingRulesExpanded) ...[
            const SizedBox(height: 8),
            _buildRankingRulesCard(),
          ],
          if (_isRankingExpanded && _genderRanking.isNotEmpty) ...[
            const SizedBox(height: 8),
            ..._genderRanking.map(
              (athlete) => _buildRankingAthleteTile(athlete, userId),
            ),
            if (hasMoreRanking) ...[
              const SizedBox(height: 4),
              Center(
                child: TextButton(
                  onPressed: () {
                    setState(() {
                      _isFullRankingExpanded = !_isFullRankingExpanded;
                    });
                  },
                  style: TextButton.styleFrom(
                    foregroundColor: olympusGold,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                  ),
                  child: Text(
                    _isFullRankingExpanded
                        ? 'Ocultar restante do ranking'
                        : 'Expandir ranking completo',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
            if (_isFullRankingExpanded && remainingRanking.isNotEmpty) ...[
              const SizedBox(height: 4),
              ...remainingRanking.map(
                (athlete) => _buildRankingAthleteTile(athlete, userId),
              ),
            ],
            if (_currentUserRankingPosition != null && !currentUserInTop) ...[
              const SizedBox(height: 4),
              Text(
                'Você está em ${_currentUserRankingPosition}º no ranking do mês.',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: olympusBlue.withOpacity(0.75),
                ),
              ),
            ],
          ],
          if (_monthlyHistory.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: olympusBlue.withOpacity(0.04),
                border: Border.all(
                  color: olympusBlue.withOpacity(0.08),
                ),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Histórico mensal',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: olympusBlue.withOpacity(0.82),
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          setState(() {
                            _isMonthlyHistoryExpanded =
                                !_isMonthlyHistoryExpanded;
                          });
                        },
                        style: TextButton.styleFrom(
                          foregroundColor: olympusGold,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                        ),
                        child: Text(
                          _isMonthlyHistoryExpanded
                              ? 'Ocultar'
                              : 'Ver histórico',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                  if (_isMonthlyHistoryExpanded) ...[
                    const SizedBox(height: 6),
                    ..._monthlyHistory.take(3).map((item) {
                      final year = (item['reference_year'] ?? 0) as int;
                      final month = (item['reference_month'] ?? 1) as int;
                      final presenceCount =
                          ((item['presence_count'] ?? 0) as num).toInt();
                      final absenceCount =
                          ((item['absence_count'] ?? 0) as num).toInt();
                      final totalTrainings =
                          ((item['total_trainings'] ?? 0) as num).toInt();
                      final rankingPosition = item['ranking_position'] == null
                          ? '-'
                          : '${((item['ranking_position'] ?? 0) as num).toInt()}º';
                      final presencePercent =
                          ((item['presence_percent'] ?? 0) as num).toDouble();
                      final streak =
                          ((item['current_streak'] ?? 0) as num).toInt();
                      final level =
                          (item['performance_level'] ?? 'Iniciante').toString();

                      return Container(
                        margin: const EdgeInsets.only(top: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          color: Colors.white.withOpacity(0.70),
                          border: Border.all(
                            color: olympusBlue.withOpacity(0.08),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    _getMonthlyHistoryLabel(month, year),
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w800,
                                      color: olympusBlue,
                                    ),
                                  ),
                                ),
                                TextButton(
                                  onPressed: () =>
                                      _showMonthlyRetrospective(item),
                                  style: TextButton.styleFrom(
                                    foregroundColor: olympusGold,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                  ),
                                  child: const Text(
                                    'Retrospectiva',
                                    style:
                                        TextStyle(fontWeight: FontWeight.w800),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                _buildHistoryTag(
                                  'Presenças',
                                  '$presenceCount/$totalTrainings',
                                  const Color(0xFF1F9D55),
                                ),
                                _buildHistoryTag(
                                  'Taxa',
                                  '${presencePercent.toStringAsFixed(0)}%',
                                  olympusGold,
                                ),
                                _buildHistoryTag(
                                  'Faltas',
                                  '$absenceCount',
                                  const Color(0xFFE15A5A),
                                ),
                                _buildHistoryTag(
                                  'Streak',
                                  '$streak',
                                  const Color(0xFFEF8B17),
                                ),
                                _buildHistoryTag(
                                  'Nível',
                                  level,
                                  const Color(0xFF4FA3FF),
                                ),
                                _buildHistoryTag(
                                  'Ranking',
                                  rankingPosition,
                                  const Color(0xFF7B61FF),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRankingRulesCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: olympusBlue.withOpacity(0.04),
        border: Border.all(
          color: olympusBlue.withOpacity(0.08),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.rule_rounded,
                color: olympusBlue,
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                'Regras do ranking',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: olympusBlue.withOpacity(0.90),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '• Check-in liberado 10 min antes do treino e aceito até 30 min após o início.',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: olympusBlue.withOpacity(0.78),
              height: 1.35,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '• Check-in feito até 10 min após o início vale 2 pontos.',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: olympusBlue.withOpacity(0.78),
              height: 1.35,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '• Check-in feito entre 11 e 30 min após o início vale 1 ponto.',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: olympusBlue.withOpacity(0.78),
              height: 1.35,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '• O primeiro check-in válido de cada treino ganha +1 ponto de bônus.',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: olympusBlue.withOpacity(0.78),
              height: 1.35,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '• O ranking ordena por pontos, depois por treinos válidos, depois por chegadas em 1º e por fim por nome.',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: olympusBlue.withOpacity(0.78),
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _loadMonthlyHistory() async {
    try {
      final user = supabase.auth.currentUser;
      if (user == null) return;

      final now = DateTime.now();

      final response = await supabase
          .from('athlete_monthly_history')
          .select(
            'reference_year, reference_month, total_trainings, presence_count, absence_count, presence_percent, current_streak, performance_level, ranking_position',
          )
          .eq('user_id', user.id)
          .order('reference_year', ascending: false)
          .order('reference_month', ascending: false)
          .limit(12);

      final history = List<Map<String, dynamic>>.from(response).where((item) {
        final year = ((item['reference_year'] ?? 0) as num).toInt();
        final month = ((item['reference_month'] ?? 0) as num).toInt();

        if (year == now.year && month == 3) return false;
        if (year == now.year && month == 4) return false;
        if (year > now.year) return true;
        if (year == now.year && month > now.month) return true;
        if (year < now.year) return true;
        return false;
      }).toList();

      if (mounted) {
        setState(() {
          _monthlyHistory = history;
        });
      }
    } catch (e) {
      debugPrint('Erro ao carregar histórico mensal: $e');
    }
  }

  String _getMonthlyHistoryLabel(int month, int year) {
    final date = DateTime(year, month);
    final label = DateFormat('MMMM', 'pt_BR').format(date);
    return '${label[0].toUpperCase()}${label.substring(1)} / $year';
  }

  Widget _buildMonthlyHistoryCard() {
    if (_monthlyHistory.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.94),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(0.74)),
        boxShadow: [
          BoxShadow(
            color: olympusGold.withOpacity(0.10),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Histórico mensal',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: olympusBlue.withOpacity(0.85),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Fechamentos salvos dos últimos meses',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: olympusBlue.withOpacity(0.70),
                  ),
                ),
              ),
              TextButton(
                onPressed: () {
                  setState(() {
                    _isMonthlyHistoryExpanded = !_isMonthlyHistoryExpanded;
                  });
                },
                style: TextButton.styleFrom(
                  foregroundColor: olympusGold,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                ),
                child: Text(
                  _isMonthlyHistoryExpanded ? 'Ocultar' : 'Ver histórico',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          if (_isMonthlyHistoryExpanded) ...[
            const SizedBox(height: 8),
            ..._monthlyHistory.take(3).map((item) {
              final year = (item['reference_year'] ?? 0) as int;
              final month = (item['reference_month'] ?? 1) as int;
              final presenceCount =
                  ((item['presence_count'] ?? 0) as num).toInt();
              final absenceCount =
                  ((item['absence_count'] ?? 0) as num).toInt();
              final totalTrainings =
                  ((item['total_trainings'] ?? 0) as num).toInt();
              final rankingPosition = item['ranking_position'] == null
                  ? '-'
                  : '${((item['ranking_position'] ?? 0) as num).toInt()}º';
              final presencePercent =
                  ((item['presence_percent'] ?? 0) as num).toDouble();
              final streak = ((item['current_streak'] ?? 0) as num).toInt();
              final level =
                  (item['performance_level'] ?? 'Iniciante').toString();

              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: olympusBlue.withOpacity(0.04),
                  border: Border.all(
                    color: olympusBlue.withOpacity(0.08),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _getMonthlyHistoryLabel(month, year),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: olympusBlue,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _buildHistoryTag(
                          'Presenças',
                          '$presenceCount/$totalTrainings',
                          const Color(0xFF1F9D55),
                        ),
                        _buildHistoryTag(
                          'Taxa',
                          '${presencePercent.toStringAsFixed(0)}%',
                          olympusGold,
                        ),
                        _buildHistoryTag(
                          'Faltas',
                          '$absenceCount',
                          const Color(0xFFE15A5A),
                        ),
                        _buildHistoryTag(
                          'Streak',
                          '$streak',
                          const Color(0xFFEF8B17),
                        ),
                        _buildHistoryTag(
                          'Nível',
                          level,
                          const Color(0xFF4FA3FF),
                        ),
                        _buildHistoryTag(
                          'Ranking',
                          rankingPosition,
                          const Color(0xFF7B61FF),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            }),
          ],
        ],
      ),
    );
  }

  Widget _buildHistoryTag(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: color.withOpacity(0.10),
        border: Border.all(
          color: color.withOpacity(0.22),
        ),
      ),
      child: RichText(
        text: TextSpan(
          children: [
            TextSpan(
              text: '$label: ',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
            TextSpan(
              text: value,
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: olympusBlue,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _loadWeekEvents() async {
    try {
      final user = supabase.auth.currentUser;
      if (user == null) return;

      final response = await supabase.from('convocations').select('''
status,
events!$_eventsEmbedFk (
id,
event_name,
event_date,
event_time,
event_type
)
''').eq('user_id', user.id).neq('status', 'rejected');

      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final endOfWeek = today.add(const Duration(days: 7));

      final List<Map<String, dynamic>> weekEvents = [];

      for (final item in response) {
        final event = item['events'];
        if (event == null) continue;

        final eventMap = Map<String, dynamic>.from(event);
        final eventDate = _parseEventDateTime(
          (eventMap['event_date'] ?? '').toString(),
          (eventMap['event_time'] ?? '').toString(),
        );

        if (eventDate == null) continue;

        if (!eventDate.isBefore(today) && eventDate.isBefore(endOfWeek)) {
          weekEvents.add({
            ...eventMap,
            'status': item['status'],
            'event_datetime': eventDate,
          });
        }
      }

      weekEvents.sort(
        (a, b) => (a['event_datetime'] as DateTime)
            .compareTo(b['event_datetime'] as DateTime),
      );

      if (mounted) {
        setState(() {
          _weekEvents = weekEvents;
        });
      }
    } catch (e) {
      debugPrint('Erro ao carregar eventos da semana: $e');
    }
  }

  Future<void> _loadAttendanceAndPerformance() async {
    try {
      final user = supabase.auth.currentUser;
      if (user == null) return;

      final response = await supabase.from('convocations').select('''
event_id,
status,
justification,
events!$_eventsEmbedFk (
id,
event_name,
event_type,
event_date,
event_time
)
''').eq('user_id', user.id);

      final now = DateTime.now();
      final month = now.month;
      final year = now.year;

      final List<Map<String, dynamic>> trainingEvents = [];
      final List<Map<String, dynamic>> annualTrainingEvents = [];
      final Set<String> trainingEventIds = <String>{};

      int rejectedPresence = 0;

      for (final item in response) {
        final event = item['events'];
        if (event == null) continue;

        final status = (item['status'] ?? '').toString().toLowerCase().trim();
        final justification =
            (item['justification'] ?? '').toString().toLowerCase().trim();

        if (status == 'rejected') {
          rejectedPresence++;
        }

        final eventMap = Map<String, dynamic>.from(event);
        final eventType =
            (eventMap['event_type'] ?? '').toString().toLowerCase().trim();

        if (!eventType.contains('treino')) continue;

        final eventDate = _parseEventDateTime(
          (eventMap['event_date'] ?? '').toString(),
          (eventMap['event_time'] ?? '').toString(),
        );
        if (eventDate == null) continue;
        if (eventDate.year != year) continue;

        final eventId = (eventMap['id'] ?? '').toString();
        if (eventId.isEmpty) continue;

        final normalizedTrainingEvent = {
          ...eventMap,
          'status': status,
          'justification': justification,
          'event_datetime': eventDate,
        };

        annualTrainingEvents.add(normalizedTrainingEvent);
        trainingEventIds.add(eventId);

        if (eventDate.month == month) {
          trainingEvents.add(normalizedTrainingEvent);
        }
      }

      final pendingTrainingOpenCount = trainingEvents.where((event) {
        final status = (event['status'] ?? '').toString().toLowerCase().trim();
        return status == 'pending' &&
            _isPendingConvocationStillActionable(event);
      }).length;

      final checkins = trainingEventIds.isEmpty
          ? <dynamic>[]
          : await supabase
              .from('checkins')
              .select('event_id, user_id, check_in_status, created_at')
              .eq('user_id', user.id)
              .inFilter('event_id', trainingEventIds.toList());

      final Map<String, bool> eventHasValidCheckin = {};
      final Map<String, DateTime?> eventLatestCheckinAt = {};

      for (final row in checkins) {
        final eventId = (row['event_id'] ?? '').toString();
        if (eventId.isEmpty) continue;

        final normalized = _normalizarCheckInStatus(row['check_in_status']);
        final isRealizado = normalized == 'realizado';
        final createdAt = _parseCheckInDateTime(row['created_at']);

        eventHasValidCheckin[eventId] =
            (eventHasValidCheckin[eventId] ?? false) || isRealizado;

        final currentLatest = eventLatestCheckinAt[eventId];
        if (createdAt != null &&
            (currentLatest == null || createdAt.isAfter(currentLatest))) {
          eventLatestCheckinAt[eventId] = createdAt;
        }
      }

      int monthlyPresence = 0;
      int monthlyAbsence = 0;
      int acceptedButAbsent = 0;
      int confirmedPresence = 0;

      trainingEvents.sort(
        (a, b) => (a['event_datetime'] as DateTime)
            .compareTo(b['event_datetime'] as DateTime),
      );

      final countedTrainingEvents = trainingEvents.where((event) {
        final eventId = (event['id'] ?? '').toString();
        final eventDate = event['event_datetime'] as DateTime;
        final hasValidCheckin = eventHasValidCheckin[eventId] ?? false;
        final checkinExpired =
            now.isAfter(eventDate.add(const Duration(minutes: 30)));

        // Ignora treinos futuros/abertos no percentual. Se já houver check-in
        // válido, conta como realizado mesmo antes do prazo fechar.
        return hasValidCheckin || checkinExpired;
      }).toList();

      for (final event in countedTrainingEvents) {
        final eventId = (event['id'] ?? '').toString();
        final status = (event['status'] ?? '').toString().toLowerCase().trim();
        final justification =
            (event['justification'] ?? '').toString().toLowerCase().trim();
        final hasValidCheckin = eventHasValidCheckin[eventId] ?? false;

        if (hasValidCheckin) {
          monthlyPresence++;
          confirmedPresence++;
          continue;
        }

        final isConvokedWithoutCheckin = !hasValidCheckin;

        if (isConvokedWithoutCheckin) {
          acceptedButAbsent++;
          monthlyAbsence++;
        }
      }

      final totalTrainings = countedTrainingEvents.length;
      final presencePercent =
          totalTrainings > 0 ? (monthlyPresence / totalTrainings) * 100 : 0.0;

      annualTrainingEvents.sort(
        (a, b) => (a['event_datetime'] as DateTime)
            .compareTo(b['event_datetime'] as DateTime),
      );

      final countedAnnualTrainingEvents = annualTrainingEvents.where((event) {
        final eventId = (event['id'] ?? '').toString();
        final eventDate = event['event_datetime'] as DateTime;
        final hasValidCheckin = eventHasValidCheckin[eventId] ?? false;
        final checkinExpired =
            now.isAfter(eventDate.add(const Duration(minutes: 30)));

        return hasValidCheckin || checkinExpired;
      }).toList();

      int annualPresence = 0;
      int annualAbsence = 0;

      for (final event in countedAnnualTrainingEvents) {
        final eventId = (event['id'] ?? '').toString();
        final hasValidCheckin = eventHasValidCheckin[eventId] ?? false;

        if (hasValidCheckin) {
          annualPresence++;
        } else {
          annualAbsence++;
        }
      }

      final annualTotalTrainings = countedAnnualTrainingEvents.length;
      final annualPresencePercent = annualTotalTrainings > 0
          ? (annualPresence / annualTotalTrainings) * 100
          : 0.0;

      int currentStreak = 0;
      final completedTrainings = countedTrainingEvents.toList()
        ..sort(
          (a, b) => (b['event_datetime'] as DateTime)
              .compareTo(a['event_datetime'] as DateTime),
        );

      for (final event in completedTrainings) {
        final eventId = (event['id'] ?? '').toString();
        final hasValidCheckin = eventHasValidCheckin[eventId] ?? false;

        if (hasValidCheckin) {
          currentStreak++;
        } else {
          break;
        }
      }

      if (mounted) {
        setState(() {
          _confirmedPresenceCount = confirmedPresence;
          _acceptedButAbsentCount = acceptedButAbsent;
          _rejectedPresenceCount = rejectedPresence;
          _pendingTrainingCount = pendingTrainingOpenCount;
          _pendingCount = pendingTrainingOpenCount +
              _pendingFriendlyCount +
              _pendingCompetitionCount;
          _monthlyTrainingTotal = totalTrainings;
          _monthlyPresenceCount = monthlyPresence;
          _monthlyAbsenceCount = monthlyAbsence;
          _annualTrainingTotal = annualTotalTrainings;
          _annualPresenceCount = annualPresence;
          _annualAbsenceCount = annualAbsence;
          _annualPresencePercent = annualPresencePercent;
          _currentStreak = currentStreak;
          _monthlyPresencePercent = presencePercent;
        });
      }
    } catch (e) {
      debugPrint('Erro ao carregar presença/desempenho: $e');
    }
  }

  DateTime? _parseEventDateTime(String dateStr, String timeStr) {
    try {
      final dp = dateStr.trim().split('/');
      final tp = timeStr.trim().split(':');
      if (dp.length != 3 || tp.length < 2) return null;
      return DateTime(
        int.parse(dp[2]),
        int.parse(dp[1]),
        int.parse(dp[0]),
        int.parse(tp[0]),
        int.parse(tp[1]),
      );
    } catch (_) {
      return null;
    }
  }

  bool _isPendingConvocationStillActionable(
    Map<String, dynamic> eventMap,
  ) {
    final eventDateTime = _parseEventDateTime(
      (eventMap['event_date'] ?? '').toString(),
      (eventMap['event_time'] ?? '').toString(),
    );

    if (eventDateTime == null) return false;

    final now = DateTime.now();
    if (!eventDateTime.isAfter(now)) return false;

    final eventType =
        (eventMap['event_type'] ?? '').toString().toLowerCase().trim();

    int horasLimite;
    switch (eventType) {
      case 'treino':
        horasLimite = 0;
        break;
      case 'amistoso':
        horasLimite = 12;
        break;
      case 'campeonato':
        horasLimite = 48;
        break;
      default:
        horasLimite = 3;
    }

    return eventDateTime.difference(now).inMinutes >= (horasLimite * 60);
  }

  // ignore: unused_element
  String _getAgendaSubtitle() {
    if (_weekEvents.isEmpty) {
      return 'Veja suas convocações e eventos';
    }

    final nextEvent = _weekEvents.first;
    final eventDate = nextEvent['event_datetime'] as DateTime;
    final dayLabel = DateFormat('EEE', 'pt_BR').format(eventDate);
    final dayLabelCapitalized =
        dayLabel[0].toUpperCase() + dayLabel.substring(1).replaceAll('.', '');

    return 'Próximo: $dayLabelCapitalized às ${DateFormat('HH:mm').format(eventDate)}';
  }

  String _getPerformanceLevel() {
    if (_monthlyPresencePercent <= 40) {
      return 'Iniciante';
    } else if (_monthlyPresencePercent <= 50) {
      return 'Participante';
    } else if (_monthlyPresencePercent <= 60) {
      return 'Regular';
    } else if (_monthlyPresencePercent <= 70) {
      return 'Comprometido';
    } else if (_monthlyPresencePercent <= 80) {
      return 'Dedicado';
    } else if (_monthlyPresencePercent <= 85) {
      return 'Atleta Bronze';
    } else if (_monthlyPresencePercent <= 90) {
      return 'Atleta Prata';
    } else if (_monthlyPresencePercent <= 95) {
      return 'Atleta Ouro';
    } else if (_monthlyPresencePercent <= 98) {
      return 'Elite';
    }
    return 'Lenda';
  }

  void _showTrainingPresenceLevelsInfo() {
    const levels = [
      {'level': '1. Iniciante', 'range': '0% - 40%'},
      {'level': '2. Participante', 'range': '41% - 50%'},
      {'level': '3. Regular', 'range': '51% - 60%'},
      {'level': '4. Comprometido', 'range': '61% - 70%'},
      {'level': '5. Dedicado', 'range': '71% - 80%'},
      {'level': '6. Atleta Bronze', 'range': '81% - 85%'},
      {'level': '7. Atleta Prata', 'range': '86% - 90%'},
      {'level': '8. Atleta Ouro', 'range': '91% - 95%'},
      {'level': '9. Elite', 'range': '96% - 98%'},
      {'level': '10. Lenda', 'range': '99% - 100%'},
    ];

    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.55),
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 520),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: olympusGold.withOpacity(0.60),
              width: 1.4,
            ),
            gradient: const LinearGradient(
              colors: [
                Color(0xFF102845),
                Color(0xFF173A61),
                Color(0xFF204E7B),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.30),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
              BoxShadow(
                color: olympusGold.withOpacity(0.12),
                blurRadius: 26,
                spreadRadius: 1,
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Stack(
              children: [
                Positioned(
                  top: -28,
                  right: -16,
                  child: Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withOpacity(0.05),
                    ),
                  ),
                ),
                Positioned(
                  bottom: -36,
                  left: -20,
                  child: Container(
                    width: 110,
                    height: 110,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: olympusGold.withOpacity(0.06),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: const LinearGradient(
                                colors: [
                                  Color(0xFFF0D771),
                                  Color(0xFFB48A23),
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: olympusGold.withOpacity(0.35),
                                  blurRadius: 10,
                                  spreadRadius: 0.5,
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.emoji_events_rounded,
                              color: Color(0xFF173A61),
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Text(
                              'Treinos',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(Icons.close_rounded),
                            color: Colors.white70,
                            splashRadius: 20,
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Níveis de presença mensal no padrão Olympus.',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.72),
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 18),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          color: Colors.white.withOpacity(0.08),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.10),
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Nível',
                                style: TextStyle(
                                  color: olympusGold,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            Text(
                              'Porcentagem',
                              style: TextStyle(
                                color: olympusGold,
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      Flexible(
                        child: SingleChildScrollView(
                          child: Column(
                            children: List.generate(levels.length, (index) {
                              final item = levels[index];
                              return Container(
                                margin: const EdgeInsets.only(bottom: 8),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 12,
                                ),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(14),
                                  color: index.isEven
                                      ? Colors.white.withOpacity(0.06)
                                      : Colors.white.withOpacity(0.03),
                                  border: Border.all(
                                    color: Colors.white.withOpacity(0.08),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        item['level']!,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 14,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 6,
                                      ),
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(20),
                                        color: olympusGold.withOpacity(0.16),
                                        border: Border.all(
                                          color: olympusGold.withOpacity(0.28),
                                        ),
                                      ),
                                      child: Text(
                                        item['range']!,
                                        style: const TextStyle(
                                          color: Color(0xFFFFF2B8),
                                          fontSize: 13,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: () => Navigator.pop(context),
                          style: TextButton.styleFrom(
                            foregroundColor: olympusGold,
                          ),
                          child: const Text(
                            'Fechar',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _redirectToLogin() async {
    await supabase.auth.signOut();
    if (mounted) {
      Navigator.pushNamedAndRemoveUntil(
        context,
        '/login',
        (route) => false,
      );
    }
  }

  void _navigateToProfilePage() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AthleteProfilePage(profile: _profile),
      ),
    ).then((_) => _loadProfile());
  }

  void _navigateToAgenda() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const AthleteAgendaPage(),
      ),
    ).then((_) {
      _loadPendingCount();
      _loadWeekEvents();
      _loadAttendanceAndPerformance();
    });
  }

  void _navigateToFinancial() {
    final viewedAt = DateTime.now();

    setState(() {
      _newFinancialCount = 0;
    });

    supabase.auth.updateUser(
      UserAttributes(
        data: {
          ...?supabase.auth.currentUser?.userMetadata,
          'last_financial_viewed_at': viewedAt.toIso8601String(),
        },
      ),
    );

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const AthleteFinancialPage(),
      ),
    ).then((_) {
      _loadOverdueFinancialCount();
      _loadNewFinancialCount();
    });
  }

  void _navigateToMessages() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const AthleteMessagesPage(),
      ),
    ).then((_) => _loadMessageUnreadCount());
  }

  void _navigateToStatistics() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const AthleteStatisticsPage(),
      ),
    );
  }

  void _navigateToCoachEvaluation() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const AthleteCoachEvaluationPage(),
      ),
    );
  }

  void _navigateToChat() {
    if (!_canAccessChat) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const ChatRoomsPage(),
      ),
    ).then((_) => _loadChatUnreadCount());
  }

  void _navigateToCompetitions() {
    final viewedAt = DateTime.now();

    setState(() {
      _lastCompetitionsViewedAt = viewedAt;
      _competitionNewCount = 0;
    });

    supabase.auth.updateUser(
      UserAttributes(
        data: {
          'last_competitions_viewed_at': viewedAt.toIso8601String(),
        },
      ),
    );

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const AdminCompetitionsPage(
          canEdit: false,
        ),
      ),
    ).then((_) => _loadCompetitionNewCount());
  }

  DateTime? _parseBirthdayValue(dynamic rawValue) {
    if (rawValue == null) return null;
    final raw = rawValue.toString().trim();
    if (raw.isEmpty) return null;

    try {
      if (raw.contains('/')) {
        final parts = raw.split('/');
        if (parts.length == 3) {
          return DateTime(
            int.parse(parts[2]),
            int.parse(parts[1]),
            int.parse(parts[0]),
          );
        }
      }
      return DateTime.parse(raw);
    } catch (_) {
      return null;
    }
  }

  int? _daysUntilOwnBirthday() {
    final birthDate = _parseBirthdayValue(_profile?['birth_date']);
    if (birthDate == null) return null;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    var nextBirthday = DateTime(today.year, birthDate.month, birthDate.day);

    if (nextBirthday.isBefore(today)) {
      nextBirthday = DateTime(today.year + 1, birthDate.month, birthDate.day);
    }

    return nextBirthday.difference(today).inDays;
  }

  String _getBirthdayCountdownText() {
    final days = _daysUntilOwnBirthday();
    if (days == null) return '';

    if (days == 0) {
      return 'Hoje é dia de comemorar a vida!';
    }
    if (days == 1) {
      return 'Falta 1 dia para você celebrar a vida 🎉';
    }
    return 'Faltam $days dias para você celebrar a vida 🎉';
  }

  Future<void> _loadTodayBirthdays() async {
    try {
      final response = await supabase
          .from('profiles')
          .select('full_name, birth_date, avatar_url, court_position')
          .eq('is_active', true)
          .not('birth_date', 'is', null);

      final now = DateTime.now();
      final birthdays = List<Map<String, dynamic>>.from(response).where((user) {
        final birthDate = _parseBirthdayValue(user['birth_date']);
        if (birthDate == null) return false;
        return birthDate.day == now.day && birthDate.month == now.month;
      }).toList();

      birthdays.sort((a, b) {
        final aName = (a['full_name'] ?? '').toString().toLowerCase();
        final bName = (b['full_name'] ?? '').toString().toLowerCase();
        return aName.compareTo(bName);
      });

      if (!mounted) return;
      setState(() {
        _todayBirthdays = birthdays;
        _isLoadingTodayBirthdays = false;
      });
    } catch (e) {
      debugPrint('Erro ao carregar aniversariantes do dia: $e');
      if (!mounted) return;
      setState(() {
        _todayBirthdays = [];
        _isLoadingTodayBirthdays = false;
      });
    }
  }

  Widget _buildTodayBirthdaysCard() {
    if (_isLoadingTodayBirthdays || _todayBirthdays.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: olympusGold.withOpacity(0.65),
          width: 1.4,
        ),
        gradient: const LinearGradient(
          colors: [
            Color(0xFFF7EAB0),
            Color(0xFFE6D27A),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: olympusGold.withOpacity(0.18),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withOpacity(0.35),
                  border: Border.all(
                    color: olympusGold.withOpacity(0.45),
                  ),
                ),
                child: const Icon(
                  Icons.cake_rounded,
                  color: Color(0xFF8A6400),
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Aniversariante do dia',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF6F5300),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ..._todayBirthdays.map((birthdayUser) {
            final name = (birthdayUser['full_name'] ?? 'Sem nome').toString();
            final avatarUrl =
                (birthdayUser['avatar_url'] ?? '').toString().trim();
            final position =
                ((birthdayUser['court_position'] ?? '').toString().trim())
                        .isEmpty
                    ? 'Sem posição'
                    : birthdayUser['court_position'].toString().trim();

            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                color: Colors.white.withOpacity(0.38),
                border: Border.all(
                  color: Colors.white.withOpacity(0.5),
                ),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 26,
                    backgroundColor: const Color(0xFF143A5B),
                    backgroundImage:
                        avatarUrl.isNotEmpty ? NetworkImage(avatarUrl) : null,
                    child: avatarUrl.isEmpty
                        ? Text(
                            name.isNotEmpty ? name[0].toUpperCase() : '?',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                            ),
                          )
                        : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF4B3900),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          position,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF6E5A12),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Hoje o dia é de festa: $name está completando mais um ano de vida!',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF7A5A00),
                            height: 1.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildAthleteInfoCard() {
    final firstName =
        _profile?['full_name']?.toString().split(' ').first ?? 'Atleta';
    final position = _profile?['court_position']?.toString() ?? 'Não definida';
    final avatarUrl = _profile?['avatar_url']?.toString();

    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: Colors.white.withOpacity(0.20),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.25),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
          BoxShadow(
            color: olympusGold.withOpacity(0.12),
            blurRadius: 24,
            spreadRadius: 1,
          ),
        ],
        gradient: const LinearGradient(
          colors: [
            Color(0xFF0D223B),
            Color(0xFF123861),
            Color(0xFF235E94),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Stack(
          children: [
            Positioned.fill(
              child: Opacity(
                opacity: 0.18,
                child: avatarUrl != null && avatarUrl.isNotEmpty
                    ? Image.network(
                        avatarUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                      )
                    : const SizedBox.shrink(),
              ),
            ),
            Positioned(
              top: -40,
              right: -30,
              child: Container(
                width: 140,
                height: 140,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withOpacity(0.08),
                ),
              ),
            ),
            Positioned(
              bottom: -50,
              left: -30,
              child: Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: olympusGold.withOpacity(0.08),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
              child: Column(
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 90,
                            height: 90,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(24),
                              gradient: const LinearGradient(
                                colors: [
                                  Color(0xFFF0D771),
                                  Color(0xFFB48A23),
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: olympusGold.withOpacity(0.45),
                                  blurRadius: 12,
                                  spreadRadius: 1,
                                ),
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.18),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            padding: const EdgeInsets.all(2.6),
                            child: Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(22),
                                color: const Color(0xFF113457),
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(21),
                                child: avatarUrl != null && avatarUrl.isNotEmpty
                                    ? Image.network(
                                        avatarUrl,
                                        fit: BoxFit.cover,
                                        errorBuilder: (c, o, s) =>
                                            _buildAvatarPlaceholder(firstName),
                                      )
                                    : _buildAvatarPlaceholder(firstName),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            constraints: const BoxConstraints(minWidth: 90),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(999),
                              color: olympusGold.withOpacity(0.16),
                              border: Border.all(
                                color: olympusGold.withOpacity(0.42),
                              ),
                            ),
                            child: Text(
                              _getPerformanceLevel(),
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Color(0xFFFFF2B8),
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Column(
                            children: [
                              Text(
                                '${_monthlyPresenceCount}/${_monthlyTrainingTotal} treinos',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.82),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 6),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(999),
                                child: SizedBox(
                                  width: 90,
                                  child: LinearProgressIndicator(
                                    value: _monthlyTrainingTotal > 0
                                        ? _monthlyPresenceCount /
                                            _monthlyTrainingTotal
                                        : 0,
                                    minHeight: 6,
                                    backgroundColor:
                                        Colors.white.withOpacity(0.15),
                                    valueColor:
                                        const AlwaysStoppedAnimation<Color>(
                                      olympusGold,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _monthlyTrainingTotal > 0
                                    ? '${((_monthlyPresenceCount / _monthlyTrainingTotal) * 100).toStringAsFixed(0)}%'
                                    : '0%',
                                style: TextStyle(
                                  color: olympusGold,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Olá, $firstName!',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                  height: 1.1,
                                ),
                              ),
                              const SizedBox(height: 6),
                              if (_getBirthdayCountdownText().isNotEmpty) ...[
                                Text(
                                  _getBirthdayCountdownText(),
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white.withOpacity(0.92),
                                    height: 1.2,
                                  ),
                                ),
                                const SizedBox(height: 8),
                              ],
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(22),
                                  gradient: const LinearGradient(
                                    colors: [
                                      Color(0xFFD7E3EE),
                                      Color(0xFFBFCFDD),
                                    ],
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                  ),
                                  border: Border.all(
                                    color: const Color(0xFF90A9BF),
                                    width: 1.2,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.white.withOpacity(0.35),
                                      blurRadius: 2,
                                      offset: const Offset(0, -1),
                                    ),
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.18),
                                      blurRadius: 6,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.sports_volleyball,
                                      size: 15,
                                      color: Color(0xFF42576B),
                                    ),
                                    const SizedBox(width: 6),
                                    Flexible(
                                      child: Text(
                                        position,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                          color: Color(0xFF2E4053),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (_getNextTrainingEvent() != null) ...[
                                const SizedBox(height: 8),
                                _buildCompactWeekEventsPreview(),
                                const SizedBox(height: 8),
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(12),
                                    color: Colors.white.withOpacity(0.06),
                                    border: Border.all(
                                      color: olympusGold.withOpacity(0.22),
                                    ),
                                  ),
                                  child: Text(
                                    _getStreakLabel(),
                                    style: TextStyle(
                                      color: Colors.white.withOpacity(0.88),
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _buildEmbeddedPerformanceCompactCard(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCompactWeekEventsPreview() {
    final nextTraining = _getNextTrainingEvent();
    if (nextTraining == null) return const SizedBox.shrink();

    final eventDate = nextTraining['event_datetime'] as DateTime;
    final weekday = DateFormat('EEEE', 'pt_BR').format(eventDate).toUpperCase();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: Colors.white.withOpacity(0.05),
        border: Border.all(
          color: Colors.amber,
          width: 1.5,
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.calendar_today, color: Colors.white70, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '${nextTraining['event_name']} • ${DateFormat('dd/MM • HH:mm').format(eventDate)}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmbeddedPerformanceCompactCard() {
    final progress = _monthlyTrainingTotal > 0
        ? (_monthlyPresenceCount / _monthlyTrainingTotal).clamp(0.0, 1.0)
        : 0.0;
    final now = DateTime.now();
    final monthName = DateFormat('MMMM', 'pt_BR').format(now);
    final currentMonthLabel =
        '${monthName[0].toUpperCase()}${monthName.substring(1)}';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: const LinearGradient(
          colors: [Color(0xFF132743), Color(0xFF1B3154)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(
          color: olympusGold.withOpacity(0.55),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.18),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
          BoxShadow(
            color: olympusGold.withOpacity(0.08),
            blurRadius: 12,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Column(
        children: [
          Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.centerLeft,
            children: [
              Container(
                height: 8,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.05),
                  ),
                ),
              ),
              FractionallySizedBox(
                widthFactor: progress,
                child: Container(
                  height: 8,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    gradient: const LinearGradient(
                      colors: [Color(0xFF8AF26D), Color(0xFFF3D94F)],
                    ),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0xFF9AF07A),
                        blurRadius: 8,
                        spreadRadius: 0.2,
                      ),
                    ],
                  ),
                ),
              ),
              if (progress > 0)
                Positioned(
                  left: ((MediaQuery.of(context).size.width - 56) * progress)
                      .clamp(0.0, MediaQuery.of(context).size.width - 56),
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        colors: [Color(0xFFFFF27E), Color(0xFFDABF2B)],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFF3D94F).withOpacity(0.75),
                          blurRadius: 10,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        'MÊS ATUAL • $currentMonthLabel',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.3,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 4),
                    GestureDetector(
                      onTap: _showTrainingPresenceLevelsInfo,
                      child: Container(
                        width: 16,
                        height: 16,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: olympusGold.withOpacity(0.18),
                          border: Border.all(
                            color: olympusGold.withOpacity(0.45),
                            width: 0.8,
                          ),
                        ),
                        alignment: Alignment.center,
                        child: const Text(
                          '!',
                          style: TextStyle(
                            color: olympusGold,
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            height: 1,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                '${_monthlyPresenceCount.toString().padLeft(2, '0')}/${_monthlyTrainingTotal.toString().padLeft(2, '0')} treinos',
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _buildMiniMetric(
                  icon: Icons.check_circle_outline,
                  label: 'Presença',
                  helper: 'Mês atual',
                  value: '${_monthlyPresencePercent.toStringAsFixed(0)}%',
                  valueColor: _getPresencePercentColor(_monthlyPresencePercent),
                  accentColor:
                      _getPresencePercentColor(_monthlyPresencePercent),
                  chartType: _MiniChartType.line,
                  blinkValue: true,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildMiniMetric(
                  icon: Icons.warning_amber_rounded,
                  label: 'Faltas',
                  helper: 'No mês',
                  value: _monthlyAbsenceCount.toString(),
                  valueColor: _getAbsenceCardColor(),
                  accentColor: _getAbsenceCardColor(),
                  chartType: _MiniChartType.line,
                  blinkValue: true,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildMiniMetric(
                  icon: Icons.bar_chart_rounded,
                  label: 'Volume',
                  helper: 'Treinos/mês',
                  value: _monthlyTrainingTotal.toString(),
                  valueColor: const Color(0xFF4FA3FF),
                  accentColor: const Color(0xFF4FA3FF),
                  chartType: _MiniChartType.grid,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _buildAnnualConsolidatedStrip(now.year),
        ],
      ),
    );
  }

  Widget _buildAnnualConsolidatedStrip(int year) {
    final annualProgress = _annualTrainingTotal > 0
        ? (_annualPresenceCount / _annualTrainingTotal).clamp(0.0, 1.0)
        : 0.0;

    return Container(
      padding: const EdgeInsets.fromLTRB(9, 8, 9, 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(11),
        color: const Color(0xFF061A31).withOpacity(0.72),
        border: Border.all(
          color: const Color(0xFF4FA3FF).withOpacity(0.34),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(9),
              gradient: LinearGradient(
                colors: [
                  const Color(0xFF4FA3FF).withOpacity(0.34),
                  const Color(0xFF8AF26D).withOpacity(0.18),
                ],
              ),
            ),
            child: const Icon(
              Icons.insights_rounded,
              color: Color(0xFF8FD0FF),
              size: 16,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Consolidado',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    Text(
                      'Ano atual • $year',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.62),
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: LinearProgressIndicator(
                    value: annualProgress,
                    minHeight: 5,
                    backgroundColor: Colors.white.withOpacity(0.10),
                    valueColor: AlwaysStoppedAnimation<Color>(
                      _getPresencePercentColor(_annualPresencePercent),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _buildAnnualMetricChip(
            '${_annualPresencePercent.toStringAsFixed(0)}%',
            'pres.',
            _getPresencePercentColor(_annualPresencePercent),
          ),
          const SizedBox(width: 5),
          _buildAnnualMetricChip(
            _annualAbsenceCount.toString(),
            'faltas',
            const Color(0xFFFF6B6B),
          ),
          const SizedBox(width: 5),
          _buildAnnualMetricChip(
            _annualTrainingTotal.toString(),
            'treinos',
            const Color(0xFF8FD0FF),
          ),
        ],
      ),
    );
  }

  Widget _buildAnnualMetricChip(String value, String label, Color color) {
    return Container(
      constraints: const BoxConstraints(minWidth: 38),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: color.withOpacity(0.36)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w900,
              height: 1,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white.withOpacity(0.58),
              fontSize: 7,
              fontWeight: FontWeight.w700,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMiniMetric({
    required IconData icon,
    required String label,
    required String helper,
    required String value,
    required Color valueColor,
    required Color accentColor,
    required _MiniChartType chartType,
    bool blinkValue = false,
  }) {
    return Container(
      height: 92,
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        gradient: LinearGradient(
          colors: [
            accentColor.withOpacity(0.30),
            const Color(0xFF0F2138),
            accentColor.withOpacity(0.12),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: accentColor.withOpacity(0.95), width: 1.1),
        boxShadow: [
          BoxShadow(
            color: accentColor.withOpacity(0.24),
            blurRadius: 13,
            spreadRadius: 0.7,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  color: accentColor.withOpacity(0.16),
                  border: Border.all(color: accentColor.withOpacity(0.7)),
                ),
                child: Icon(icon, size: 10, color: accentColor),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 8,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            helper,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white54,
              fontSize: 7,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 2),
          blinkValue
              ? FadeTransition(
                  opacity: _presenceBlinkOpacity,
                  child: Text(
                    value,
                    style: TextStyle(
                      color: valueColor,
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      height: 1,
                      shadows: [
                        Shadow(
                          color: valueColor.withOpacity(0.75),
                          blurRadius: 12,
                        ),
                      ],
                    ),
                  ),
                )
              : Text(
                  value,
                  style: TextStyle(
                    color: valueColor,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    height: 1,
                  ),
                ),
          const Spacer(),
          _buildMiniChart(chartType, accentColor),
        ],
      ),
    );
  }

  Widget _buildMiniChart(_MiniChartType type, Color accentColor) {
    switch (type) {
      case _MiniChartType.line:
        return CustomPaint(
          size: const Size(double.infinity, 18),
          painter: _MiniLinePainter(color: accentColor),
        );
      case _MiniChartType.barsRed:
        return Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: List.generate(8, (index) {
            final heights = [6.0, 10.0, 14.0, 7.0, 18.0, 12.0, 16.0, 9.0];
            return Expanded(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 1),
                height: heights[index],
                decoration: BoxDecoration(
                  color: accentColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            );
          }),
        );
      case _MiniChartType.grid:
        return Column(
          children: List.generate(3, (row) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Row(
                children: List.generate(8, (col) {
                  final active = (row + col) % 2 == 0 || col > 4;
                  return Expanded(
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 1),
                      height: 5,
                      decoration: BoxDecoration(
                        color: active
                            ? accentColor.withOpacity(0.95)
                            : accentColor.withOpacity(0.22),
                        borderRadius: BorderRadius.circular(1.5),
                      ),
                    ),
                  );
                }),
              ),
            );
          }),
        );
    }
  }

  Widget _buildWeekEventsSectionCard() {
    if (_weekEvents.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.94),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(0.74)),
        boxShadow: [
          BoxShadow(
            color: olympusGold.withOpacity(0.12),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.calendar_month,
                color: olympusGold,
                size: 18,
              ),
              const SizedBox(width: 8),
              const Text(
                'Eventos da semana',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: olympusBlue,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ..._weekEvents.take(3).map((event) {
            final eventDate = event['event_datetime'] as DateTime;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: olympusGold.withOpacity(0.14),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${DateFormat('dd/MM').format(eventDate)} • ${DateFormat('HH:mm').format(eventDate)}',
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: olympusBlue,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      (event['event_name'] ?? 'Evento').toString(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF2C3E5A),
                      ),
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ],
      ),
    );
  }

  Widget _buildAvatarPlaceholder(String firstName) {
    return Container(
      color: olympusGold.withOpacity(0.2),
      child: Center(
        child: Text(
          firstName[0].toUpperCase(),
          style: const TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.bold,
            color: olympusBlue,
          ),
        ),
      ),
    );
  }

  Widget _buildPresenceSummaryCard() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      padding: const EdgeInsets.fromLTRB(14, 18, 14, 14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.94),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(0.74)),
        boxShadow: [
          BoxShadow(
            color: olympusBlue.withOpacity(0.08),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Treinos:',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: olympusBlue.withOpacity(0.85),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _buildPresenceMetric(
                  icon: Icons.check_circle,
                  label: 'Check-in realizado',
                  value: _confirmedPresenceCount,
                  color: Colors.green,
                ),
              ),
              Container(
                width: 1,
                height: 48,
                color: Colors.grey.withOpacity(0.18),
              ),
              Expanded(
                child: _buildPresenceMetric(
                  icon: Icons.schedule,
                  label: 'Pendente',
                  value: _pendingTrainingCount,
                  color: Colors.orange,
                ),
              ),
              Container(
                width: 1,
                height: 48,
                color: Colors.grey.withOpacity(0.18),
              ),
              Expanded(
                child: _buildPresenceMetric(
                  icon: Icons.person_off_rounded,
                  label: 'Ausência sem check-in',
                  value: _acceptedButAbsentCount,
                  color: Colors.red,
                ),
              ),
              Container(
                width: 1,
                height: 48,
                color: Colors.grey.withOpacity(0.18),
              ),
              Expanded(
                child: _buildPresenceMetric(
                  icon: Icons.cancel,
                  label: 'Recusado',
                  value: _rejectedPresenceCount,
                  color: Colors.red,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPresenceMetric({
    required IconData icon,
    required String label,
    required int value,
    required Color color,
  }) {
    return Column(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(height: 6),
        Text(
          value.toString(),
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: Colors.grey[700],
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  // ignore: unused_element
  Widget _buildDashboardCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
    int? badgeCount,
    List<_DashboardBadgeData>? badges,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final screenWidth = MediaQuery.of(context).size.width;
        final availableWidth =
            constraints.maxWidth.isFinite ? constraints.maxWidth : screenWidth;
        final isCompact = availableWidth < 380;
        final horizontalMargin = isCompact ? 12.0 : 16.0;
        final verticalMargin = isCompact ? 8.0 : 10.0;
        final cardRadius = isCompact ? 18.0 : 20.0;
        final cardPadding = isCompact ? 16.0 : 18.0;
        final iconBoxSize = isCompact ? 54.0 : 60.0;
        final iconSize = isCompact ? 28.0 : 32.0;
        final titleSize = isCompact ? 17.0 : 18.0;
        final subtitleSize = isCompact ? 12.0 : 13.0;
        final arrowSize = isCompact ? 16.0 : 18.0;
        final badgeTop = isCompact ? 10.0 : 12.0;
        final badgeRight = isCompact ? 10.0 : 12.0;
        final visibleBadges = (badges ?? const <_DashboardBadgeData>[])
            .where((b) => b.count > 0)
            .toList();

        return Container(
          margin: EdgeInsets.symmetric(
            horizontal: horizontalMargin,
            vertical: verticalMargin,
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(cardRadius),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(cardRadius),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.white.withOpacity(0.24),
                          Colors.white.withOpacity(0.16),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(cardRadius),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.22),
                          blurRadius: 18,
                          offset: const Offset(0, 8),
                        ),
                        BoxShadow(
                          color: color.withOpacity(0.14),
                          blurRadius: 14,
                          spreadRadius: 0.8,
                        ),
                      ],
                      border: Border.all(
                        color: Colors.white.withOpacity(0.34),
                        width: 1.25,
                      ),
                    ),
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Positioned(
                          top: -20,
                          right: -12,
                          child: Container(
                            width: isCompact ? 68 : 76,
                            height: isCompact ? 68 : 76,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white.withOpacity(0.10),
                            ),
                          ),
                        ),
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: Container(
                            height: 1,
                            color: Colors.white.withOpacity(0.10),
                          ),
                        ),
                        Padding(
                          padding: EdgeInsets.all(cardPadding),
                          child: Row(
                            children: [
                              Container(
                                width: iconBoxSize,
                                height: iconBoxSize,
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.10),
                                  borderRadius: BorderRadius.circular(
                                      isCompact ? 14 : 16),
                                  border: Border.all(
                                    color: Colors.white.withOpacity(0.16),
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: color.withOpacity(0.16),
                                      blurRadius: 10,
                                      spreadRadius: 0.4,
                                    ),
                                  ],
                                ),
                                child: Icon(
                                  icon,
                                  size: iconSize,
                                  color: Colors.white,
                                ),
                              ),
                              SizedBox(width: isCompact ? 12 : 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: titleSize,
                                        fontWeight: FontWeight.w800,
                                        color: Colors.white,
                                        height: 1.05,
                                      ),
                                    ),
                                    SizedBox(height: isCompact ? 5 : 6),
                                    Text(
                                      subtitle,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: subtitleSize,
                                        color: Colors.white.withOpacity(0.88),
                                        fontWeight: FontWeight.w500,
                                        height: 1.22,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              SizedBox(width: isCompact ? 10 : 12),
                              Container(
                                width: isCompact ? 30 : 34,
                                height: isCompact ? 30 : 34,
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.08),
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.white.withOpacity(0.14),
                                  ),
                                ),
                                child: Icon(
                                  Icons.arrow_forward_ios_rounded,
                                  color: Colors.white.withOpacity(0.80),
                                  size: arrowSize,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (visibleBadges.isNotEmpty)
                          Positioned(
                            right: badgeRight,
                            top: badgeTop,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: visibleBadges
                                  .map(
                                    (badge) => Padding(
                                      padding: const EdgeInsets.only(bottom: 4),
                                      child: _buildDashboardBadge(
                                        count: badge.count,
                                        color: badge.color,
                                        isCompact: isCompact,
                                      ),
                                    ),
                                  )
                                  .toList(),
                            ),
                          )
                        else if (badgeCount != null && badgeCount > 0)
                          Positioned(
                            right: badgeRight,
                            top: badgeTop,
                            child: _buildDashboardBadge(
                              count: badgeCount,
                              color: Colors.red,
                              isCompact: isCompact,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildDashboardBadge({
    required int count,
    required Color color,
    required bool isCompact,
  }) {
    return Container(
      constraints: BoxConstraints(
        minWidth: isCompact ? 24 : 26,
      ),
      padding: EdgeInsets.symmetric(
        horizontal: isCompact ? 7 : 9,
        vertical: isCompact ? 4 : 5,
      ),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white, width: 1.8),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.38),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Text(
        count.toString(),
        textAlign: TextAlign.center,
        style: TextStyle(
          color: Colors.white,
          fontSize: isCompact ? 11.5 : 12.5,
          fontWeight: FontWeight.w800,
          height: 1,
        ),
      ),
    );
  }

  Widget _buildFloatingChatButton() {
    final screenWidth = MediaQuery.of(context).size.width;
    final isCompact = screenWidth < 380;

    return SafeArea(
      minimum: EdgeInsets.only(
        right: isCompact ? 6 : 8,
        bottom: isCompact ? 6 : 8,
      ),
      child: GestureDetector(
        onTap: _navigateToChat,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(isCompact ? 18 : 20),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: Container(
              padding: EdgeInsets.symmetric(
                horizontal: isCompact ? 14 : 16,
                vertical: isCompact ? 11 : 12,
              ),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.white.withOpacity(0.20),
                    olympusLightBlue.withOpacity(0.26),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(isCompact ? 18 : 20),
                boxShadow: [
                  BoxShadow(
                    color: olympusLightBlue.withOpacity(0.32),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ],
                border: Border.all(
                  color: Colors.white.withOpacity(0.30),
                  width: 1.1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.chat_bubble_rounded,
                    color: Colors.white,
                    size: isCompact ? 18 : 20,
                  ),
                  SizedBox(width: isCompact ? 6 : 8),
                  Text(
                    'Chat',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: isCompact ? 13 : 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAnimatedFinancialBadge() {
    return ScaleTransition(
      scale: _birthdayBadgeScale,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.red.shade700,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: Colors.red.shade900,
            width: 1.1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.red.withOpacity(0.24),
              blurRadius: 10,
              spreadRadius: 0.4,
            ),
          ],
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.notifications_active_rounded,
              size: 14,
              color: Colors.white,
            ),
            SizedBox(width: 6),
            Text(
              'Pendência financeira',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                color: Colors.white,
                height: 1.0,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFinancialAlertCard() {
    if (_overdueFinancialCount == 0) return const SizedBox.shrink();

    String monthMessage = '';
    final sortedMonths = _overdueByMonth.keys.toList()
      ..sort((a, b) => b.compareTo(a));

    for (int i = 0; i < sortedMonths.length; i++) {
      final month = sortedMonths[i];
      final count = _overdueByMonth[month]!;
      final monthName = DateFormat.MMMM('pt_BR').format(DateTime(2024, month));
      final monthNameCapitalized =
          monthName[0].toUpperCase() + monthName.substring(1);

      if (i > 0) {
        monthMessage += ' e ';
      }
      monthMessage +=
          '$count ${count == 1 ? "pagamento" : "pagamentos"} em atraso em $monthNameCapitalized';
    }

    return GestureDetector(
      onTap: _navigateToFinancial,
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Colors.red.shade50,
              Colors.red.shade100,
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: Colors.red.shade300,
            width: 2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.red.withOpacity(0.3),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: Colors.red.shade100,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.warning_rounded,
                  color: Colors.red.shade700,
                  size: 32,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildAnimatedFinancialBadge(),
                    const SizedBox(height: 8),
                    Text(
                      'Pendência financeira em atraso',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.red.shade900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      monthMessage,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.red.shade700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Acesse o financeiro e regularize o quanto antes.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.red.shade600,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios,
                color: Colors.red.shade400,
                size: 16,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPremiumDashboardBackground() {
    return Stack(
      children: [
        Positioned.fill(
          child: Opacity(
            opacity: 0.72,
            child: Image.asset(
              'assets/images/monte_olimpo_v2.png',
              fit: BoxFit.cover,
              alignment: Alignment.center,
              errorBuilder: (context, error, stackTrace) {
                return Container(color: const Color(0xFF102845));
              },
            ),
          ),
        ),
        Positioned.fill(
          child: Container(
            color: Colors.black.withOpacity(0.10),
          ),
        ),
        Positioned.fill(
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  olympusBlue.withOpacity(0.48),
                  olympusLightBlue.withOpacity(0.20),
                  Colors.black.withOpacity(0.60),
                ],
              ),
            ),
          ),
        ),
        Positioned.fill(
          child: Container(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(0, -0.62),
                radius: 1.18,
                colors: [
                  olympusGold.withOpacity(0.11),
                  Colors.transparent,
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAthleteCommandCenter() {
    final pendingInvites = _pendingCompetitionCount +
        _pendingTrainingCount +
        _pendingFriendlyCount;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            decoration: BoxDecoration(
              color: const Color(0xFF081D33).withOpacity(0.88),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white.withOpacity(0.12)),
            ),
            child: Row(
              children: [
                _buildAthleteStatusMetric(
                  value: '$pendingInvites',
                  label: 'Convocações',
                  color: olympusGold,
                ),
                _athleteStatusDivider(),
                _buildAthleteStatusMetric(
                  value: '$_messageUnreadCount',
                  label: 'Mensagens',
                  color: const Color(0xFFFF8FA3),
                ),
                _athleteStatusDivider(),
                _buildAthleteStatusMetric(
                  value: '$_overdueFinancialCount',
                  label: 'Financeiro',
                  color: const Color(0xFF8FE8FF),
                ),
              ],
            ),
          ),
          const SizedBox(height: 17),
          const Text(
            'Acesso imediato',
            style: TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 10),
          _buildAthleteQuickActions(),
          const SizedBox(height: 17),
          _buildCoachEvaluationFeaturedAction(),
          const SizedBox(height: 13),
          _buildAthleteSportsDirectory(),
        ],
      ),
    );
  }

  Widget _athleteStatusDivider() {
    return Container(
      width: 1,
      height: 34,
      margin: const EdgeInsets.symmetric(horizontal: 8),
      color: Colors.white.withOpacity(0.12),
    );
  }

  Widget _buildAthleteStatusMetric({
    required String value,
    required String label,
    required Color color,
  }) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 20,
              fontWeight: FontWeight.w900,
              height: 1,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white60, fontSize: 10.5),
          ),
        ],
      ),
    );
  }

  Widget _buildAthleteQuickActions() {
    final actions = <({
      String label,
      IconData icon,
      Color color,
      int badge,
      VoidCallback onTap,
    })>[
      (
        label: 'Agenda',
        icon: Icons.calendar_month_rounded,
        color: olympusGold,
        badge: _pendingTrainingCount +
            _pendingFriendlyCount +
            _pendingCompetitionCount,
        onTap: _navigateToAgenda,
      ),
      (
        label: 'Estatísticas',
        icon: Icons.query_stats_rounded,
        color: const Color(0xFF73E2A7),
        badge: 0,
        onTap: _navigateToStatistics,
      ),
      (
        label: 'Mensagens',
        icon: Icons.forum_rounded,
        color: const Color(0xFFFF8FA3),
        badge: _messageUnreadCount,
        onTap: _navigateToMessages,
      ),
      if (_canAccessChat)
        (
          label: 'Chat',
          icon: Icons.chat_bubble_rounded,
          color: const Color(0xFF25D366),
          badge: _chatUnreadCount,
          onTap: _navigateToChat,
        ),
      (
        label: 'Financeiro',
        icon: Icons.account_balance_wallet_rounded,
        color: const Color(0xFF8FE8FF),
        badge: _overdueFinancialCount + _newFinancialCount,
        onTap: _navigateToFinancial,
      ),
    ];

    return SizedBox(
      width: double.infinity,
      height: 88,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final itemWidth =
              ((constraints.maxWidth - 32) / actions.length).clamp(54.0, 70.0);
          return Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: actions.indexed.map((entry) {
              final index = entry.$1;
              final action = entry.$2;
              return Padding(
                padding: EdgeInsets.only(left: index == 0 ? 0 : 8),
                child: _buildAthleteQuickAction(
                  width: itemWidth,
                  label: action.label,
                  icon: action.icon,
                  color: action.color,
                  badge: action.badge,
                  onTap: action.onTap,
                ),
              );
            }).toList(),
          );
        },
      ),
    );
  }

  Widget _buildAthleteQuickAction({
    required double width,
    required String label,
    required IconData icon,
    required Color color,
    required int badge,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      width: width,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Column(
          children: [
            Badge(
              isLabelVisible: badge > 0,
              label: Text(badge > 99 ? '99+' : '$badge'),
              backgroundColor: Colors.redAccent,
              child: Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color.withOpacity(0.16),
                  border: Border.all(color: color.withOpacity(0.52)),
                  boxShadow: [
                    BoxShadow(
                      color: color.withOpacity(0.14),
                      blurRadius: 12,
                    ),
                  ],
                ),
                child: Icon(icon, color: color, size: 25),
              ),
            ),
            const SizedBox(height: 7),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 10.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCoachEvaluationFeaturedAction() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _navigateToCoachEvaluation,
        borderRadius: BorderRadius.circular(22),
        child: Ink(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            gradient: const LinearGradient(
              colors: [Color(0xFF64FFDA), Color(0xFF25BFA5)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x3364FFDA),
                blurRadius: 18,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.22),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.rate_review_rounded,
                  color: Color(0xFF0A3340),
                  size: 25,
                ),
              ),
              const SizedBox(width: 13),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Avaliar meu treinador',
                      style: TextStyle(
                        color: Color(0xFF0A3340),
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Compartilhe sua experiência no treino',
                      style: TextStyle(
                        color: Color(0xCC0A3340),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.arrow_forward_rounded,
                color: Color(0xFF0A3340),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAthleteSportsDirectory() {
    final items = <({
      String label,
      String subtitle,
      IconData icon,
      Color color,
      int badge,
      VoidCallback onTap,
    })>[
      (
        label: 'Competições',
        subtitle: 'Ligas, campeonatos e amistosos',
        icon: Icons.emoji_events_rounded,
        color: const Color(0xFF70E1F5),
        badge: _competitionNewCount,
        onTap: _navigateToCompetitions,
      ),
      if (_canAccessBirthdays)
        (
          label: 'Aniversariantes',
          subtitle: 'Datas especiais da equipe',
          icon: Icons.cake_rounded,
          color: const Color(0xFFFF86C8),
          badge: 0,
          onTap: _navigateToBirthdays,
        ),
    ];

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF102D4F).withOpacity(0.88),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withOpacity(0.13)),
      ),
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(15, 14, 15, 7),
            child: Row(
              children: [
                Text(
                  'Meu time',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Spacer(),
                Text(
                  'OLYMPUS',
                  style: TextStyle(
                    color: olympusGold,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.2,
                  ),
                ),
              ],
            ),
          ),
          ...items.indexed.map((entry) {
            final index = entry.$1;
            final item = entry.$2;
            return Column(
              children: [
                if (index > 0)
                  Divider(
                    height: 1,
                    indent: 65,
                    color: Colors.white.withOpacity(0.09),
                  ),
                ListTile(
                  onTap: item.onTap,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 3,
                  ),
                  leading: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: item.color.withOpacity(0.14),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(item.icon, color: item.color, size: 21),
                  ),
                  title: Text(
                    item.label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 13.5,
                    ),
                  ),
                  subtitle: Text(
                    item.subtitle,
                    style: const TextStyle(color: Colors.white54, fontSize: 11),
                  ),
                  trailing: item.badge > 0
                      ? Badge(
                          label: Text('${item.badge}'),
                          backgroundColor: Colors.redAccent,
                        )
                      : const Icon(
                          Icons.chevron_right_rounded,
                          color: Colors.white38,
                        ),
                ),
              ],
            );
          }),
          const SizedBox(height: 6),
        ],
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _birthdayBadgeController.dispose();
    _presenceBlinkController.dispose();
    if (_messagesRealtimeChannel != null) {
      supabase.removeChannel(_messagesRealtimeChannel!);
    }
    if (_messageThreadsRealtimeChannel != null) {
      supabase.removeChannel(_messageThreadsRealtimeChannel!);
    }
    if (_messageParticipantsRealtimeChannel != null) {
      supabase.removeChannel(_messageParticipantsRealtimeChannel!);
    }
    if (_competitionsRealtimeChannel != null) {
      supabase.removeChannel(_competitionsRealtimeChannel!);
    }
    if (_convocationsRealtimeChannel != null) {
      supabase.removeChannel(_convocationsRealtimeChannel!);
    }
    if (_financialRealtimeChannel != null) {
      supabase.removeChannel(_financialRealtimeChannel!);
    }
    if (_checkinsRealtimeChannel != null) {
      supabase.removeChannel(_checkinsRealtimeChannel!);
    }
    if (_profilesRealtimeChannel != null) {
      supabase.removeChannel(_profilesRealtimeChannel!);
    }
    if (_monthlyHistoryRealtimeChannel != null) {
      supabase.removeChannel(_monthlyHistoryRealtimeChannel!);
    }
    if (_trainingEvaluationsRealtimeChannel != null) {
      supabase.removeChannel(_trainingEvaluationsRealtimeChannel!);
    }
    _dashboardBadgeFallbackTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF102845),
      appBar: _isLoading
          ? null
          : AppBar(
              title: const Text('Área do Atleta'),
              backgroundColor: olympusBlue,
              foregroundColor: Colors.white,
              actions: [
                IconButton(
                  icon: const Icon(Icons.person, color: Colors.white),
                  tooltip: 'Perfil',
                  onPressed: _navigateToProfilePage,
                ),
                IconButton(
                  icon: const Icon(Icons.logout),
                  tooltip: 'Sair',
                  onPressed: _redirectToLogin,
                ),
              ],
            ),
      body: Stack(
        children: [
          Positioned.fill(
            child: _buildPremiumDashboardBackground(),
          ),
          if (_isLoading)
            const Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            )
          else
            SafeArea(
              top: false,
              minimum: const EdgeInsets.only(bottom: 12),
              child: SingleChildScrollView(
                padding: const EdgeInsets.only(bottom: 92),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    _buildAthleteInfoCard(),
                    _buildAthleteCommandCenter(),
                    _buildTodayBirthdaysCard(),
                    _buildFinancialAlertCard(),
                    _buildPresenceSummaryCard(),
                    _buildGenderRankingCard(),
                    _buildWeekEventsSectionCard(),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _DashboardBadgeData {
  final int count;
  final Color color;

  const _DashboardBadgeData({
    required this.count,
    required this.color,
  });
}

enum _MiniChartType {
  line,
  barsRed,
  grid,
}

class _MiniLinePainter extends CustomPainter {
  final Color color;
  _MiniLinePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final glowPaint = Paint()
      ..color = color.withOpacity(0.35)
      ..strokeWidth = 5
      ..style = PaintingStyle.stroke
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);

    final dotPaint = Paint()..color = color;

    final path = Path();
    final points = [
      Offset(0, size.height - 10),
      Offset(size.width * 0.20, size.height - 11),
      Offset(size.width * 0.40, size.height - 8),
      Offset(size.width * 0.60, size.height - 12),
      Offset(size.width * 0.80, size.height - 4),
      Offset(size.width, size.height - 7),
    ];

    path.moveTo(points.first.dx, points.first.dy);
    for (final point in points.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }

    canvas.drawPath(path, glowPaint);
    canvas.drawPath(path, linePaint);
    canvas.drawCircle(points.last, 2.8, dotPaint);
  }

  @override
  bool shouldRepaint(covariant _MiniLinePainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

// ============================================================================
// TELA DE PERFIL COMPLETA DO ATLETA
// ============================================================================
class AthleteProfilePage extends StatefulWidget {
  final Map<String, dynamic>? profile;
  const AthleteProfilePage({super.key, this.profile});

  @override
  State<AthleteProfilePage> createState() => _AthleteProfilePageState();
}

class _AthleteProfilePageState extends State<AthleteProfilePage> {
  final supabase = Supabase.instance.client;
  final _authService = AuthService();
  final PermissionService _permissionService = PermissionService();
  static const Color olympusBlue = Color(0xFF1E3A5F);
  static const Color olympusGold = Color(0xFFD4AF37);
  static const Color olympusLightBlue = Color(0xFF2C5F8D);

  void _showChangePasswordDialog() {
    final currentPasswordCtrl = TextEditingController();
    final newPasswordCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    bool _isLoading = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.lock, color: olympusGold),
              const SizedBox(width: 8),
              const Text('Mudar Senha'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: currentPasswordCtrl,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: 'Senha Atual *',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.lock, color: olympusGold),
                  focusedBorder: OutlineInputBorder(
                    borderSide: const BorderSide(color: olympusGold, width: 2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: newPasswordCtrl,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: 'Nova Senha *',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.lock, color: olympusGold),
                  focusedBorder: OutlineInputBorder(
                    borderSide: const BorderSide(color: olympusGold, width: 2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: confirmCtrl,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: 'Confirmar Nova Senha *',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.lock, color: olympusGold),
                  focusedBorder: OutlineInputBorder(
                    borderSide: const BorderSide(color: olympusGold, width: 2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: _isLoading
                  ? null
                  : () async {
                      if (newPasswordCtrl.text != confirmCtrl.text) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('As senhas não conferem'),
                            backgroundColor: Colors.red,
                          ),
                        );
                        return;
                      }
                      if (newPasswordCtrl.text.length < 6) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Mínimo 6 caracteres'),
                            backgroundColor: Colors.red,
                          ),
                        );
                        return;
                      }
                      setDialogState(() => _isLoading = true);
                      try {
                        final user = supabase.auth.currentUser;
                        if (user == null || user.email == null) {
                          throw Exception('Usuário não autenticado');
                        }
                        try {
                          await supabase.auth.signInWithPassword(
                            email: user.email!,
                            password: currentPasswordCtrl.text,
                          );
                        } catch (e) {
                          throw Exception('Senha atual incorreta');
                        }
                        await supabase.auth.updateUser(
                          UserAttributes(password: newPasswordCtrl.text),
                        );
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('✅ Senha alterada com sucesso!'),
                            backgroundColor: olympusBlue,
                          ),
                        );
                        Navigator.pop(context);
                      } catch (e) {
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Erro: ${e.toString()}'),
                            backgroundColor: Colors.red,
                          ),
                        );
                      } finally {
                        if (mounted) {
                          setDialogState(() => _isLoading = false);
                        }
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: olympusGold,
                foregroundColor: olympusBlue,
              ),
              child: _isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(olympusBlue),
                      ),
                    )
                  : const Text('Salvar'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDeleteAccount() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Excluir conta'),
        content: const Text(
          'Essa ação é permanente e apagará sua conta e seus dados vinculados. Deseja continuar?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Excluir conta'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Expanded(
              child: Text('Excluindo conta...'),
            ),
          ],
        ),
      ),
    );

    final result = await _authService.deleteMyAccount();

    if (!mounted) return;

    Navigator.of(context, rootNavigator: true).pop();

    if (result['success'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Conta excluída com sucesso'),
          backgroundColor: olympusBlue,
        ),
      );
      Navigator.pushNamedAndRemoveUntil(
        context,
        '/login',
        (route) => false,
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result['error'] ?? 'Erro ao excluir conta'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = widget.profile;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Meu Perfil'),
        backgroundColor: olympusBlue,
        foregroundColor: Colors.white,
        elevation: 2,
      ),
      body: profile == null
          ? Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(olympusGold),
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Column(
                      children: [
                        CircleAvatar(
                          radius: 60,
                          backgroundColor: olympusGold.withOpacity(0.2),
                          backgroundImage: profile['avatar_url'] != null &&
                                  profile['avatar_url'].toString().isNotEmpty
                              ? NetworkImage(profile['avatar_url'])
                              : null,
                          child: profile['avatar_url'] == null ||
                                  profile['avatar_url'].toString().isEmpty
                              ? Text(
                                  profile['full_name']?[0]?.toUpperCase() ??
                                      '?',
                                  style: const TextStyle(
                                    fontSize: 40,
                                    fontWeight: FontWeight.bold,
                                    color: olympusBlue,
                                  ),
                                )
                              : null,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          profile['full_name'] ?? 'Sem nome',
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: olympusBlue,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        Text(
                          _getUserTypeLabel(profile['user_type']),
                          style: TextStyle(
                            fontSize: 16,
                            color: olympusGold,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) =>
                                    _AthleteProfileEditDialog(profile: profile),
                              ),
                            ).then((_) => Navigator.pop(context, true));
                          },
                          icon: const Icon(Icons.edit),
                          label: const Text('Alterar Dados'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: olympusGold,
                            foregroundColor: olympusBlue,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _showChangePasswordDialog,
                          icon: const Icon(Icons.lock),
                          label: const Text('Alterar Senha'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: olympusBlue,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _confirmDeleteAccount,
                      icon: const Icon(Icons.delete_forever),
                      label: const Text('Excluir conta'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  _buildSectionTitle('Dados Pessoais'),
                  _buildInfoTile(Icons.person, 'Nome', profile['full_name']),
                  _buildInfoTile(Icons.email, 'E-mail',
                      profile['email'] ?? 'Não informado'),
                  _buildInfoTile(
                      Icons.phone, 'Telefone', _formatPhone(profile['phone'])),
                  _buildInfoTile(
                      Icons.credit_card, 'CPF', _formatCpf(profile['cpf'])),
                  _buildInfoTile(
                      Icons.badge, 'RG', profile['rg'] ?? 'Não informado'),
                  _buildInfoTile(Icons.calendar_today, 'Data de Nascimento',
                      _formatDate(profile['birth_date'])),
                  _buildInfoTile(
                      Icons.transgender, 'Gênero', profile['gender']),
                  if (profile['court_position'] != null &&
                      profile['court_position'].toString().isNotEmpty)
                    _buildInfoTile(Icons.sports_volleyball, 'Posição na Quadra',
                        profile['court_position']),
                  const SizedBox(height: 24),
                  _buildSectionTitle('Endereço'),
                  _buildInfoTile(Icons.location_on, 'CEP',
                      _formatCep(profile['zip_code'])),
                  _buildInfoTile(Icons.home, 'Rua', profile['street']),
                  _buildInfoTile(Icons.pin, 'Número', profile['street_number']),
                  if (profile['complement'] != null &&
                      profile['complement'].toString().isNotEmpty)
                    _buildInfoTile(
                        Icons.apartment, 'Complemento', profile['complement']),
                  _buildInfoTile(
                      Icons.location_city, 'Bairro', profile['neighborhood']),
                  _buildInfoTile(
                      Icons.location_city, 'Cidade', profile['city']),
                  _buildInfoTile(Icons.public, 'Estado', profile['state']),
                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 20,
            decoration: BoxDecoration(
              color: olympusGold,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: olympusBlue,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoTile(IconData icon, String label, String? value) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: olympusGold.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: olympusGold, size: 20),
      ),
      title: Text(
        label,
        style: const TextStyle(fontSize: 12, color: Colors.grey),
      ),
      subtitle: Text(
        value ?? 'Não informado',
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w500,
          color: olympusBlue,
        ),
      ),
      contentPadding: EdgeInsets.zero,
    );
  }

  String _formatPhone(String? phone) {
    if (phone == null) return 'Não informado';
    final numbers = phone.replaceAll(RegExp(r'\D'), '');
    if (numbers.length == 11) {
      return '(${numbers.substring(0, 2)}) ${numbers.substring(2, 7)}-${numbers.substring(7)}';
    } else if (numbers.length == 10) {
      return '(${numbers.substring(0, 2)}) ${numbers.substring(2, 6)}-${numbers.substring(6)}';
    }
    return phone;
  }

  String _formatCpf(String? cpf) {
    if (cpf == null) return 'Não informado';
    final numbers = cpf.replaceAll(RegExp(r'\D'), '');
    if (numbers.length != 11) return cpf;
    return '${numbers.substring(0, 3)}.${numbers.substring(3, 6)}.${numbers.substring(6, 9)}-${numbers.substring(9)}';
  }

  String _formatCep(String? cep) {
    if (cep == null) return 'Não informado';
    final numbers = cep.replaceAll(RegExp(r'\D'), '');
    if (numbers.length != 8) return cep;
    return '${numbers.substring(0, 5)}-${numbers.substring(5)}';
  }

  String _formatDate(String? date) {
    if (date == null) return 'Não informado';
    try {
      final dt = DateTime.parse(date);
      return DateFormat('dd/MM/yyyy').format(dt);
    } catch (e) {
      return date;
    }
  }

  String _getUserTypeLabel(String? userType) {
    switch (userType) {
      case 'athlete':
        return 'Atleta';
      case 'coach':
        return 'Técnico';
      case 'admin':
        return 'Administrador';
      default:
        return 'Membro';
    }
  }
}

// ============================================================================
// DIÁLOGO DE EDIÇÃO DE PERFIL (COM FILTRO DE POSIÇÃO POR GÊNERO)
// ============================================================================
class _AthleteProfileEditDialog extends StatefulWidget {
  final Map<String, dynamic> profile;
  const _AthleteProfileEditDialog({required this.profile});

  @override
  State<_AthleteProfileEditDialog> createState() =>
      _AthleteProfileEditDialogState();
}

class _AthleteProfileEditDialogState extends State<_AthleteProfileEditDialog> {
  final _formKey = GlobalKey<FormState>();
  final _picker = ImagePicker();
  final supabase = Supabase.instance.client;
  late TextEditingController _fullNameController;
  late MaskedTextController _phoneController;
  late TextEditingController _birthDateController;
  late MaskedTextController _rgController;
  late MaskedTextController _cpfController;
  late TextEditingController _genderController;
  late TextEditingController _positionController;
  late MaskedTextController _zipCodeController;
  late TextEditingController _streetController;
  late TextEditingController _streetNumberController;
  late TextEditingController _complementController;
  late TextEditingController _neighborhoodController;
  late TextEditingController _cityController;
  late TextEditingController _stateController;
  XFile? _selectedImage;
  bool _isLoading = false;
  bool _isUploading = false;
  bool _isFetchingCep = false;
  String _selectedGender = '';
  static const Color olympusBlue = Color(0xFF1E3A5F);
  static const Color olympusGold = Color(0xFFD4AF37);
  static const Color olympusLightBlue = Color(0xFF2C5F8D);

  final Map<String, List<Map<String, String>>> _positions = {
    'Masculino': [
      {'value': 'Ponteiro', 'label': 'Ponteiro'},
      {'value': 'Levantador', 'label': 'Levantador'},
      {'value': 'Central', 'label': 'Central'},
      {'value': 'Oposto', 'label': 'Oposto'},
      {'value': 'Líbero', 'label': 'Líbero'},
    ],
    'Feminino': [
      {'value': 'Ponteira', 'label': 'Ponteira'},
      {'value': 'Levantadora', 'label': 'Levantadora'},
      {'value': 'Central', 'label': 'Central'},
      {'value': 'Oposta', 'label': 'Oposta'},
      {'value': 'Líbero', 'label': 'Líbero'},
    ],
  };

  @override
  void initState() {
    super.initState();
    _fullNameController =
        TextEditingController(text: widget.profile['full_name'] ?? '');
    _phoneController = MaskedTextController(
        mask: '(00) 00000-0000', text: widget.profile['phone'] ?? '');
    _birthDateController =
        TextEditingController(text: widget.profile['birth_date'] ?? '');
    _rgController = MaskedTextController(
        mask: '00.000.000-0', text: widget.profile['rg'] ?? '');
    _cpfController = MaskedTextController(
        mask: '000.000.000-00', text: widget.profile['cpf'] ?? '');
    _genderController =
        TextEditingController(text: widget.profile['gender'] ?? '');
    _positionController =
        TextEditingController(text: widget.profile['court_position'] ?? '');
    _zipCodeController = MaskedTextController(
        mask: '00000-000', text: widget.profile['zip_code'] ?? '');
    _streetController =
        TextEditingController(text: widget.profile['street'] ?? '');
    _streetNumberController =
        TextEditingController(text: widget.profile['street_number'] ?? '');
    _complementController =
        TextEditingController(text: widget.profile['complement'] ?? '');
    _neighborhoodController =
        TextEditingController(text: widget.profile['neighborhood'] ?? '');
    _cityController = TextEditingController(text: widget.profile['city'] ?? '');
    _stateController =
        TextEditingController(text: widget.profile['state'] ?? '');
    _selectedGender = widget.profile['gender'] ?? '';
    _zipCodeController.addListener(_onZipCodeChanged);
  }

  void _onZipCodeChanged() {
    final cep = _zipCodeController.text.replaceAll(RegExp(r'\D'), '');
    if (cep.length == 8 && !_isFetchingCep) {
      _fetchAddressByCep(cep);
    }
  }

  Future<void> _fetchAddressByCep(String cep) async {
    setState(() => _isFetchingCep = true);
    try {
      final response =
          await http.get(Uri.parse('https://viacep.com.br/ws/$cep/json/'));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['erro'] == null && mounted) {
          setState(() {
            _streetController.text = data['logradouro'] ?? '';
            _neighborhoodController.text = data['bairro'] ?? '';
            _cityController.text = data['localidade'] ?? '';
            _stateController.text = data['uf'] ?? '';
          });
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('✅ Endereço preenchido automaticamente!'),
                duration: Duration(seconds: 2),
                backgroundColor: olympusBlue,
              ),
            );
          }
        }
      }
    } catch (e) {
      debugPrint('Erro ao buscar CEP: $e');
    } finally {
      if (mounted) {
        setState(() => _isFetchingCep = false);
      }
    }
  }

  Future<void> _pickImage() async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 85,
      );
      if (image != null && mounted) {
        setState(() {
          _selectedImage = image;
        });
      }
    } catch (e) {
      debugPrint('Erro ao selecionar imagem: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Erro ao selecionar imagem'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<String?> _uploadImage() async {
    if (_selectedImage == null) return null;
    setState(() => _isUploading = true);
    try {
      final user = supabase.auth.currentUser;
      final fileName =
          '${DateTime.now().millisecondsSinceEpoch}_${user?.id}.jpg';
      final Uint8List? fileBytes = await _selectedImage!.readAsBytes();
      if (fileBytes == null) return null;
      await supabase.storage.from('avatars').uploadBinary(fileName, fileBytes,
          fileOptions: const FileOptions(upsert: true));
      final publicUrl = supabase.storage.from('avatars').getPublicUrl(fileName);
      return publicUrl;
    } catch (e) {
      debugPrint('Erro ao fazer upload: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao fazer upload: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return null;
    } finally {
      if (mounted) {
        setState(() => _isUploading = false);
      }
    }
  }

  Future<void> _selectDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: olympusGold,
              onPrimary: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null && mounted) {
      setState(() {
        _birthDateController.text = DateFormat('dd/MM/yyyy').format(picked);
      });
    }
  }

  String _removeMask(String? text) {
    if (text == null || text.isEmpty) return '';
    return text.replaceAll(RegExp(r'\D'), '');
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      String? avatarUrl;
      if (_selectedImage != null) {
        avatarUrl = await _uploadImage();
      }
      final user = supabase.auth.currentUser;
      if (user == null) throw Exception('Usuário não autenticado');
      final data = <String, dynamic>{
        'full_name': _fullNameController.text.trim(),
        'phone': _removeMask(_phoneController.text),
        'birth_date': _birthDateController.text,
        'rg': _removeMask(_rgController.text),
        'cpf': _removeMask(_cpfController.text),
        'gender': _genderController.text.trim(),
        'court_position': _positionController.text.trim(),
        'zip_code': _removeMask(_zipCodeController.text),
        'street': _streetController.text.trim(),
        'street_number': _streetNumberController.text.trim(),
        'complement': _complementController.text.trim(),
        'neighborhood': _neighborhoodController.text.trim(),
        'city': _cityController.text.trim(),
        'state': _stateController.text.trim().toUpperCase(),
        'updated_at': DateTime.now().toIso8601String(),
        if (avatarUrl != null) 'avatar_url': avatarUrl,
      };
      await supabase.from('profiles').update(data).eq('id', user.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Perfil atualizado com sucesso!'),
          backgroundColor: olympusBlue,
        ),
      );
      Navigator.pop(context);
    } catch (e) {
      debugPrint('❌ Erro ao salvar perfil: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao salvar: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Editar Perfil'),
        backgroundColor: olympusBlue,
        foregroundColor: Colors.white,
        elevation: 2,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: GestureDetector(
                  onTap: _pickImage,
                  child: Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      color: olympusGold.withOpacity(0.1),
                      shape: BoxShape.circle,
                      border: Border.all(color: olympusGold, width: 3),
                    ),
                    child: ClipOval(
                      child: _getAvatarImage(),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Center(
                child: TextButton.icon(
                  onPressed: _pickImage,
                  icon: const Icon(Icons.photo_camera, color: olympusGold),
                  label: const Text(
                    'Selecionar Foto',
                    style: TextStyle(color: olympusBlue),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _fullNameController,
                decoration: InputDecoration(
                  labelText: 'Nome Completo *',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.person, color: olympusGold),
                  focusedBorder: OutlineInputBorder(
                    borderSide: const BorderSide(color: olympusGold, width: 2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                validator: (value) =>
                    value?.isEmpty ?? true ? 'Campo obrigatório' : null,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _cpfController,
                      decoration: InputDecoration(
                        labelText: 'CPF *',
                        border: const OutlineInputBorder(),
                        prefixIcon:
                            const Icon(Icons.credit_card, color: olympusGold),
                        focusedBorder: OutlineInputBorder(
                          borderSide:
                              const BorderSide(color: olympusGold, width: 2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      keyboardType: TextInputType.number,
                      validator: (value) => _removeMask(value).length != 11
                          ? 'CPF inválido'
                          : null,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      controller: _rgController,
                      decoration: InputDecoration(
                        labelText: 'RG *',
                        border: const OutlineInputBorder(),
                        prefixIcon:
                            const Icon(Icons.credit_card, color: olympusGold),
                        focusedBorder: OutlineInputBorder(
                          borderSide:
                              const BorderSide(color: olympusGold, width: 2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      keyboardType: TextInputType.number,
                      validator: (value) =>
                          value?.isEmpty ?? true ? 'Campo obrigatório' : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _phoneController,
                      decoration: InputDecoration(
                        labelText: 'Telefone *',
                        border: const OutlineInputBorder(),
                        prefixIcon: const Icon(Icons.phone, color: olympusGold),
                        focusedBorder: OutlineInputBorder(
                          borderSide:
                              const BorderSide(color: olympusGold, width: 2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      keyboardType: TextInputType.phone,
                      validator: (value) => _removeMask(value).length < 10
                          ? 'Telefone inválido'
                          : null,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value:
                          _selectedGender.isNotEmpty ? _selectedGender : null,
                      decoration: InputDecoration(
                        labelText: 'Gênero *',
                        border: const OutlineInputBorder(),
                        prefixIcon:
                            const Icon(Icons.transgender, color: olympusGold),
                        focusedBorder: OutlineInputBorder(
                          borderSide:
                              const BorderSide(color: olympusGold, width: 2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      items: const [
                        DropdownMenuItem(
                            value: 'Masculino', child: Text('Masculino')),
                        DropdownMenuItem(
                            value: 'Feminino', child: Text('Feminino')),
                      ],
                      onChanged: (value) {
                        setState(() {
                          _selectedGender = value ?? '';
                          _positionController.text = '';
                          _genderController.text = value ?? '';
                        });
                      },
                      validator: (value) =>
                          value == null ? 'Campo obrigatório' : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _birthDateController,
                decoration: InputDecoration(
                  labelText: 'Data de Nascimento',
                  border: const OutlineInputBorder(),
                  prefixIcon:
                      const Icon(Icons.calendar_today, color: olympusGold),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.calendar_today, color: olympusGold),
                    onPressed: _selectDate,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: const BorderSide(color: olympusGold, width: 2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                readOnly: true,
              ),
              const SizedBox(height: 12),
              if (_selectedGender.isNotEmpty)
                DropdownButtonFormField<String>(
                  value: _positionController.text.isNotEmpty
                      ? _positionController.text
                      : null,
                  decoration: InputDecoration(
                    labelText: 'Posição na Quadra',
                    border: const OutlineInputBorder(),
                    prefixIcon:
                        const Icon(Icons.sports_volleyball, color: olympusGold),
                    focusedBorder: OutlineInputBorder(
                      borderSide:
                          const BorderSide(color: olympusGold, width: 2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  items: (_positions[_selectedGender] ?? [])
                      .map((pos) => DropdownMenuItem(
                            value: pos['value'],
                            child: Text(pos['label']!),
                          ))
                      .toList(),
                  onChanged: (value) =>
                      setState(() => _positionController.text = value ?? ''),
                ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Icon(Icons.location_on, color: olympusGold, size: 20),
                  const SizedBox(width: 8),
                  const Text(
                    'Endereço',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: olympusBlue,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _zipCodeController,
                decoration: InputDecoration(
                  labelText: 'CEP *',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.location_on, color: olympusGold),
                  suffixIcon: _isFetchingCep
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(olympusGold),
                          ),
                        )
                      : null,
                  focusedBorder: OutlineInputBorder(
                    borderSide: const BorderSide(color: olympusGold, width: 2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                keyboardType: TextInputType.number,
                maxLength: 9,
                validator: (value) =>
                    _removeMask(value).length != 8 ? 'CEP inválido' : null,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: TextFormField(
                      controller: _streetController,
                      decoration: InputDecoration(
                        labelText: 'Rua *',
                        border: const OutlineInputBorder(),
                        focusedBorder: OutlineInputBorder(
                          borderSide:
                              const BorderSide(color: olympusGold, width: 2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      validator: (value) =>
                          value?.isEmpty ?? true ? 'Campo obrigatório' : null,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      controller: _streetNumberController,
                      decoration: InputDecoration(
                        labelText: 'Número *',
                        border: const OutlineInputBorder(),
                        focusedBorder: OutlineInputBorder(
                          borderSide:
                              const BorderSide(color: olympusGold, width: 2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      keyboardType: TextInputType.number,
                      validator: (value) =>
                          value?.isEmpty ?? true ? 'Campo obrigatório' : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _complementController,
                decoration: InputDecoration(
                  labelText: 'Complemento',
                  border: const OutlineInputBorder(),
                  focusedBorder: OutlineInputBorder(
                    borderSide: const BorderSide(color: olympusGold, width: 2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _neighborhoodController,
                decoration: InputDecoration(
                  labelText: 'Bairro *',
                  border: const OutlineInputBorder(),
                  focusedBorder: OutlineInputBorder(
                    borderSide: const BorderSide(color: olympusGold, width: 2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                validator: (value) =>
                    value?.isEmpty ?? true ? 'Campo obrigatório' : null,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: TextFormField(
                      controller: _cityController,
                      decoration: InputDecoration(
                        labelText: 'Cidade *',
                        border: const OutlineInputBorder(),
                        focusedBorder: OutlineInputBorder(
                          borderSide:
                              const BorderSide(color: olympusGold, width: 2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      validator: (value) =>
                          value?.isEmpty ?? true ? 'Campo obrigatório' : null,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      controller: _stateController,
                      decoration: InputDecoration(
                        labelText: 'Estado *',
                        border: const OutlineInputBorder(),
                        focusedBorder: OutlineInputBorder(
                          borderSide:
                              const BorderSide(color: olympusGold, width: 2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      maxLength: 2,
                      validator: (value) =>
                          value?.isEmpty ?? true ? 'Campo obrigatório' : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),
              SizedBox(
                height: 50,
                child: ElevatedButton(
                  onPressed: _isLoading || _isUploading ? null : _saveProfile,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: olympusGold,
                    foregroundColor: olympusBlue,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 2,
                    shadowColor: olympusGold.withOpacity(0.4),
                  ),
                  child: _isLoading || _isUploading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(olympusBlue),
                          ),
                        )
                      : const Text(
                          'Salvar Alterações',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _getAvatarImage() {
    if (_selectedImage != null) {
      return FutureBuilder<Uint8List?>(
        future: _selectedImage!.readAsBytes(),
        builder: (context, snapshot) {
          if (snapshot.hasData && snapshot.data != null) {
            return Image.memory(snapshot.data!, fit: BoxFit.cover);
          }
          return const Icon(Icons.person, size: 60, color: Colors.grey);
        },
      );
    }
    if (widget.profile['avatar_url'] != null &&
        widget.profile['avatar_url'].toString().isNotEmpty) {
      return Image.network(
        widget.profile['avatar_url'],
        fit: BoxFit.cover,
        errorBuilder: (c, o, s) =>
            const Icon(Icons.person, size: 60, color: Colors.grey),
      );
    }
    return const Icon(Icons.person, size: 60, color: Colors.grey);
  }

  @override
  void dispose() {
    _zipCodeController.removeListener(_onZipCodeChanged);
    _fullNameController.dispose();
    _phoneController.dispose();
    _birthDateController.dispose();
    _rgController.dispose();
    _cpfController.dispose();
    _genderController.dispose();
    _positionController.dispose();
    _zipCodeController.dispose();
    _streetController.dispose();
    _streetNumberController.dispose();
    _complementController.dispose();
    _neighborhoodController.dispose();
    _cityController.dispose();
    _stateController.dispose();
    super.dispose();
  }
}
