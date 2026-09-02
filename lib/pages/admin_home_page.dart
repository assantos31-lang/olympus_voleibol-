import 'dart:async';
import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/auth_service.dart';
import '../services/chat_service.dart';
import '../services/permission_service.dart';
import '../services/platform_admin_service.dart';
import '../theme/olympus_theme.dart';
import 'agenda_page.dart';
import 'admin_branding_page.dart';
import 'admin_birthdays_page.dart';
import 'admin_checkin_ranking_page.dart';
import 'admin_competitions_page.dart';
import 'admin_financial_page.dart';
import 'admin_messages_page.dart';
import 'admin_training_plans_page.dart' show AdminTrainingPlansPage;
import 'admin_technical_staff_page.dart';
import 'chat_rooms_page.dart';
import 'platform_master_page.dart';

class AdminHomePage extends StatefulWidget {
  const AdminHomePage({super.key});

  @override
  State<AdminHomePage> createState() => _AdminHomePageState();
}

class _AdminHomePageState extends State<AdminHomePage>
    with WidgetsBindingObserver {
  final supabase = Supabase.instance.client;
  final PermissionService _permissionService = PermissionService();
  final ChatService _chatService = ChatService();
  Map<String, bool> _adminPermissions = {};
  bool _isPlatformAdmin = false;

  List<Map<String, dynamic>> allBirthdays = [];
  List<Map<String, dynamic>> monthBirthdays = [];
  bool isLoadingBirthdays = true;
  bool _showAllMonthBirthdays = false;
  int pendingFinancialReceiptsCount = 0;
  int overdueFinancialRecordsCount = 0;
  int pendingFinancialRecordsCount = 0;
  RealtimeChannel? _financialReceiptsChannel;
  RealtimeChannel? _birthdaysRealtimeChannel;
  RealtimeChannel? _messagesParticipantsRealtimeChannel;
  RealtimeChannel? _messagesRealtimeChannel;
  RealtimeChannel? _eventsRealtimeChannel;
  Timer? _adminBadgesFallbackTimer;
  StreamSubscription<int>? _chatUnreadSubscription;
  int unreadMessagesCount = 0;
  int chatUnreadCount = 0;
  bool _refreshingRealtimeBadges = false;

  OlympusBranding get _branding => OlympusBrandingController.instance.branding;

  Color _brandPanel([double opacity = 0.88]) =>
      (Color.lerp(_branding.primaryColor, Colors.black, 0.26) ??
              _branding.primaryColor)
          .withOpacity(opacity);

  Widget _buildBrandLogo({
    required double width,
    required double height,
    required double fallbackIconSize,
  }) {
    final branding = _branding;
    final fallback = Image.asset(
      'assets/images/olympus_logo.png',
      width: width,
      height: height,
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) => Icon(
        Icons.admin_panel_settings_rounded,
        size: fallbackIconSize,
        color: branding.secondaryColor,
      ),
    );
    if (branding.logoUrl.isEmpty) return fallback;
    return CachedNetworkImage(
      imageUrl: branding.logoUrl,
      width: width,
      height: height,
      fit: BoxFit.contain,
      placeholder: (_, __) => SizedBox(
        width: width,
        height: height,
        child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      ),
      errorWidget: (_, __, ___) => fallback,
    );
  }

  Widget _buildBrandBackground() {
    final branding = _branding;
    if (branding.backgroundImageUrl.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: branding.backgroundImageUrl,
        fit: BoxFit.cover,
        alignment: Alignment.center,
        errorWidget: (_, __, ___) => const SizedBox.shrink(),
      );
    }
    return Image.asset(
      branding.backgroundAsset,
      fit: BoxFit.cover,
      alignment: Alignment.center,
      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshRealtimeBadges();
    _loadAdminPermissions();
    _loadPlatformAdminAccess();
    _setupRealtimeListeners();
    _listenChatUnreadCount();
  }

  void _listenChatUnreadCount() {
    _chatUnreadSubscription?.cancel();
    _chatUnreadSubscription = _chatService.streamTotalUnreadCount().listen(
      (total) {
        if (!mounted || total == chatUnreadCount) return;
        setState(() => chatUnreadCount = total);
      },
      onError: (Object error, StackTrace stackTrace) {
        debugPrint('Erro ao atualizar badge do chat: $error');
      },
    );
  }

  Future<void> _loadAdminPermissions() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;
    final permissions = await _permissionService.getUserPermissions(userId);
    if (mounted) setState(() => _adminPermissions = permissions);
  }

  Future<void> _loadPlatformAdminAccess() async {
    final allowed = await PlatformAdminService.instance.isPlatformAdmin();
    if (mounted && allowed != _isPlatformAdmin) {
      setState(() => _isPlatformAdmin = allowed);
    }
  }

  bool _canOpen(String permission) => _adminPermissions[permission] ?? true;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startAdminFallbackTimer();
      _refreshRealtimeBadges();
    } else if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _adminBadgesFallbackTimer?.cancel();
      _adminBadgesFallbackTimer = null;
    }
  }

  Future<void> _refreshRealtimeBadges() async {
    if (!mounted || _refreshingRealtimeBadges) return;
    _refreshingRealtimeBadges = true;

    try {
      await Future.wait([
        _fetchMonthBirthdays(),
        _fetchPendingFinancialReceiptsCount(),
        _fetchUnreadMessagesCount(),
        _fetchChatUnreadCount(),
      ]);
    } finally {
      _refreshingRealtimeBadges = false;
    }
  }

  void _setupRealtimeListeners() {
    _listenForFinancialReceipts();
    _listenForBirthdays();
    _listenForAdminMessages();
    _listenForEvents();

    _startAdminFallbackTimer();
  }

  void _startAdminFallbackTimer() {
    _adminBadgesFallbackTimer ??= Timer.periodic(
      const Duration(seconds: 60),
      (_) => _refreshRealtimeBadges(),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _adminBadgesFallbackTimer?.cancel();
    _chatUnreadSubscription?.cancel();
    if (_financialReceiptsChannel != null) {
      supabase.removeChannel(_financialReceiptsChannel!);
    }
    if (_birthdaysRealtimeChannel != null) {
      supabase.removeChannel(_birthdaysRealtimeChannel!);
    }
    if (_messagesParticipantsRealtimeChannel != null) {
      supabase.removeChannel(_messagesParticipantsRealtimeChannel!);
    }
    if (_messagesRealtimeChannel != null) {
      supabase.removeChannel(_messagesRealtimeChannel!);
    }
    if (_eventsRealtimeChannel != null) {
      supabase.removeChannel(_eventsRealtimeChannel!);
    }
    super.dispose();
  }

  Future<void> _fetchPendingFinancialReceiptsCount() async {
    try {
      final response = await supabase
          .from('financial_records')
          .select('id, status, day, month, year, receipt_url');

      final allRecords = List<Map<String, dynamic>>.from(response as List);
      final today = DateTime.now();
      final todayDate = DateTime(today.year, today.month, today.day);

      final openRecords = allRecords.where((record) {
        final status = record['status']?.toString().trim().toLowerCase() ?? '';
        return status != 'approved';
      }).toList();

      final overdueCount = openRecords.where((record) {
        final day = int.tryParse(record['day']?.toString() ?? '') ?? 1;
        final month =
            int.tryParse(record['month']?.toString() ?? '') ?? today.month;
        final year =
            int.tryParse(record['year']?.toString() ?? '') ?? today.year;
        final dueDate = DateTime(year, month, day);
        return dueDate.isBefore(todayDate);
      }).length;

      final pendingReceiptCount = openRecords.where((record) {
        final status = record['status']?.toString().trim().toLowerCase() ?? '';
        final receiptUrl = record['receipt_url']?.toString().trim() ?? '';
        return status == 'pending' && receiptUrl.isNotEmpty;
      }).length;

      final pendingCount = openRecords.length;

      if (mounted) {
        setState(() {
          pendingFinancialReceiptsCount = pendingReceiptCount;
          overdueFinancialRecordsCount = overdueCount;
          pendingFinancialRecordsCount = pendingCount;
        });
      }
    } catch (e) {
      debugPrint('Erro ao buscar status financeiro: $e');
    }
  }

  void _listenForFinancialReceipts() {
    if (_financialReceiptsChannel != null) return;

    _financialReceiptsChannel = supabase
        .channel('admin_home_financial_receipts')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'financial_records',
          callback: (_) => _fetchPendingFinancialReceiptsCount(),
        )
        .subscribe((status, [error]) {
      debugPrint(
        'Realtime financial_records status: $status error: $error',
      );
      if (status == RealtimeSubscribeStatus.subscribed) {
        _fetchPendingFinancialReceiptsCount();
      }
    });
  }

  void _listenForBirthdays() {
    if (_birthdaysRealtimeChannel != null) return;

    _birthdaysRealtimeChannel = supabase
        .channel('admin_home_birthdays_profiles')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'profiles',
          callback: (_) => _fetchMonthBirthdays(),
        )
        .subscribe((status, [error]) {
      debugPrint(
        'Realtime profiles/birthdays status: $status error: $error',
      );
      if (status == RealtimeSubscribeStatus.subscribed) {
        _fetchMonthBirthdays();
      }
    });
  }

  void _listenForAdminMessages() {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    _messagesParticipantsRealtimeChannel ??= supabase
        .channel('admin_home_message_participants_${user.id}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'app_message_participants',
          callback: (_) => _fetchUnreadMessagesCount(),
        )
        .subscribe((status, [error]) {
      debugPrint(
        'Realtime app_message_participants status: $status error: $error',
      );
      if (status == RealtimeSubscribeStatus.subscribed) {
        _fetchUnreadMessagesCount();
      }
    });

    _messagesRealtimeChannel ??= supabase
        .channel('admin_home_messages_${user.id}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'app_messages',
          callback: (_) => _fetchUnreadMessagesCount(),
        )
        .subscribe((status, [error]) {
      debugPrint('Realtime app_messages status: $status error: $error');
      if (status == RealtimeSubscribeStatus.subscribed) {
        _fetchUnreadMessagesCount();
      }
    });
  }

  void _listenForEvents() {
    if (_eventsRealtimeChannel != null) return;

    _eventsRealtimeChannel = supabase
        .channel('admin_home_events')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'events',
          callback: (_) {
            _fetchMonthBirthdays();
          },
        )
        .subscribe((status, [error]) {
      debugPrint('Realtime events status: $status error: $error');
    });
  }

  Future<void> _fetchUnreadMessagesCount() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    try {
      final response = await supabase
          .from('app_message_participants')
          .select('unread_count')
          .eq('user_id', user.id);

      final unreadTotal = List<Map<String, dynamic>>.from(response as List)
          .fold<int>(0, (sum, row) {
        final value = row['unread_count'];
        if (value is int) return sum + value;
        if (value is num) return sum + value.toInt();
        return sum + (int.tryParse((value ?? '0').toString()) ?? 0);
      });

      if (mounted) {
        setState(() {
          unreadMessagesCount = unreadTotal;
        });
      }
    } catch (e) {
      debugPrint('Erro ao buscar mensagens não lidas do admin: $e');
    }
  }

  Future<void> _fetchChatUnreadCount() async {
    final unreadTotal = await _chatService.getTotalUnreadCount();
    if (!mounted) return;

    setState(() {
      chatUnreadCount = unreadTotal;
    });
  }

  Future<void> _fetchMonthBirthdays() async {
    try {
      final now = DateTime.now();

      final response = await supabase
          .from('profiles')
          .select('full_name, birth_date, avatar_url, court_position')
          .eq('is_active', true)
          .not('birth_date', 'is', null);

      final allUsers = List<Map<String, dynamic>>.from(response);

      final parsedBirthdays = allUsers.where((user) {
        final rawBirthDate = user['birth_date'];
        if (rawBirthDate == null || rawBirthDate.toString().trim().isEmpty) {
          return false;
        }

        final birthDate = DateTime.tryParse(rawBirthDate.toString());
        if (birthDate == null) return false;

        return true;
      }).map((user) {
        final birthDate = DateTime.parse(user['birth_date'].toString());
        return {
          ...user,
          'birth': birthDate,
          'parsed_birth_date': birthDate,
        };
      }).toList();

      parsedBirthdays.sort((a, b) {
        final aBirth = a['birth'] as DateTime;
        final bBirth = b['birth'] as DateTime;
        final aMonthOffset = (aBirth.month - now.month + 12) % 12;
        final bMonthOffset = (bBirth.month - now.month + 12) % 12;
        final monthComparison = aMonthOffset.compareTo(bMonthOffset);
        if (monthComparison != 0) return monthComparison;
        final dayComparison = aBirth.day.compareTo(bBirth.day);
        if (dayComparison != 0) return dayComparison;
        return (a['full_name'] ?? '').toString().compareTo(
              (b['full_name'] ?? '').toString(),
            );
      });

      final filtered = parsedBirthdays
          .where((user) => (user['birth'] as DateTime).month == now.month)
          .toList();

      if (mounted) {
        setState(() {
          allBirthdays = parsedBirthdays;
          monthBirthdays = filtered;
          isLoadingBirthdays = false;
        });
      }
    } catch (e) {
      debugPrint('Erro ao buscar aniversariantes do mês: $e');
      if (mounted) {
        setState(() {
          isLoadingBirthdays = false;
        });
      }
    }
  }

  String _formatBirthDate(DateTime date) {
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    return '$day/$month';
  }

  String _formatPosition(dynamic value) {
    if (value == null || value.toString().trim().isEmpty) {
      return 'Sem posição';
    }
    return value.toString();
  }

  String? _resolveBirthdayAvatarUrl(dynamic rawValue) {
    final value = rawValue?.toString().trim();
    if (value == null || value.isEmpty) return null;
    if (value.startsWith('http://') || value.startsWith('https://')) {
      return value;
    }
    return supabase.storage.from('avatars').getPublicUrl(value);
  }

  Widget _buildBirthdayAvatar(
    Map<String, dynamic> birthday, {
    double size = 42,
    bool highlighted = false,
  }) {
    final name = (birthday['full_name'] ?? 'Sem nome').toString().trim();
    final avatarUrl = _resolveBirthdayAvatarUrl(birthday['avatar_url']);
    final fallback = Container(
      color: highlighted
          ? _branding.secondaryColor.withOpacity(0.18)
          : _branding.primaryColor.withOpacity(0.08),
      alignment: Alignment.center,
      child: Text(
        name.isEmpty ? '?' : name[0].toUpperCase(),
        style: TextStyle(
          color: _branding.primaryColor,
          fontWeight: FontWeight.w900,
        ),
      ),
    );

    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: highlighted
              ? _branding.secondaryColor
              : _branding.primaryColor.withOpacity(0.16),
          width: highlighted ? 1.6 : 1,
        ),
      ),
      child: avatarUrl == null
          ? fallback
          : CachedNetworkImage(
              imageUrl: avatarUrl,
              fit: BoxFit.cover,
              memCacheWidth: 240,
              memCacheHeight: 240,
              fadeInDuration: const Duration(milliseconds: 120),
              placeholder: (_, __) => fallback,
              errorWidget: (_, __, ___) => fallback,
            ),
    );
  }

  String _monthLabel(int month) {
    const months = [
      '',
      'Janeiro',
      'Fevereiro',
      'Março',
      'Abril',
      'Maio',
      'Junho',
      'Julho',
      'Agosto',
      'Setembro',
      'Outubro',
      'Novembro',
      'Dezembro',
    ];
    return months[month];
  }

  String _currentMonthLabel() {
    const months = [
      '',
      'Janeiro',
      'Fevereiro',
      'Março',
      'Abril',
      'Maio',
      'Junho',
      'Julho',
      'Agosto',
      'Setembro',
      'Outubro',
      'Novembro',
      'Dezembro',
    ];
    return months[DateTime.now().month];
  }

  Widget _buildMonthBirthdaysCard(BuildContext context) {
    const goldenColor = Color(0xFFE4C050);
    const cyanColor = Color(0xFF8FE8FF);

    final today = DateTime.now();
    final visibleBirthdays = _showAllMonthBirthdays
        ? monthBirthdays
        : monthBirthdays.take(5).toList();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(0.16), width: 1.2),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withOpacity(0.14),
            Colors.white.withOpacity(0.07),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: goldenColor.withOpacity(0.08),
            blurRadius: 18,
            spreadRadius: 1,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: goldenColor.withOpacity(0.14),
                      border: Border.all(color: goldenColor.withOpacity(0.35)),
                    ),
                    child: const Icon(
                      Icons.cake_outlined,
                      color: Color(0xFFE4C050),
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Aniversariantes do mês',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.92),
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${_currentMonthLabel()} • ${monthBirthdays.length} ${monthBirthdays.length == 1 ? "aniversariante" : "aniversariantes"}',
                          style: TextStyle(
                            color: cyanColor.withOpacity(0.92),
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const AdminBirthdaysPage(),
                        ),
                      );
                    },
                    child: const Text('Ver todos'),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              if (isLoadingBirthdays)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 18),
                    child: SizedBox(
                      width: 26,
                      height: 26,
                      child: CircularProgressIndicator(strokeWidth: 2.4),
                    ),
                  ),
                )
              else if (monthBirthdays.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Text(
                    'Nenhum aniversariante neste mês.',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.72),
                      fontSize: 14,
                    ),
                  ),
                )
              else ...[
                AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeInOut,
                  constraints: BoxConstraints(
                    maxHeight: _showAllMonthBirthdays ? 330 : 260,
                  ),
                  child: Scrollbar(
                    thumbVisibility: _showAllMonthBirthdays,
                    radius: const Radius.circular(999),
                    child: ListView.builder(
                      shrinkWrap: true,
                      padding: EdgeInsets.zero,
                      physics: _showAllMonthBirthdays
                          ? const BouncingScrollPhysics()
                          : const NeverScrollableScrollPhysics(),
                      itemCount: visibleBirthdays.length,
                      itemBuilder: (context, index) {
                        final user = visibleBirthdays[index];
                        final birthDate = user['birth'] as DateTime;
                        final fullName =
                            (user['full_name'] ?? 'Sem nome').toString();
                        final position = _formatPosition(
                          user['court_position'],
                        );
                        final isToday = birthDate.day == today.day &&
                            birthDate.month == today.month;

                        return Container(
                          width: double.infinity,
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 11,
                          ),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            color: isToday
                                ? goldenColor.withOpacity(0.18)
                                : Colors.white.withOpacity(0.06),
                            border: Border.all(
                              color: isToday
                                  ? goldenColor.withOpacity(0.65)
                                  : Colors.white.withOpacity(0.08),
                              width: isToday ? 1.4 : 1,
                            ),
                            boxShadow: isToday
                                ? [
                                    BoxShadow(
                                      color: goldenColor.withOpacity(0.22),
                                      blurRadius: 14,
                                      spreadRadius: 0.5,
                                    ),
                                  ]
                                : null,
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 34,
                                height: 34,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: isToday
                                      ? goldenColor.withOpacity(0.24)
                                      : cyanColor.withOpacity(0.10),
                                  border: Border.all(
                                    color: isToday
                                        ? goldenColor.withOpacity(0.65)
                                        : cyanColor.withOpacity(0.22),
                                  ),
                                ),
                                child: Icon(
                                  isToday
                                      ? Icons.celebration_rounded
                                      : Icons.cake_outlined,
                                  color: isToday ? goldenColor : cyanColor,
                                  size: 18,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            fullName,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              color: Colors.white.withOpacity(
                                                0.92,
                                              ),
                                              fontSize: 14,
                                              fontWeight: isToday
                                                  ? FontWeight.w800
                                                  : FontWeight.w600,
                                              height: 1.2,
                                            ),
                                          ),
                                        ),
                                        if (isToday) ...[
                                          const SizedBox(width: 8),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 3,
                                            ),
                                            decoration: BoxDecoration(
                                              borderRadius:
                                                  BorderRadius.circular(999),
                                              color: goldenColor.withOpacity(
                                                0.22,
                                              ),
                                              border: Border.all(
                                                color: goldenColor.withOpacity(
                                                  0.55,
                                                ),
                                              ),
                                            ),
                                            child: const Text(
                                              'Hoje 🎉',
                                              style: TextStyle(
                                                color: Color(0xFFE4C050),
                                                fontSize: 10.5,
                                                fontWeight: FontWeight.w800,
                                                height: 1,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '${_formatBirthDate(birthDate)} • $position',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: isToday
                                            ? goldenColor.withOpacity(0.95)
                                            : Colors.white.withOpacity(0.68),
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w500,
                                        height: 1.2,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ),
                if (monthBirthdays.length > 5) ...[
                  const SizedBox(height: 4),
                  SizedBox(
                    width: double.infinity,
                    child: TextButton.icon(
                      onPressed: () {
                        setState(() {
                          _showAllMonthBirthdays = !_showAllMonthBirthdays;
                        });
                      },
                      icon: Icon(
                        _showAllMonthBirthdays
                            ? Icons.keyboard_arrow_up_rounded
                            : Icons.keyboard_arrow_down_rounded,
                        color: goldenColor,
                      ),
                      label: Text(
                        _showAllMonthBirthdays
                            ? 'Ver menos'
                            : 'Ver mais ${monthBirthdays.length - 5}',
                        style: const TextStyle(
                          color: goldenColor,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }

  int get _financialBadgeCount {
    if (overdueFinancialRecordsCount > 0) return overdueFinancialRecordsCount;
    if (pendingFinancialReceiptsCount > 0) return pendingFinancialReceiptsCount;
    return pendingFinancialRecordsCount;
  }

  Color get _financialBadgeColor {
    if (overdueFinancialRecordsCount > 0) return Colors.redAccent;
    if (pendingFinancialReceiptsCount > 0) return Colors.blueAccent;
    return Colors.orangeAccent;
  }

  IconData get _financialBadgeIcon {
    if (overdueFinancialRecordsCount > 0) return Icons.warning_rounded;
    if (pendingFinancialReceiptsCount > 0) return Icons.attach_file_rounded;
    return Icons.schedule_rounded;
  }

  String get _financialBadgeTooltip {
    if (overdueFinancialRecordsCount > 0) {
      return overdueFinancialRecordsCount == 1
          ? '1 cobrança atrasada'
          : '$overdueFinancialRecordsCount cobranças atrasadas';
    }
    if (pendingFinancialReceiptsCount > 0) {
      return pendingFinancialReceiptsCount == 1
          ? '1 comprovante aguardando aprovação'
          : '$pendingFinancialReceiptsCount comprovantes aguardando aprovação';
    }
    return pendingFinancialRecordsCount == 1
        ? '1 cobrança pendente'
        : '$pendingFinancialRecordsCount cobranças pendentes';
  }

  bool get _useCompactAdminGrid => true;

  Widget _buildCompactAdminHero() {
    final branding = _branding;
    final primary = branding.primaryColor;
    final secondary = branding.secondaryColor;
    final onPrimary =
        ThemeData.estimateBrightnessForColor(primary) == Brightness.dark
            ? Colors.white
            : const Color(0xFF102845);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          colors: [
            (Color.lerp(primary, Colors.white, 0.08) ?? primary).withOpacity(
              0.92,
            ),
            (Color.lerp(primary, Colors.black, 0.32) ?? primary).withOpacity(
              0.88,
            ),
          ],
        ),
        border: Border.all(color: secondary.withOpacity(0.32)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 64,
            height: 64,
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Color.lerp(primary, Colors.black, 0.48),
              border: Border.all(color: secondary, width: 1.4),
            ),
            child: _buildBrandLogo(width: 56, height: 56, fallbackIconSize: 30),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Olá, Admin!',
                  style: TextStyle(
                    color: onPrimary,
                    fontSize: 21,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Seu centro de controle ${branding.teamName}',
                  style: TextStyle(
                    color: onPrimary.withOpacity(0.72),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Atualizar painel',
            onPressed: _refreshRealtimeBadges,
            style: IconButton.styleFrom(
              backgroundColor: Colors.white.withOpacity(0.09),
              foregroundColor: secondary,
            ),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactBirthdaySummary(BuildContext context) {
    final visible = monthBirthdays.take(2).toList();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: _brandPanel(0.84),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.14)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const CircleAvatar(
                radius: 19,
                backgroundColor: Color(0x33E4C050),
                child: Icon(Icons.cake_outlined, color: Color(0xFFE4C050)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Aniversariantes do mês',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      '${monthBirthdays.length} pessoa${monthBirthdays.length == 1 ? '' : 's'} em ${_currentMonthLabel()}',
                      style: const TextStyle(
                        color: Color(0xFF8FE8FF),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: _showCurrentMonthBirthdays,
                child: const Text('Ver todos'),
              ),
            ],
          ),
          if (isLoadingBirthdays)
            const Padding(
              padding: EdgeInsets.all(12),
              child: LinearProgressIndicator(),
            )
          else if (visible.isNotEmpty) ...[
            const SizedBox(height: 10),
            ...visible.map((birthday) {
              final date = birthday['parsed_birth_date'] as DateTime?;
              return Padding(
                padding: const EdgeInsets.only(top: 7),
                child: Row(
                  children: [
                    _buildBirthdayAvatar(birthday, size: 30, highlighted: true),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        (birthday['full_name'] ?? 'Sem nome').toString(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    if (date != null)
                      Text(
                        _formatBirthDate(date),
                        style: const TextStyle(
                          color: Colors.white60,
                          fontSize: 12,
                        ),
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

  // ignore: unused_element
  Widget _buildAdminModulesGrid(BuildContext context) {
    final modules = <({
      String permission,
      String label,
      String subtitle,
      IconData icon,
      Color color,
      int badge,
      VoidCallback onTap,
    })>[
      (
        permission: 'admin_agenda',
        label: 'Agenda',
        subtitle: 'Eventos e convocações',
        icon: Icons.calendar_month_rounded,
        color: const Color(0xFF65D6FF),
        badge: 0,
        onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AgendaPage()),
            ),
      ),
      (
        permission: 'admin_users',
        label: 'Perfis',
        subtitle: 'Usuários e permissões',
        icon: Icons.groups_rounded,
        color: const Color(0xFFE4C050),
        badge: 0,
        onTap: () => Navigator.pushNamed(context, '/profiles'),
      ),
      (
        permission: 'admin_users',
        label: 'Cores do clube',
        subtitle: 'Todos os perfis e telas',
        icon: Icons.palette_rounded,
        color: const Color(0xFFFFC857),
        badge: 0,
        onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AdminBrandingPage()),
            ),
      ),
      (
        permission: 'admin_training_plans',
        label: 'Treinos',
        subtitle: 'Planejamentos',
        icon: Icons.menu_book_rounded,
        color: const Color(0xFF73E2A7),
        badge: 0,
        onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const AdminTrainingPlansPage(),
              ),
            ),
      ),
      (
        permission: 'admin_competitions',
        label: 'Competições',
        subtitle: 'Jogos e campeonatos',
        icon: Icons.emoji_events_rounded,
        color: const Color(0xFF70E1F5),
        badge: 0,
        onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const AdminCompetitionsPage(canEdit: true),
              ),
            ),
      ),
      (
        permission: 'admin_evaluations',
        label: 'Avaliações',
        subtitle: 'Feedback dos treinadores',
        icon: Icons.rate_review_rounded,
        color: const Color(0xFF64FFDA),
        badge: 0,
        onTap: () => Navigator.pushNamed(context, '/admin-coach-evaluations'),
      ),
      (
        permission: 'admin_statistics',
        label: 'Estatísticas',
        subtitle: 'Desempenho dos atletas',
        icon: Icons.query_stats_rounded,
        color: const Color(0xFFB29BFF),
        badge: 0,
        onTap: () => Navigator.pushNamed(context, '/admin-athletes-statistics'),
      ),
      (
        permission: 'admin_statistics',
        label: 'Ranking',
        subtitle: 'Check-ins por período',
        icon: Icons.leaderboard_rounded,
        color: const Color(0xFFE4C050),
        badge: 0,
        onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const AdminCheckinRankingPage(),
              ),
            ),
      ),
      (
        permission: 'admin_financial',
        label: 'Financeiro',
        subtitle: 'Cobranças e comprovantes',
        icon: Icons.account_balance_wallet_rounded,
        color: const Color(0xFFFFC857),
        badge: _financialBadgeCount,
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const AdminFinancialPage(),
            ),
          );
          _fetchPendingFinancialReceiptsCount();
        },
      ),
      (
        permission: 'admin_messages',
        label: 'Mensagens',
        subtitle: 'Comunicação da equipe',
        icon: Icons.forum_rounded,
        color: const Color(0xFFFF8FA3),
        badge: unreadMessagesCount,
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const AdminMessagesPage(),
            ),
          );
          _fetchUnreadMessagesCount();
        },
      ),
      (
        permission: 'admin_birthdays',
        label: 'Aniversários',
        subtitle: 'Calendário da equipe',
        icon: Icons.cake_rounded,
        color: const Color(0xFFFF86C8),
        badge: 0,
        onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AdminBirthdaysPage()),
            ),
      ),
    ].where((module) => _canOpen(module.permission)).toList();

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 760 ? 3 : 2;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: modules.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: columns == 2 ? 1.16 : 1.35,
          ),
          itemBuilder: (context, index) {
            final module = modules[index];
            return _buildAdminModuleCard(
              label: module.label,
              subtitle: module.subtitle,
              icon: module.icon,
              color: module.color,
              badge: module.badge,
              onTap: module.onTap,
            );
          },
        );
      },
    );
  }

  Widget _buildSportsCommandCenter(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildClubStatusStrip(),
        const SizedBox(height: 18),
        const Text(
          'Acesso imediato',
          style: TextStyle(
            color: Colors.white,
            fontSize: 17,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 10),
        _buildQuickActionsRail(context),
        const SizedBox(height: 20),
        _buildFeaturedAgendaAction(context),
        const SizedBox(height: 14),
        _buildManagementDirectory(context),
      ],
    );
  }

  Widget _buildClubStatusStrip() {
    final metrics =
        <({String value, String label, Color color, VoidCallback onTap})>[
      if (_canOpen('admin_financial'))
        (
          value: '$_financialBadgeCount',
          label: 'Financeiro',
          color: const Color(0xFFFFC857),
          onTap: () async {
            await Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AdminFinancialPage()),
            );
            _fetchPendingFinancialReceiptsCount();
          },
        ),
      if (_canOpen('admin_messages'))
        (
          value: '$unreadMessagesCount',
          label: 'Mensagens',
          color: const Color(0xFFFF8FA3),
          onTap: () async {
            await Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AdminMessagesPage()),
            );
            _fetchUnreadMessagesCount();
          },
        ),
      if (_canOpen('admin_birthdays'))
        (
          value: '${monthBirthdays.length}',
          label: 'Aniversários',
          color: const Color(0xFF8FE8FF),
          onTap: _showCurrentMonthBirthdays,
        ),
    ];

    if (metrics.isEmpty) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: _brandPanel(0.86),
        border: Border.all(color: Colors.white.withOpacity(0.12)),
      ),
      child: Row(
        children: metrics.indexed.expand((entry) {
          final index = entry.$1;
          final metric = entry.$2;
          return [
            if (index > 0) _statusDivider(),
            _buildStatusMetric(
              value: metric.value,
              label: metric.label,
              color: metric.color,
              onTap: metric.onTap,
            ),
          ];
        }).toList(),
      ),
    );
  }

  Widget _statusDivider() {
    return Container(
      width: 1,
      height: 34,
      margin: const EdgeInsets.symmetric(horizontal: 8),
      color: Colors.white.withOpacity(0.12),
    );
  }

  Widget _buildStatusMetric({
    required String value,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
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
        ),
      ),
    );
  }

  // Mantido apenas como referência visual da versão anterior.
  // ignore: unused_element
  void _showCurrentMonthBirthdaysLegacy() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => DraggableScrollableSheet(
        initialChildSize: 0.56,
        minChildSize: 0.36,
        maxChildSize: 0.86,
        expand: false,
        builder: (context, controller) => Container(
          decoration: const BoxDecoration(
            color: Color(0xFFF6F9FC),
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.black12,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 10, 10),
                child: Row(
                  children: [
                    const CircleAvatar(
                      backgroundColor: Color(0xFFFFE8A6),
                      child: Icon(Icons.cake_rounded, color: Color(0xFF8A6500)),
                    ),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Aniversariantes de ${_currentMonthLabel()}',
                            style: const TextStyle(
                              color: Color(0xFF102D4F),
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          Text(
                            '${monthBirthdays.length} pessoa${monthBirthdays.length == 1 ? '' : 's'} neste mês',
                            style: const TextStyle(
                              color: Colors.black54,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(sheetContext),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: monthBirthdays.isEmpty
                    ? const Center(
                        child: Text('Nenhum aniversariante neste mês.'),
                      )
                    : ListView.separated(
                        controller: controller,
                        padding: const EdgeInsets.all(16),
                        itemCount: monthBirthdays.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final birthday = monthBirthdays[index];
                          final date =
                              birthday['parsed_birth_date'] as DateTime?;
                          return Container(
                            padding: const EdgeInsets.all(13),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: const Color(0xFFE3EAF2),
                              ),
                            ),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  backgroundColor: const Color(
                                    0xFF102D4F,
                                  ).withOpacity(0.08),
                                  child: const Icon(
                                    Icons.celebration_rounded,
                                    color: Color(0xFFD4AF37),
                                  ),
                                ),
                                const SizedBox(width: 11),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        (birthday['full_name'] ?? 'Sem nome')
                                            .toString(),
                                        style: const TextStyle(
                                          color: Color(0xFF102D4F),
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                      Text(
                                        (birthday['court_position'] ??
                                                'Posição não informada')
                                            .toString(),
                                        style: const TextStyle(
                                          color: Colors.black54,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (date != null)
                                  Text(
                                    _formatBirthDate(date),
                                    style: const TextStyle(
                                      color: Color(0xFF102D4F),
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBirthdaySheetCard(
    Map<String, dynamic> birthday, {
    required bool highlighted,
  }) {
    final date = birthday['parsed_birth_date'] as DateTime?;
    final name = (birthday['full_name'] ?? 'Sem nome').toString();
    final position = _formatPosition(birthday['court_position']);

    return Container(
      margin: const EdgeInsets.only(bottom: 9),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: highlighted
            ? _branding.secondaryColor.withOpacity(0.12)
            : _branding.surfaceColor,
        borderRadius: BorderRadius.circular(17),
        border: Border.all(
          color: highlighted
              ? _branding.secondaryColor.withOpacity(0.58)
              : const Color(0xFFE3EAF2),
          width: highlighted ? 1.4 : 1,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0D102D4F),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          _buildBirthdayAvatar(birthday, size: 48, highlighted: highlighted),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _branding.primaryColor,
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  position,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.black54, fontSize: 12),
                ),
              ],
            ),
          ),
          if (date != null) ...[
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: highlighted
                    ? _branding.secondaryColor
                    : _branding.primaryColor.withOpacity(0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                _formatBirthDate(date),
                style: TextStyle(
                  color: highlighted
                      ? Theme.of(context).colorScheme.onSecondary
                      : _branding.primaryColor,
                  fontWeight: FontWeight.w900,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBirthdaySheetMonthSection(
    int month,
    List<Map<String, dynamic>> birthdays,
  ) {
    final highlighted = month == DateTime.now().month;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 9),
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
            decoration: BoxDecoration(
              color: highlighted
                  ? _branding.primaryColor
                  : _branding.primaryColor.withOpacity(0.08),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: highlighted
                    ? _branding.secondaryColor
                    : const Color(0xFFD9E3ED),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  highlighted ? Icons.celebration_rounded : Icons.cake_outlined,
                  color: highlighted
                      ? _branding.secondaryColor
                      : _branding.primaryColor,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _monthLabel(month),
                    style: TextStyle(
                      color: highlighted
                          ? Theme.of(context).colorScheme.onPrimary
                          : _branding.primaryColor,
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                if (highlighted)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: _branding.secondaryColor,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      'Mês atual',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSecondary,
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  )
                else
                  Text(
                    '${birthdays.length}',
                    style: const TextStyle(
                      color: Color(0xFF58708A),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
              ],
            ),
          ),
          ...birthdays.map(
            (birthday) =>
                _buildBirthdaySheetCard(birthday, highlighted: highlighted),
          ),
        ],
      ),
    );
  }

  void _showCurrentMonthBirthdays() {
    final grouped = <int, List<Map<String, dynamic>>>{};
    for (final birthday in allBirthdays) {
      final date = birthday['parsed_birth_date'] as DateTime?;
      if (date == null) continue;
      grouped.putIfAbsent(date.month, () => []).add(birthday);
    }
    final currentMonth = DateTime.now().month;
    final orderedMonths = grouped.keys.toList()
      ..sort((a, b) {
        final aOffset = (a - currentMonth + 12) % 12;
        final bOffset = (b - currentMonth + 12) % 12;
        return aOffset.compareTo(bOffset);
      });

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => DraggableScrollableSheet(
        initialChildSize: 0.78,
        minChildSize: 0.48,
        maxChildSize: 0.94,
        expand: false,
        builder: (context, controller) => Container(
          decoration: BoxDecoration(
            color: _branding.backgroundColor,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.black12,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 10, 10),
                child: Row(
                  children: [
                    CircleAvatar(
                      backgroundColor:
                          _branding.secondaryColor.withOpacity(0.18),
                      child: Icon(
                        Icons.cake_rounded,
                        color: _branding.secondaryColor,
                      ),
                    ),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Aniversariantes',
                            style: TextStyle(
                              color: _branding.primaryColor,
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          Text(
                            '${allBirthdays.length} pessoa${allBirthdays.length == 1 ? '' : 's'} • ${_currentMonthLabel()} em destaque',
                            style: const TextStyle(
                              color: Colors.black54,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(sheetContext),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: allBirthdays.isEmpty
                    ? const Center(
                        child: Text(
                          'Nenhum aniversariante com data cadastrada.',
                        ),
                      )
                    : ListView(
                        controller: controller,
                        padding: const EdgeInsets.all(16),
                        children: orderedMonths
                            .map(
                              (month) => _buildBirthdaySheetMonthSection(
                                month,
                                grouped[month]!,
                              ),
                            )
                            .toList(),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQuickActionsRail(BuildContext context) {
    final actions = <({
      String permission,
      String label,
      IconData icon,
      Color color,
      int badge,
      VoidCallback onTap,
    })>[
      (
        permission: 'admin_users',
        label: 'Perfis',
        icon: Icons.groups_rounded,
        color: const Color(0xFFE4C050),
        badge: 0,
        onTap: () => Navigator.pushNamed(context, '/profiles'),
      ),
      (
        permission: 'admin_financial',
        label: 'Financeiro',
        icon: Icons.account_balance_wallet_rounded,
        color: const Color(0xFFFFC857),
        badge: _financialBadgeCount,
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const AdminFinancialPage(),
            ),
          );
          _fetchPendingFinancialReceiptsCount();
        },
      ),
      (
        permission: 'admin_messages',
        label: 'Mensagens',
        icon: Icons.forum_rounded,
        color: const Color(0xFFFF8FA3),
        badge: unreadMessagesCount,
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const AdminMessagesPage(),
            ),
          );
          _fetchUnreadMessagesCount();
        },
      ),
      (
        permission: 'admin_messages',
        label: 'Chat',
        icon: Icons.chat_bubble_rounded,
        color: const Color(0xFF25D366),
        badge: chatUnreadCount,
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const ChatRoomsPage()),
          );
          _fetchChatUnreadCount();
        },
      ),
      (
        permission: 'admin_birthdays',
        label: 'Aniversários',
        icon: Icons.cake_rounded,
        color: const Color(0xFF8FE8FF),
        badge: 0,
        onTap: _showCurrentMonthBirthdays,
      ),
    ].where((action) => _canOpen(action.permission)).toList();

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
                child: _buildQuickAction(
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

  Widget _buildQuickAction({
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
                  border: Border.all(color: color.withOpacity(0.50)),
                  boxShadow: [
                    BoxShadow(color: color.withOpacity(0.15), blurRadius: 12),
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

  Widget _buildFeaturedAgendaAction(BuildContext context) {
    if (!_canOpen('admin_agenda')) return const SizedBox.shrink();
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const AgendaPage()),
        ),
        borderRadius: BorderRadius.circular(22),
        child: Ink(
          padding: const EdgeInsets.all(17),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            gradient: const LinearGradient(
              colors: [Color(0xFFE4C050), Color(0xFFB78618)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x44D4AF37),
                blurRadius: 20,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.20),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: const Icon(
                  Icons.calendar_month_rounded,
                  color: Color(0xFF0C2743),
                  size: 27,
                ),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Abrir agenda do clube',
                      style: TextStyle(
                        color: Color(0xFF0C2743),
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Eventos, convocações e presenças',
                      style: TextStyle(color: Color(0xCC0C2743), fontSize: 12),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_rounded, color: Color(0xFF0C2743)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildManagementDirectory(BuildContext context) {
    final modules = <({
      String permission,
      String label,
      String subtitle,
      IconData icon,
      Color color,
      VoidCallback onTap,
    })>[
      (
        permission: 'admin_users',
        label: 'Equipe técnica',
        subtitle: 'Coordenadores, treinadores, assistentes e estagiários',
        icon: Icons.account_tree_rounded,
        color: const Color(0xFFFFD166),
        onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const AdminTechnicalStaffPage(),
              ),
            ),
      ),
      (
        permission: 'admin_users',
        label: 'Cores do clube',
        subtitle: 'Admin, treinadores e atletas',
        icon: Icons.palette_rounded,
        color: const Color(0xFFFFC857),
        onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AdminBrandingPage()),
            ),
      ),
      (
        permission: 'admin_training_plans',
        label: 'Planejamentos de treino',
        subtitle: 'Programações criadas pelos treinadores',
        icon: Icons.menu_book_rounded,
        color: const Color(0xFF73E2A7),
        onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const AdminTrainingPlansPage(),
              ),
            ),
      ),
      (
        permission: 'admin_competitions',
        label: 'Competições',
        subtitle: 'Jogos, amistosos e campeonatos',
        icon: Icons.emoji_events_rounded,
        color: const Color(0xFF70E1F5),
        onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const AdminCompetitionsPage(canEdit: true),
              ),
            ),
      ),
      (
        permission: 'admin_evaluations',
        label: 'Avaliações dos treinadores',
        subtitle: 'Feedback recebido pelos técnicos',
        icon: Icons.rate_review_rounded,
        color: const Color(0xFF64FFDA),
        onTap: () => Navigator.pushNamed(context, '/admin-coach-evaluations'),
      ),
      (
        permission: 'admin_statistics',
        label: 'Estatísticas dos atletas',
        subtitle: 'Indicadores e evolução esportiva',
        icon: Icons.query_stats_rounded,
        color: const Color(0xFFB29BFF),
        onTap: () => Navigator.pushNamed(context, '/admin-athletes-statistics'),
      ),
      (
        permission: 'admin_statistics',
        label: 'Ranking de check-ins',
        subtitle: 'Posições, presenças e exportação',
        icon: Icons.leaderboard_rounded,
        color: const Color(0xFFE4C050),
        onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const AdminCheckinRankingPage(),
              ),
            ),
      ),
    ].where((module) => _canOpen(module.permission)).toList();

    if (modules.isEmpty) return const SizedBox.shrink();
    return Container(
      decoration: BoxDecoration(
        color: _brandPanel(),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withOpacity(0.13)),
      ),
      child: Column(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(16, 15, 16, 8),
            child: Row(
              children: [
                Text(
                  'Gestão e configurações',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Spacer(),
                Text(
                  _branding.teamName.toUpperCase(),
                  style: TextStyle(
                    color: _branding.secondaryColor,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.2,
                  ),
                ),
              ],
            ),
          ),
          ...modules.indexed.map((entry) {
            final index = entry.$1;
            final module = entry.$2;
            return Column(
              children: [
                if (index > 0)
                  Divider(
                    height: 1,
                    indent: 66,
                    color: Colors.white.withOpacity(0.09),
                  ),
                ListTile(
                  onTap: module.onTap,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 3,
                  ),
                  leading: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: module.color.withOpacity(0.14),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(module.icon, color: module.color, size: 21),
                  ),
                  title: Text(
                    module.label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 13.5,
                    ),
                  ),
                  subtitle: Text(
                    module.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white54, fontSize: 11),
                  ),
                  trailing: const Icon(
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

  Widget _buildAdminModuleCard({
    required String label,
    required String subtitle,
    required IconData icon,
    required Color color,
    required int badge,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Ink(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                (Color.lerp(_branding.primaryColor, Colors.white, 0.10) ??
                        _branding.primaryColor)
                    .withOpacity(0.94),
                (Color.lerp(_branding.primaryColor, Colors.black, 0.30) ??
                        _branding.primaryColor)
                    .withOpacity(0.90),
              ],
            ),
            border: Border.all(color: color.withOpacity(0.30)),
          ),
          child: Stack(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.16),
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: Icon(icon, color: color, size: 23),
                  ),
                  const Spacer(),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.62),
                      fontSize: 11,
                      height: 1.2,
                    ),
                  ),
                ],
              ),
              Positioned(
                top: 0,
                right: 0,
                child: badge > 0
                    ? Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.redAccent,
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: Text(
                          badge > 99 ? '99+' : '$badge',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 11,
                          ),
                        ),
                      )
                    : Icon(
                        Icons.arrow_outward_rounded,
                        color: color.withOpacity(0.75),
                        size: 19,
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final branding = _branding;
    final primary = branding.primaryColor;
    final goldenColor = branding.secondaryColor;
    final cyanColor =
        Color.lerp(goldenColor, Colors.white, 0.54) ?? goldenColor;

    return Scaffold(
      floatingActionButton: _isPlatformAdmin
          ? FloatingActionButton.extended(
              heroTag: 'platform_admin_master',
              tooltip: 'Gerenciar clubes e funcionalidades',
              onPressed: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => const PlatformMasterPage(),
                  ),
                );
                _loadAdminPermissions();
              },
              icon: const Icon(Icons.admin_panel_settings_rounded),
              label: const Text('Admin Master'),
            )
          : null,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color.lerp(primary, Colors.black, 0.30) ?? primary,
              primary,
              Color.lerp(primary, Colors.black, 0.58) ?? primary,
            ],
          ),
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: Opacity(opacity: 0.68, child: _buildBrandBackground()),
            ),
            Positioned.fill(
              child: Container(
                color: (Color.lerp(primary, Colors.black, 0.62) ?? primary)
                    .withOpacity(0.46),
              ),
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(painter: _FuturisticBackgroundPainter()),
              ),
            ),
            SafeArea(
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Painel Administrativo',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.85),
                            fontSize: 17,
                            fontWeight: FontWeight.w500,
                            letterSpacing: 0.2,
                          ),
                        ),
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.06),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.10),
                            ),
                          ),
                          child: IconButton(
                            padding: EdgeInsets.zero,
                            icon: Icon(
                              Icons.logout_rounded,
                              color: Colors.white.withOpacity(0.85),
                              size: 22,
                            ),
                            onPressed: () async {
                              final authService = AuthService();
                              await authService.signOut();
                              if (context.mounted) {
                                Navigator.pushNamedAndRemoveUntil(
                                  context,
                                  '/login',
                                  (route) => false,
                                );
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Center(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 22,
                          vertical: 12,
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (_useCompactAdminGrid) _buildCompactAdminHero(),
                            if (!_useCompactAdminGrid)
                              Stack(
                                clipBehavior: Clip.none,
                                alignment: Alignment.topCenter,
                                children: [
                                  Container(
                                    width: double.infinity,
                                    margin: const EdgeInsets.only(top: 54),
                                    padding: const EdgeInsets.fromLTRB(
                                      20,
                                      72,
                                      20,
                                      22,
                                    ),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(18),
                                      border: Border.all(
                                        color: Colors.white.withOpacity(0.16),
                                        width: 1.2,
                                      ),
                                      gradient: LinearGradient(
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                        colors: [
                                          Colors.white.withOpacity(0.18),
                                          Colors.white.withOpacity(0.08),
                                        ],
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: cyanColor.withOpacity(0.10),
                                          blurRadius: 24,
                                          spreadRadius: 1,
                                        ),
                                      ],
                                    ),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(18),
                                      child: BackdropFilter(
                                        filter: ImageFilter.blur(
                                          sigmaX: 14,
                                          sigmaY: 14,
                                        ),
                                        child: Column(
                                          children: [
                                            Text(
                                              'Bem-vindo, Admin!',
                                              textAlign: TextAlign.center,
                                              style: TextStyle(
                                                fontSize: 23,
                                                fontWeight: FontWeight.w500,
                                                color: Colors.white.withOpacity(
                                                  0.92,
                                                ),
                                                height: 1.15,
                                              ),
                                            ),
                                            const SizedBox(height: 10),
                                            Text(
                                              'Gerencie o sistema ${branding.teamName}',
                                              textAlign: TextAlign.center,
                                              style: TextStyle(
                                                fontSize: 14,
                                                color: Colors.white.withOpacity(
                                                  0.68,
                                                ),
                                                fontWeight: FontWeight.w400,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                  Container(
                                    width: 118,
                                    height: 118,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      gradient: LinearGradient(
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                        colors: [
                                          const Color(
                                            0xFF42556F,
                                          ).withOpacity(0.95),
                                          const Color(
                                            0xFF31445D,
                                          ).withOpacity(0.88),
                                        ],
                                      ),
                                      border: Border.all(
                                        color: goldenColor.withOpacity(0.35),
                                        width: 2,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: goldenColor.withOpacity(0.20),
                                          blurRadius: 24,
                                          spreadRadius: 2,
                                        ),
                                      ],
                                    ),
                                    child: Center(
                                      child: ClipOval(
                                        child: Padding(
                                          padding: const EdgeInsets.all(4),
                                          child: _buildBrandLogo(
                                            width: 108,
                                            height: 108,
                                            fallbackIconSize: 54,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            const SizedBox(height: 14),
                            if (_canOpen('admin_birthdays'))
                              if (_useCompactAdminGrid)
                                _buildCompactBirthdaySummary(context)
                              else
                                _buildMonthBirthdaysCard(context),
                            const SizedBox(height: 18),
                            if (_useCompactAdminGrid) ...[
                              _buildSportsCommandCenter(context),
                              const SizedBox(height: 12),
                            ],
                            if (!_useCompactAdminGrid &&
                                _canOpen('admin_evaluations')) ...[
                              _buildFuturisticButton(
                                context: context,
                                label: 'Avaliações dos Treinadores',
                                icon: Icons.rate_review_rounded,
                                accentColor: const Color(0xFF64FFDA),
                                isPrimary: true,
                                onTap: () {
                                  Navigator.pushNamed(
                                    context,
                                    '/admin-coach-evaluations',
                                  );
                                },
                              ),
                              const SizedBox(height: 18),
                            ],
                            if (!_useCompactAdminGrid &&
                                _canOpen('admin_agenda')) ...[
                              _buildFuturisticButton(
                                context: context,
                                label: 'Agenda',
                                icon: Icons.calendar_month_rounded,
                                accentColor: cyanColor,
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => const AgendaPage(),
                                    ),
                                  );
                                },
                              ),
                              const SizedBox(height: 18),
                            ],
                            if (!_useCompactAdminGrid &&
                                _canOpen('admin_training_plans')) ...[
                              _buildFuturisticButton(
                                context: context,
                                label: 'Programações de Treinos',
                                icon: Icons.menu_book_outlined,
                                accentColor: const Color(0xFFB9FBC0),
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) =>
                                          const AdminTrainingPlansPage(),
                                    ),
                                  );
                                },
                              ),
                              const SizedBox(height: 18),
                            ],
                            if (!_useCompactAdminGrid &&
                                _canOpen('admin_statistics')) ...[
                              _buildFuturisticButton(
                                context: context,
                                label: 'Estatísticas dos Atletas',
                                icon: Icons.bar_chart_rounded,
                                accentColor: const Color(0xFF9D8DF1),
                                isPrimary: true,
                                onTap: () {
                                  Navigator.pushNamed(
                                    context,
                                    '/admin-athletes-statistics',
                                  );
                                },
                              ),
                              const SizedBox(height: 18),
                            ],
                            if (!_useCompactAdminGrid &&
                                _canOpen('admin_birthdays')) ...[
                              _buildFuturisticButton(
                                context: context,
                                label: 'Aniversariantes',
                                icon: Icons.cake_outlined,
                                accentColor: Colors.pinkAccent,
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) =>
                                          const AdminBirthdaysPage(),
                                    ),
                                  );
                                },
                              ),
                              const SizedBox(height: 18),
                            ],
                            if (!_useCompactAdminGrid &&
                                _canOpen('admin_competitions')) ...[
                              _buildFuturisticButton(
                                context: context,
                                label: 'Competições',
                                icon: Icons.emoji_events_outlined,
                                accentColor: const Color(0xFF7CE7FF),
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) =>
                                          const AdminCompetitionsPage(
                                        canEdit: true,
                                      ),
                                    ),
                                  );
                                },
                              ),
                              const SizedBox(height: 18),
                            ],
                            if (!_useCompactAdminGrid &&
                                _canOpen('admin_financial')) ...[
                              _buildFuturisticButton(
                                context: context,
                                label: 'Financeiro',
                                icon: Icons.attach_money_rounded,
                                accentColor: cyanColor,
                                badgeCount: _financialBadgeCount,
                                badgeTooltip: _financialBadgeTooltip,
                                badgeColor: _financialBadgeColor,
                                badgeIcon: _financialBadgeIcon,
                                onTap: () async {
                                  await Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) =>
                                          const AdminFinancialPage(),
                                    ),
                                  );
                                  _fetchPendingFinancialReceiptsCount();
                                },
                              ),
                              const SizedBox(height: 18),
                            ],
                            if (!_useCompactAdminGrid &&
                                _canOpen('admin_users')) ...[
                              _buildFuturisticButton(
                                context: context,
                                label: 'Gerenciar Usuários',
                                icon: Icons.groups_rounded,
                                accentColor: goldenColor,
                                isPrimary: true,
                                onTap: () {
                                  Navigator.pushNamed(context, '/profiles');
                                },
                              ),
                              const SizedBox(height: 18),
                              _buildFuturisticButton(
                                context: context,
                                label: 'Equipe Técnica',
                                icon: Icons.account_tree_rounded,
                                accentColor: const Color(0xFFFFD166),
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) =>
                                          const AdminTechnicalStaffPage(),
                                    ),
                                  );
                                },
                              ),
                              const SizedBox(height: 18),
                              _buildFuturisticButton(
                                context: context,
                                label: 'Cores do clube',
                                icon: Icons.palette_rounded,
                                accentColor: const Color(0xFFFFC857),
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) =>
                                          const AdminBrandingPage(),
                                    ),
                                  );
                                },
                              ),
                              const SizedBox(height: 18),
                            ],
                            if (!_useCompactAdminGrid &&
                                _canOpen('admin_messages')) ...[
                              _buildFuturisticButton(
                                context: context,
                                label: 'Mensagens',
                                icon: Icons.mark_chat_unread_outlined,
                                accentColor: const Color(0xFFFFD166),
                                badgeCount: unreadMessagesCount,
                                badgeTooltip: unreadMessagesCount == 1
                                    ? '1 mensagem não lida'
                                    : '$unreadMessagesCount mensagens não lidas',
                                badgeColor: Colors.redAccent,
                                badgeIcon: Icons.mark_chat_unread_rounded,
                                onTap: () async {
                                  await Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) =>
                                          const AdminMessagesPage(),
                                    ),
                                  );
                                  _fetchUnreadMessagesCount();
                                },
                              ),
                              const SizedBox(height: 12),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFuturisticButton({
    required BuildContext context,
    required String label,
    required IconData icon,
    required Color accentColor,
    required VoidCallback onTap,
    bool isPrimary = false,
    bool isMuted = false,
    int badgeCount = 0,
    String? badgeTooltip,
    Color badgeColor = Colors.redAccent,
    IconData badgeIcon = Icons.receipt_long_rounded,
  }) {
    final Color baseTextColor = isMuted
        ? Colors.white.withOpacity(0.70)
        : Colors.white.withOpacity(0.88);

    return SizedBox(
      width: double.infinity,
      height: 74,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          Positioned(
            left: 10,
            child: Container(
              width: 10,
              height: 42,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: accentColor.withOpacity(isPrimary ? 0.85 : 0.55),
                    blurRadius: 14,
                    spreadRadius: 1,
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            right: 10,
            child: Container(
              width: 10,
              height: 42,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: accentColor.withOpacity(isPrimary ? 0.85 : 0.45),
                    blurRadius: 14,
                    spreadRadius: 1,
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            top: 6,
            child: Container(
              width: 84,
              height: 4,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: accentColor.withOpacity(0.55),
                    blurRadius: 10,
                    spreadRadius: 0.5,
                  ),
                ],
              ),
            ),
          ),
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: onTap,
                  child: Ink(
                    height: 66,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: accentColor.withOpacity(isPrimary ? 0.45 : 0.22),
                        width: 1.2,
                      ),
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: isPrimary
                            ? [
                                accentColor.withOpacity(0.28),
                                accentColor.withOpacity(0.12),
                              ]
                            : isMuted
                                ? [
                                    Colors.white.withOpacity(0.24),
                                    Colors.white.withOpacity(0.14),
                                  ]
                                : [
                                    Colors.white.withOpacity(0.12),
                                    Colors.white.withOpacity(0.06),
                                  ],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: accentColor.withOpacity(
                            isPrimary ? 0.20 : 0.10,
                          ),
                          blurRadius: 18,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                      child: Row(
                        children: [
                          Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: accentColor.withOpacity(
                                isPrimary ? 0.16 : 0.10,
                              ),
                              border: Border.all(
                                color: accentColor.withOpacity(0.30),
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: accentColor.withOpacity(0.35),
                                  blurRadius: 14,
                                  spreadRadius: 1,
                                ),
                              ],
                            ),
                            child: Icon(
                              icon,
                              color: isMuted
                                  ? Colors.white.withOpacity(0.82)
                                  : accentColor,
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 18),
                          Expanded(
                            child: Text(
                              label,
                              style: TextStyle(
                                color: baseTextColor,
                                fontSize: 17,
                                fontWeight: FontWeight.w400,
                                letterSpacing: 0.2,
                              ),
                            ),
                          ),
                          if (isPrimary)
                            Container(
                              width: 56,
                              alignment: Alignment.centerRight,
                              child: CustomPaint(
                                size: const Size(42, 26),
                                painter: _NodeLinesPainter(
                                  color: accentColor.withOpacity(0.55),
                                ),
                              ),
                            )
                          else
                            Container(
                              width: 56,
                              alignment: Alignment.centerRight,
                              child: CustomPaint(
                                size: const Size(42, 26),
                                painter: _NodeLinesPainter(
                                  color: Colors.white.withOpacity(0.22),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),

          // IMPORTANTE:
          // O badge precisa ficar POR ÚLTIMO no Stack.
          // Antes ele era desenhado antes do botão, e o botão ficava por cima dele.
          if (badgeCount > 0)
            Positioned(
              top: 0,
              right: 12,
              child: Tooltip(
                message: badgeTooltip ?? '$badgeCount pendência(s)',
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: badgeColor,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: Colors.white, width: 1.6),
                    boxShadow: [
                      BoxShadow(
                        color: badgeColor.withOpacity(0.55),
                        blurRadius: 12,
                        spreadRadius: 1,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(badgeIcon, color: Colors.white, size: 12),
                      const SizedBox(width: 4),
                      Text(
                        badgeCount > 99 ? '99+' : badgeCount.toString(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                          height: 1,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _FuturisticBackgroundPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final wavePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..color = const Color(0xFFB7F1FF).withOpacity(0.08)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);

    final wavePaint2 = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..color = const Color(0xFFD8FBFF).withOpacity(0.06)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);

    final path1 = Path();
    path1.moveTo(0, size.height * 0.18);
    path1.cubicTo(
      size.width * 0.20,
      size.height * 0.10,
      size.width * 0.35,
      size.height * 0.28,
      size.width * 0.52,
      size.height * 0.18,
    );
    path1.cubicTo(
      size.width * 0.68,
      size.height * 0.08,
      size.width * 0.82,
      size.height * 0.23,
      size.width,
      size.height * 0.15,
    );
    canvas.drawPath(path1, wavePaint);

    final path2 = Path();
    path2.moveTo(0, size.height * 0.80);
    path2.cubicTo(
      size.width * 0.18,
      size.height * 0.70,
      size.width * 0.36,
      size.height * 0.90,
      size.width * 0.56,
      size.height * 0.80,
    );
    path2.cubicTo(
      size.width * 0.74,
      size.height * 0.72,
      size.width * 0.86,
      size.height * 0.86,
      size.width,
      size.height * 0.78,
    );
    canvas.drawPath(path2, wavePaint2);

    final nodePaint = Paint()
      ..color = const Color(0xFFE8FCFF).withOpacity(0.12)
      ..style = PaintingStyle.fill;

    final linePaint = Paint()
      ..color = const Color(0xFFC7F6FF).withOpacity(0.10)
      ..strokeWidth = 1;

    final points = <Offset>[
      Offset(size.width * 0.72, size.height * 0.34),
      Offset(size.width * 0.82, size.height * 0.38),
      Offset(size.width * 0.90, size.height * 0.33),
      Offset(size.width * 0.76, size.height * 0.44),
      Offset(size.width * 0.88, size.height * 0.47),
      Offset(size.width * 0.69, size.height * 0.52),
      Offset(size.width * 0.83, size.height * 0.56),
      Offset(size.width * 0.93, size.height * 0.52),
      Offset(size.width * 0.73, size.height * 0.64),
      Offset(size.width * 0.86, size.height * 0.67),
    ];

    for (int i = 0; i < points.length - 1; i++) {
      canvas.drawLine(points[i], points[i + 1], linePaint);
    }
    canvas.drawLine(points[0], points[3], linePaint);
    canvas.drawLine(points[1], points[4], linePaint);
    canvas.drawLine(points[3], points[5], linePaint);
    canvas.drawLine(points[4], points[6], linePaint);
    canvas.drawLine(points[6], points[8], linePaint);
    canvas.drawLine(points[7], points[9], linePaint);

    for (final point in points) {
      canvas.drawCircle(point, 1.8, nodePaint);
    }

    final glowPaint = Paint()
      ..color = const Color(0xFFA4F0FF).withOpacity(0.07)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 26);

    canvas.drawCircle(
      Offset(size.width * 0.20, size.height * 0.25),
      70,
      glowPaint,
    );
    canvas.drawCircle(
      Offset(size.width * 0.78, size.height * 0.55),
      90,
      glowPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _NodeLinesPainter extends CustomPainter {
  final Color color;

  _NodeLinesPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = color
      ..strokeWidth = 1;

    final dotPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final points = <Offset>[
      Offset(size.width * 0.15, size.height * 0.70),
      Offset(size.width * 0.38, size.height * 0.30),
      Offset(size.width * 0.62, size.height * 0.55),
      Offset(size.width * 0.84, size.height * 0.22),
      Offset(size.width * 0.90, size.height * 0.78),
    ];

    canvas.drawLine(points[0], points[1], linePaint);
    canvas.drawLine(points[1], points[2], linePaint);
    canvas.drawLine(points[2], points[3], linePaint);
    canvas.drawLine(points[2], points[4], linePaint);

    for (final point in points) {
      canvas.drawCircle(point, 1.6, dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _NodeLinesPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}
