import 'dart:async';
import 'dart:ui';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../pages/admin_competitions_page.dart';
import '../../pages/chat_rooms_page.dart';
import '../../services/chat_service.dart';
import '../../services/permission_service.dart';
import '../../services/technical_staff_service.dart';
import '../../theme/olympus_theme.dart';
import 'coach_athlete_evaluations_page.dart';
import 'coach_complete_profile_page.dart';
import 'coach_evaluations_hub_page.dart';
import 'coach_messages_page.dart';
import 'coach_pending_center_page.dart';
import 'coach_smart_dashboard_page.dart';
import 'coach_training_sessions_page.dart';
import 'coach_training_planning_dashboard_page.dart';
import 'coach_technical_team_page.dart';

class CoachDashboardPage extends StatefulWidget {
  const CoachDashboardPage({super.key});

  @override
  State<CoachDashboardPage> createState() => _CoachDashboardPageState();
}

class _CoachDashboardPageState extends State<CoachDashboardPage>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final supabase = Supabase.instance.client;
  final PermissionService _permissionService = PermissionService();
  final ChatService _chatService = ChatService();

  bool _isLoading = true;
  bool _isBackgroundReady = false;
  bool _refreshingDashboard = false;
  bool _loadingSecondaryDashboardData = false;
  int _competitionNewCount = 0;
  int _unreadMessagesCount = 0;
  int _chatUnreadCount = 0;
  bool _canAccessChat = true;
  bool _canViewTechnicalTeam = false;
  bool _canCreateTechnicalTraining = true;
  DateTime? _lastCompetitionsViewedAt;
  RealtimeChannel? _competitionsRealtimeChannel;
  RealtimeChannel? _messageParticipantsRealtimeChannel;
  RealtimeChannel? _messagesRealtimeChannel;
  RealtimeChannel? _messageThreadsRealtimeChannel;
  RealtimeChannel? _trainingPlanRealtimeChannel;
  RealtimeChannel? _coachEvaluationsRealtimeChannel;
  Timer? _messagesBadgeFallbackTimer;
  StreamSubscription<int>? _chatUnreadSubscription;
  Timer? _intelligenceDebounceTimer;
  bool _hasLoadedOnce = false;
  DateTime? _lastMessageNotificationAt;
  String _coachFullName = 'Técnico';
  String _coachAvatarUrl = '';
  String _coachRoleLabel = 'Técnico';
  String _technicalRoleLabel = '';
  String _coachTeamGender = 'all';
  int _activeAthletesCount = 0;
  int _todayTrainingsCount = 0;
  int _weekTrainingsCount = 0;
  String _nextCommitmentTitle = '';
  String _nextCommitmentMeta = '';
  String _nextActionLabel = '';
  DateTime? _nextCommitmentAt;
  IconData _nextCommitmentIcon = Icons.event_available_rounded;
  int _activeCompetitionsCount = 0;
  int _pendingEvaluationsCount = 0;
  int _unreadReceivedEvaluationsCount = 0;
  int _unplannedTrainingsCount = 0;
  List<Map<String, dynamic>> _pendingPlanningEvents = [];
  int _championshipsWithoutScoutCount = 0;
  final Map<int, Map<int, int>> _trainingMinutesByYear = {};
  int _trainingChartYear = DateTime.now().year;
  Timer? _nextCommitmentExpiryTimer;

  double get _monthlyEvaluationProgress {
    if (_activeAthletesCount <= 0) return 0;

    final completed = (_activeAthletesCount - _pendingEvaluationsCount)
        .clamp(0, _activeAthletesCount)
        .toInt();

    return completed / _activeAthletesCount;
  }

  int get _monthlyEvaluationsCompletedCount {
    return (_activeAthletesCount - _pendingEvaluationsCount)
        .clamp(0, _activeAthletesCount)
        .toInt();
  }

  OlympusBranding get _branding => OlympusBrandingController.instance.branding;
  Color get olympusBlue => _branding.primaryColor;
  Color get olympusGold => _branding.secondaryColor;
  Color get olympusLightBlue =>
      Color.lerp(_branding.primaryColor, Colors.white, 0.16)!;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshDashboard();
    _loadTechnicalStaffAccess();
    _listenChatUnreadCount();
  }

  Future<void> _loadTechnicalStaffAccess() async {
    try {
      final assignment = await TechnicalStaffService().loadCurrentAssignment();
      final allowed = assignment?.canManageStaff == true ||
          (assignment?.isActive == true &&
              assignment?.technicalRole == TechnicalStaffRole.headCoach);
      if (!mounted) return;
      setState(() {
        _canViewTechnicalTeam = allowed;
        if (assignment != null) {
          _canCreateTechnicalTraining = assignment.canCreateTraining;
          _technicalRoleLabel =
              TechnicalStaffRole.label(assignment.technicalRole);
          _coachRoleLabel = _technicalRoleLabel;
        }
      });
    } catch (_) {
      // A tela continua compatível enquanto a migration é publicada.
    }
  }

  void _listenChatUnreadCount() {
    _chatUnreadSubscription?.cancel();
    _chatUnreadSubscription = _chatService.streamTotalUnreadCount().listen(
      (total) {
        if (!mounted || total == _chatUnreadCount) return;
        setState(() => _chatUnreadCount = total);
      },
      onError: (Object error, StackTrace stackTrace) {
        debugPrint('Erro ao atualizar badge do chat: $error');
      },
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    if (!_isBackgroundReady) {
      final branding = OlympusBrandingController.instance.branding;
      precacheImage(
        branding.backgroundImageUrl.isNotEmpty
            ? NetworkImage(branding.backgroundImageUrl)
            : AssetImage(branding.backgroundAsset),
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

  Future<void> _refreshDashboard() async {
    if (!mounted || _refreshingDashboard) return;
    _refreshingDashboard = true;

    try {
      if (!_hasLoadedOnce) {
        setState(() => _isLoading = true);
      }

      try {
        await _loadCoachProfile().timeout(const Duration(seconds: 8));
      } catch (e) {
        debugPrint('Perfil do técnico carregado parcialmente: $e');
      }

      if (mounted) {
        setState(() {
          _isLoading = false;
          _hasLoadedOnce = true;
        });
        _setupRealtimeListeners();
      }

      // Os indicadores entram progressivamente sem manter a tela inteira presa.
      unawaited(_loadSecondaryDashboardData());
    } finally {
      _refreshingDashboard = false;
    }
  }

  Future<void> _loadSecondaryDashboardData() async {
    if (_loadingSecondaryDashboardData) return;
    _loadingSecondaryDashboardData = true;
    try {
      await Future.wait([
        _loadCompetitionNewCount(),
        _loadUnreadMessagesCount(showNotification: false),
        _loadChatPermission(),
        _loadChatUnreadCount(),
        _loadUnreadReceivedEvaluationsCount(),
        _loadDashboardIntelligence(),
      ]).timeout(const Duration(seconds: 22));
    } catch (e) {
      debugPrint('Indicadores do dashboard carregados parcialmente: $e');
    } finally {
      _loadingSecondaryDashboardData = false;
    }
  }

  void _scheduleDashboardIntelligenceRefresh() {
    _intelligenceDebounceTimer?.cancel();
    _intelligenceDebounceTimer = Timer(
      const Duration(milliseconds: 700),
      _loadDashboardIntelligence,
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startMessagesFallbackTimer();
      _refreshDashboard();
    } else if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _messagesBadgeFallbackTimer?.cancel();
      _messagesBadgeFallbackTimer = null;
    }
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

  DateTime? _getPersistedCompetitionsViewedAt() {
    final user = supabase.auth.currentUser;
    final raw = user?.userMetadata?['last_competitions_viewed_at'];
    if (raw == null) return null;
    return DateTime.tryParse(raw.toString())?.toLocal();
  }

  Future<void> _loadCoachProfile() async {
    final user = supabase.auth.currentUser;
    if (user == null) {
      if (mounted) {
        setState(() {
          _coachFullName = 'Técnico';
          _coachAvatarUrl = '';
          _coachRoleLabel = 'Técnico';
          _coachTeamGender = 'all';
        });
      }
      return;
    }

    try {
      final profile = await supabase
          .from('profiles')
          .select('full_name, avatar_url, user_type, coach_team_gender')
          .eq('id', user.id)
          .maybeSingle();

      final metadataName = user.userMetadata?['full_name']?.toString().trim();
      final fullName = (profile?['full_name'] ?? metadataName ?? 'Técnico')
          .toString()
          .trim();
      final avatarUrl = (profile?['avatar_url'] ?? '').toString().trim();
      final userType = (profile?['user_type'] ?? 'coach').toString().trim();
      final coachTeamGender = _permissionService.normalizeCoachTeamGender(
        profile?['coach_team_gender'],
      );

      if (!mounted) return;
      setState(() {
        _coachFullName = fullName.isEmpty ? 'Técnico' : fullName;
        _coachAvatarUrl = avatarUrl;
        _coachRoleLabel = _technicalRoleLabel.isEmpty
            ? _profileRoleLabel(userType)
            : _technicalRoleLabel;
        _coachTeamGender = coachTeamGender;
      });
    } catch (e) {
      debugPrint('Erro ao carregar perfil do técnico: $e');
    }
  }

  DateTime? _parseFlexibleDate(dynamic value) {
    final raw = (value ?? '').toString().trim();
    if (raw.isEmpty) return null;

    final parsedIso = DateTime.tryParse(raw);
    if (parsedIso != null) return parsedIso.toLocal();

    final parts = raw.split('/');
    if (parts.length == 3) {
      final day = int.tryParse(parts[0]);
      final month = int.tryParse(parts[1]);
      final year = int.tryParse(parts[2]);
      if (day != null && month != null && year != null) {
        return DateTime(year, month, day);
      }
    }

    return null;
  }

  DateTime _combineEventDateAndTime(DateTime date, dynamic rawTime) {
    final time = (rawTime ?? '').toString().trim();
    final match = RegExp(r'^(\d{1,2}):(\d{2})').firstMatch(time);
    final hour = int.tryParse(match?.group(1) ?? '');
    final minute = int.tryParse(match?.group(2) ?? '');

    if (hour == null || minute == null) return date;
    return DateTime(date.year, date.month, date.day, hour, minute);
  }

  void _scheduleNextCommitmentExpiry(DateTime? commitmentAt) {
    _nextCommitmentExpiryTimer?.cancel();
    if (commitmentAt == null) return;

    final remaining = commitmentAt.difference(DateTime.now());
    if (remaining <= Duration.zero) return;

    _nextCommitmentExpiryTimer = Timer(remaining, () {
      if (!mounted) return;
      setState(() {
        _nextCommitmentTitle = '';
        _nextCommitmentMeta = '';
        _nextActionLabel = '';
        _nextCommitmentAt = null;
      });
    });
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  bool _isTrainingType(String value) {
    return value.trim().toLowerCase() == 'treino';
  }

  bool _isCompetitionType(String value) {
    final type = value.trim().toLowerCase();
    return type == 'campeonato' ||
        type == 'amistoso' ||
        type == 'jogo' ||
        type == 'liga';
  }

  bool _isCoachEventRole(dynamic value) {
    final role = (value ?? '').toString().trim().toLowerCase();
    return role == 'coach' ||
        role == 'treinador' ||
        role == 'tecnico' ||
        role == 'técnico';
  }

  bool _coachCanAccessAthleteGender(dynamic athleteGender) {
    final normalizedCoachGender =
        _permissionService.normalizeCoachTeamGender(_coachTeamGender);

    if (normalizedCoachGender == 'all') return true;

    final normalizedAthleteGender =
        (athleteGender ?? '').toString().trim().toLowerCase();

    return normalizedAthleteGender == normalizedCoachGender.toLowerCase();
  }

  Future<void> _loadDashboardIntelligence() async {
    try {
      final user = supabase.auth.currentUser;
      if (user == null) return;

      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final nextSevenDays = today.add(const Duration(days: 7));
      final currentMonthStart = DateTime(now.year, now.month, 1);
      final nextMonthStart = DateTime(now.year, now.month + 1, 1);

      final results = await Future.wait([
        supabase.from('profiles').select('id, user_type, gender, is_active'),
        supabase.from('events').select(
              'id, event_type, event_name, championship_name, event_date, event_time, created_at',
            ),
        supabase
            .from('training_evaluations')
            .select('id, event_id, athlete_id, tipo, created_at'),
        supabase
            .from('match_scouts')
            .select('id, event_id, athlete_id, updated_at, created_at'),
        supabase
            .from('monthly_training_plan_summary')
            .select('coach_id, month, total_minutes')
            .eq('coach_id', user.id),
        supabase
            .from('training_plan_blocks')
            .select('event_id')
            .eq('coach_id', user.id),
        supabase
            .from('convocations')
            .select('event_id, event_role')
            .eq('user_id', user.id),
      ]);

      final profiles = List<Map<String, dynamic>>.from(results[0] as List);
      final events = List<Map<String, dynamic>>.from(results[1] as List);
      final trainingEvaluations =
          List<Map<String, dynamic>>.from(results[2] as List);
      final matchScouts = List<Map<String, dynamic>>.from(results[3] as List);
      final monthlyTrainingRows =
          List<Map<String, dynamic>>.from(results[4] as List);
      final trainingPlanRows =
          List<Map<String, dynamic>>.from(results[5] as List);
      final coachConvocationRows =
          List<Map<String, dynamic>>.from(results[6] as List);
      final coachEventIds = coachConvocationRows
          .where((row) => _isCoachEventRole(row['event_role']))
          .map((row) => (row['event_id'] ?? '').toString())
          .where((id) => id.isNotEmpty)
          .toSet();

      final activeAthleteIds = profiles
          .where((profile) {
            final userType =
                (profile['user_type'] ?? '').toString().toLowerCase().trim();
            final isAthlete = userType == 'athlete' || userType == 'atleta';
            if (!isAthlete) return false;

            final isActive = profile['is_active'] != false;
            if (!isActive) return false;

            return _coachCanAccessAthleteGender(profile['gender']);
          })
          .map((profile) => (profile['id'] ?? '').toString())
          .where((id) => id.isNotEmpty)
          .toSet();

      final eventDates = <String, DateTime>{};
      var todayTrainings = 0;
      var weekTrainings = 0;
      var activeCompetitions = 0;
      final competitionEventIds = <String>{};
      Map<String, dynamic>? nextCommitment;
      DateTime? nextCommitmentDate;

      for (final event in events) {
        final id = (event['id'] ?? '').toString();
        if (id.isEmpty || !coachEventIds.contains(id)) continue;
        final type = (event['event_type'] ?? '').toString();
        final rawDate = _parseFlexibleDate(event['event_date']) ??
            _parseFlexibleDate(event['created_at']);
        final date = rawDate == null
            ? null
            : _combineEventDateAndTime(rawDate, event['event_time']);

        if (id.isNotEmpty && date != null) {
          eventDates[id] = date;
        }

        if (date == null) continue;

        if (_isTrainingType(type)) {
          if (_isSameDay(date, today)) {
            todayTrainings++;
          }
          if (!date.isBefore(today) && date.isBefore(nextSevenDays)) {
            weekTrainings++;
          }
        }

        if (_isCompetitionType(type)) {
          if (!date.isBefore(today.subtract(const Duration(days: 30)))) {
            activeCompetitions++;
          }
          if (id.isNotEmpty) competitionEventIds.add(id);
        }

        if ((_isTrainingType(type) || _isCompetitionType(type)) &&
            date.isAfter(now)) {
          if (nextCommitmentDate == null ||
              date.isBefore(nextCommitmentDate!)) {
            nextCommitmentDate = date;
            nextCommitment = event;
          }
        }
      }

      String nextCommitmentTitle = '';
      String nextCommitmentMeta = '';
      String nextActionLabel = '';
      IconData nextCommitmentIcon = Icons.event_available_rounded;

      if (nextCommitment != null && nextCommitmentDate != null) {
        final type = (nextCommitment!['event_type'] ?? '').toString();
        final eventName = (nextCommitment!['event_name'] ??
                nextCommitment!['championship_name'] ??
                '')
            .toString()
            .trim();
        final time = (nextCommitment!['event_time'] ?? '').toString().trim();
        final date = nextCommitmentDate!;
        final dateLabel = _isSameDay(date, today)
            ? 'Hoje'
            : '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}';

        nextCommitmentTitle = eventName.isNotEmpty
            ? eventName
            : _isTrainingType(type)
                ? 'Próximo treino'
                : 'Próximo jogo';
        nextCommitmentMeta = time.isNotEmpty ? '$dateLabel • $time' : dateLabel;
        nextActionLabel =
            _isTrainingType(type) ? 'Avaliar treino' : 'Preparar competição';
        nextCommitmentIcon = _isTrainingType(type)
            ? Icons.fitness_center_rounded
            : Icons.emoji_events_rounded;
      }

      final evaluatedAthleteIdsThisMonth = <String>{};
      for (final row in trainingEvaluations) {
        final createdAt = _parseFlexibleDate(row['created_at']);
        if (createdAt == null ||
            createdAt.isBefore(currentMonthStart) ||
            !createdAt.isBefore(nextMonthStart)) {
          continue;
        }

        final tipo = (row['tipo'] ?? '').toString().toLowerCase().trim();
        if (tipo != 'completa') continue;

        final athleteId = (row['athlete_id'] ?? '').toString();
        if (athleteId.isNotEmpty && activeAthleteIds.contains(athleteId)) {
          evaluatedAthleteIdsThisMonth.add(athleteId);
        }
      }

      final championshipEventsWithScout = <String>{};
      for (final row in matchScouts) {
        final eventId = (row['event_id'] ?? '').toString();
        if (eventId.isNotEmpty) championshipEventsWithScout.add(eventId);
      }

      final pendingEvaluations =
          (activeAthleteIds.length - evaluatedAthleteIdsThisMonth.length)
              .clamp(0, activeAthleteIds.length)
              .toInt();

      final plannedEventIds = trainingPlanRows
          .map((row) => (row['event_id'] ?? '').toString())
          .where((id) => id.isNotEmpty)
          .toSet();
      final pendingPlanningEvents = events.where((event) {
        final id = (event['id'] ?? '').toString();
        final date = eventDates[id];
        if (id.isEmpty || date == null) return false;
        return coachEventIds.contains(id) &&
            _isTrainingType((event['event_type'] ?? '').toString()) &&
            date.year == now.year &&
            date.month == now.month &&
            !plannedEventIds.contains(id);
      }).map((event) {
        final copy = Map<String, dynamic>.from(event);
        copy['_event_at'] = eventDates[(event['id'] ?? '').toString()];
        return copy;
      }).toList();
      pendingPlanningEvents.sort((a, b) {
        final aDate = a['_event_at'] as DateTime;
        final bDate = b['_event_at'] as DateTime;
        final aPast = aDate.isBefore(now);
        final bPast = bDate.isBefore(now);
        if (aPast != bPast) return aPast ? -1 : 1;
        return aPast ? bDate.compareTo(aDate) : aDate.compareTo(bDate);
      });

      final championshipsWithoutScout = competitionEventIds
          .where((id) => !championshipEventsWithScout.contains(id))
          .length;

      final trainingMinutesByYear = <int, Map<int, int>>{};
      for (final row in monthlyTrainingRows) {
        final month = DateTime.tryParse((row['month'] ?? '').toString());
        if (month == null) continue;

        final rawMinutes = row['total_minutes'];
        final minutes = rawMinutes is num
            ? rawMinutes.round()
            : int.tryParse(rawMinutes?.toString() ?? '') ?? 0;
        final yearMap = trainingMinutesByYear.putIfAbsent(
          month.year,
          () => <int, int>{},
        );
        yearMap[month.month] = (yearMap[month.month] ?? 0) + minutes;
      }

      if (!mounted) return;
      setState(() {
        _activeAthletesCount = activeAthleteIds.length;
        _todayTrainingsCount = todayTrainings;
        _weekTrainingsCount = weekTrainings;
        _nextCommitmentTitle = nextCommitmentTitle;
        _nextCommitmentMeta = nextCommitmentMeta;
        _nextActionLabel = nextActionLabel;
        _nextCommitmentAt = nextCommitmentDate;
        _nextCommitmentIcon = nextCommitmentIcon;
        _activeCompetitionsCount = activeCompetitions;
        _pendingEvaluationsCount = pendingEvaluations;
        _unplannedTrainingsCount = pendingPlanningEvents.length;
        _pendingPlanningEvents = pendingPlanningEvents;
        _championshipsWithoutScoutCount = championshipsWithoutScout;
        _trainingMinutesByYear
          ..clear()
          ..addAll(trainingMinutesByYear);
      });
      _scheduleNextCommitmentExpiry(nextCommitmentDate);
    } catch (e) {
      debugPrint('Erro ao carregar inteligência do dashboard: $e');
    }
  }

  Future<void> _loadUnreadReceivedEvaluationsCount() async {
    final coachId = supabase.auth.currentUser?.id;
    if (coachId == null) return;

    try {
      final rows = await supabase
          .from('coach_evaluations')
          .select('id, coach_viewed_at')
          .eq('coach_id', coachId)
          .eq('visible_to_coach', true)
          .eq('admin_review_status', 'approved')
          .filter('coach_viewed_at', 'is', null);
      if (!mounted) return;
      setState(() {
        _unreadReceivedEvaluationsCount = rows.length;
      });
    } catch (e) {
      // Compatibilidade enquanto a coluna coach_viewed_at ainda não foi criada.
      try {
        final rows = await supabase
            .from('coach_evaluations')
            .select('id')
            .eq('coach_id', coachId)
            .eq('visible_to_coach', true)
            .eq('admin_review_status', 'approved');
        if (!mounted) return;
        setState(() {
          _unreadReceivedEvaluationsCount = rows.length;
        });
      } catch (fallbackError) {
        debugPrint('Erro ao carregar avaliações recebidas: $fallbackError');
      }
    }
  }

  Future<void> _loadCompetitionNewCount() async {
    try {
      final user = supabase.auth.currentUser;
      if (user == null) return;

      final convocationRows = await supabase
          .from('convocations')
          .select('event_id, event_role')
          .eq('user_id', user.id);
      final eventIds = List<Map<String, dynamic>>.from(convocationRows)
          .where((row) => _isCoachEventRole(row['event_role']))
          .map((row) => (row['event_id'] ?? '').toString())
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList(growable: false);

      if (eventIds.isEmpty) {
        if (mounted) setState(() => _competitionNewCount = 0);
        return;
      }

      final response = await supabase
          .from('events')
          .select('id, created_at, event_type')
          .inFilter('id', eventIds)
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

  Future<void> _loadUnreadMessagesCount(
      {required bool showNotification}) async {
    final user = supabase.auth.currentUser;
    if (user == null) {
      if (mounted) {
        setState(() => _unreadMessagesCount = 0);
      }
      return;
    }

    try {
      final response = await supabase
          .from('app_message_participants')
          .select('unread_count')
          .eq('user_id', user.id);

      var total = 0;
      for (final row in List<Map<String, dynamic>>.from(response)) {
        final value = row['unread_count'];
        if (value is int) {
          total += value;
        } else if (value is num) {
          total += value.toInt();
        } else {
          total += int.tryParse((value ?? '0').toString()) ?? 0;
        }
      }

      final previous = _unreadMessagesCount;
      if (!mounted) return;
      setState(() => _unreadMessagesCount = total);

      if (showNotification && total > previous) {
        final now = DateTime.now();
        final canNotify = _lastMessageNotificationAt == null ||
            now.difference(_lastMessageNotificationAt!).inSeconds >= 4;

        if (canNotify) {
          _lastMessageNotificationAt = now;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                total == 1
                    ? 'Você tem 1 nova mensagem.'
                    : 'Você tem $total mensagens não lidas.',
              ),
              action: SnackBarAction(
                label: 'Abrir',
                onPressed: _navigateToMessages,
              ),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Erro ao carregar badge de mensagens: $e');
    }
  }

  Future<void> _loadChatUnreadCount() async {
    final total = await _chatService.getTotalUnreadCount();
    if (!mounted) return;

    setState(() => _chatUnreadCount = total);
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

  void _setupRealtimeListeners() {
    final user = supabase.auth.currentUser;

    _competitionsRealtimeChannel ??=
        supabase.channel('coach-dashboard-competitions')
          ..onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'events',
            callback: (_) {
              _loadCompetitionNewCount();
              _scheduleDashboardIntelligenceRefresh();
            },
          )
          ..subscribe();

    _trainingPlanRealtimeChannel ??= supabase
        .channel('coach-dashboard-training-plan-${user?.id ?? 'anonymous'}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'training_plan_blocks',
          callback: (_) => _scheduleDashboardIntelligenceRefresh(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'training_plans',
          callback: (_) => _scheduleDashboardIntelligenceRefresh(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'technical_staff_assignments',
          callback: (_) {
            _loadTechnicalStaffAccess();
            _scheduleDashboardIntelligenceRefresh();
          },
        )
        .subscribe();

    _coachEvaluationsRealtimeChannel ??= supabase
        .channel(
            'coach-dashboard-received-evaluations-${user?.id ?? 'anonymous'}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'coach_evaluations',
          callback: (_) => _loadUnreadReceivedEvaluationsCount(),
        )
        .subscribe();

    if (user == null) return;

    // Realtime robusto para mensagens:
    // 1) O badge é calculado sempre no banco, pela tabela app_message_participants.
    // 2) Evitei depender apenas do filtro do Realtime, porque em alguns projetos
    //    o filtro por UUID/string pode não disparar como esperado no Flutter Web.
    // 3) O polling leve abaixo é fallback de segurança caso o websocket caia.
    _messageParticipantsRealtimeChannel ??= supabase
        .channel('coach-dashboard-message-participants-${user.id}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'app_message_participants',
          callback: (_) {
            _loadUnreadMessagesCount(showNotification: true);
          },
        )
        .subscribe((status, [error]) {
      debugPrint(
        'Realtime app_message_participants status: $status error: $error',
      );
      if (status == RealtimeSubscribeStatus.subscribed) {
        _loadUnreadMessagesCount(showNotification: false);
      }
    });

    _messagesRealtimeChannel ??= supabase
        .channel('coach-dashboard-messages-${user.id}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'app_messages',
          callback: (_) {
            _loadUnreadMessagesCount(showNotification: true);
          },
        )
        .subscribe((status, [error]) {
      debugPrint('Realtime app_messages status: $status error: $error');
    });

    _messageThreadsRealtimeChannel ??= supabase
        .channel('coach-dashboard-message-threads-${user.id}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'app_message_threads',
          callback: (_) {
            _loadUnreadMessagesCount(showNotification: true);
          },
        )
        .subscribe((status, [error]) {
      debugPrint(
        'Realtime app_message_threads status: $status error: $error',
      );
    });

    _startMessagesFallbackTimer();
  }

  void _startMessagesFallbackTimer() {
    _messagesBadgeFallbackTimer ??= Timer.periodic(
      const Duration(seconds: 60),
      (_) {
        _loadUnreadMessagesCount(showNotification: true);
        _loadChatUnreadCount();
      },
    );
  }

  void _navigateToEditCoachProfile() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const CoachCompleteProfilePage(
          isEditing: true,
        ),
      ),
    ).then((_) {
      _loadCoachProfile();
      _loadDashboardIntelligence();
    });
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

  void _navigateToAgenda() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const CoachTrainingSessionsPage(
          initialTipoEvento: 'treino',
          lockTipoEvento: true,
          pageTitle: 'Agenda do Técnico',
          agendaMode: true,
        ),
      ),
    ).then((_) => _loadDashboardIntelligence());
  }

  void _navigateToTrainingPlanner() {
    if (!_canCreateTechnicalTraining) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'O administrador ainda não liberou a criação de treinos.',
          ),
        ),
      );
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const CoachTrainingSessionsPage(
          initialTipoEvento: 'treino',
          lockTipoEvento: true,
          pageTitle: 'Planejamento de treinos',
        ),
      ),
    );
  }

  void _navigateToChampionshipEvaluations() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const CoachTrainingSessionsPage(
          initialTipoEvento: 'campeonato',
          lockTipoEvento: true,
        ),
      ),
    );
  }

  void _navigateToTrainingPlanningDashboard() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const CoachTrainingPlanningDashboardPage(),
      ),
    );
  }

  void _navigateToMessages() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const CoachMessagesPage(),
      ),
    ).then((_) => _loadUnreadMessagesCount(showNotification: false));
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

  void _navigateToSmartDashboard() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const CoachSmartDashboardPage(),
      ),
    );
  }

  void _navigateToAthleteEvaluations() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const CoachAthleteEvaluationTeamSelectPage(),
      ),
    );
  }

  void _navigateToEvaluationsHub() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CoachEvaluationsHubPage(
          pendingEvaluationsCount: _visiblePendingEvaluationsCount,
          receivedEvaluationsCount: _unreadReceivedEvaluationsCount,
        ),
      ),
    ).then((_) {
      _loadUnreadReceivedEvaluationsCount();
      _loadDashboardIntelligence();
    });
  }

  void _navigateToPendingCenter() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CoachPendingCenterPage(
          pendingEvaluationsCount: _visiblePendingEvaluationsCount,
          unplannedTrainingsCount: _unplannedTrainingsCount,
          championshipsWithoutScoutCount: _championshipsWithoutScoutCount,
          unreadMessagesCount: _unreadMessagesCount,
          onOpenEvaluations: _navigateToEvaluationsHub,
          onOpenPlanning: _navigateToTrainingPlanningDashboard,
          onOpenMessages: _navigateToMessages,
        ),
      ),
    ).then((_) => _loadDashboardIntelligence());
  }

  Widget _buildPremiumDashboardBackground() {
    final branding = OlympusBrandingController.instance.branding;
    return SizedBox.expand(
      child: Stack(
        fit: StackFit.expand,
        children: [
          branding.backgroundImageUrl.isNotEmpty
              ? CachedNetworkImage(
                  imageUrl: branding.backgroundImageUrl,
                  width: double.infinity,
                  height: double.infinity,
                  fit: BoxFit.cover,
                  alignment: Alignment.center,
                  errorWidget: (_, __, ___) => Image.asset(
                    branding.backgroundAsset,
                    fit: BoxFit.cover,
                    alignment: Alignment.center,
                  ),
                )
              : Image.asset(
                  branding.backgroundAsset,
                  width: double.infinity,
                  height: double.infinity,
                  fit: BoxFit.cover,
                  alignment: Alignment.center,
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                        color: Color.lerp(olympusBlue, Colors.black, 0.24)!);
                  },
                ),
          Container(
            color: Colors.black.withOpacity(0.10),
          ),
          Container(
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
          Container(
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
        ],
      ),
    );
  }

  String _profileRoleLabel(String value) {
    final normalized = value.trim().toLowerCase();

    if (normalized == 'coach' ||
        normalized == 'tecnico' ||
        normalized == 'técnico' ||
        normalized == 'treinador') {
      return 'Técnico';
    }

    if (normalized == 'admin') return 'Administrador';
    if (normalized == 'athlete' || normalized == 'atleta') return 'Atleta';

    return value.trim().isEmpty ? 'Técnico' : value.trim();
  }

  String _coachFirstName() {
    final parts = _coachFullName.trim().split(RegExp(r'\s+'));
    return parts.isEmpty || parts.first.isEmpty ? 'Técnico' : parts.first;
  }

  String _coachInitials() {
    final parts = _coachFullName
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();

    if (parts.isEmpty) return 'T';
    if (parts.length == 1) return parts.first.characters.first.toUpperCase();

    return '${parts.first.characters.first}${parts.last.characters.first}'
        .toUpperCase();
  }

  void _navigateToTechnicalTeam() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const CoachTechnicalTeamPage()),
    );
  }

  String? _resolvedCoachAvatarUrl() {
    final value = _coachAvatarUrl.trim();
    if (value.isEmpty) return null;
    if (value.startsWith('http://') || value.startsWith('https://')) {
      return value;
    }
    return supabase.storage.from('avatars').getPublicUrl(value);
  }

  Widget _buildCoachAvatar() {
    final avatarUrl = _resolvedCoachAvatarUrl();

    return Container(
      width: 88,
      height: 88,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: [
            Color.lerp(olympusGold, Colors.white, 0.30)!,
            Color.lerp(olympusGold, Colors.black, 0.20)!,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: olympusGold.withOpacity(0.45),
            blurRadius: 14,
            spreadRadius: 1,
          ),
          BoxShadow(
            color: Colors.black.withOpacity(0.22),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      padding: const EdgeInsets.all(3),
      child: ClipOval(
        child: Container(
          color: Color.lerp(olympusBlue, Colors.black, 0.12)!,
          child: avatarUrl != null
              ? CachedNetworkImage(
                  imageUrl: avatarUrl,
                  fit: BoxFit.cover,
                  alignment: Alignment.topCenter,
                  memCacheWidth: 240,
                  memCacheHeight: 240,
                  fadeInDuration: const Duration(milliseconds: 120),
                  placeholder: (_, __) => _buildCoachInitialsFallback(),
                  errorWidget: (_, __, ___) => _buildCoachInitialsFallback(),
                )
              : _buildCoachInitialsFallback(),
        ),
      ),
    );
  }

  Widget _buildCoachInitialsFallback() {
    return Center(
      child: Text(
        _coachInitials(),
        style: TextStyle(
          color: Color.lerp(olympusGold, Colors.white, 0.62)!,
          fontSize: 28,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.8,
        ),
      ),
    );
  }

  Widget _buildCoachMetricPill({
    required IconData icon,
    required String value,
    required String label,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: Colors.white.withOpacity(0.08),
        border: Border.all(color: Colors.white.withOpacity(0.14)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon,
              color: Color.lerp(olympusGold, Colors.white, 0.62)!, size: 14),
          const SizedBox(width: 5),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11.5,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withOpacity(0.78),
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCoachStatsWrap() {
    return Wrap(
      spacing: 7,
      runSpacing: 7,
      children: [
        _buildCoachMetricPill(
          icon: Icons.groups_rounded,
          value: '$_activeAthletesCount',
          label: 'atletas',
        ),
        _buildCoachMetricPill(
          icon: Icons.calendar_month_rounded,
          value: '$_weekTrainingsCount',
          label: 'treinos/7d',
        ),
        _buildCoachMetricPill(
          icon: Icons.mark_chat_unread_rounded,
          value: '$_unreadMessagesCount',
          label: 'msgs',
        ),
      ],
    );
  }

  int get _daysUntilEndOfCurrentMonth {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final lastDayOfMonth = DateTime(now.year, now.month + 1, 0);
    return lastDayOfMonth.difference(today).inDays;
  }

  bool get _shouldShowMonthlyClosingReminder {
    return _pendingEvaluationsCount > 0 && _daysUntilEndOfCurrentMonth <= 7;
  }

  bool get _isUrgentMonthlyClosingReminder {
    return _pendingEvaluationsCount > 0 && _daysUntilEndOfCurrentMonth <= 3;
  }

  bool get _isMonthlyEvaluationReminderWindow {
    return _daysUntilEndOfCurrentMonth <= 7;
  }

  int get _visiblePendingEvaluationsCount {
    return _isMonthlyEvaluationReminderWindow ? _pendingEvaluationsCount : 0;
  }

  int get _evaluationsBadgeCount =>
      _visiblePendingEvaluationsCount + _unreadReceivedEvaluationsCount;

  String get _monthlyClosingReminderTitle {
    if (_isUrgentMonthlyClosingReminder) {
      return 'Fechamento mensal urgente';
    }
    return 'Fechamento mensal se aproximando';
  }

  String get _monthlyClosingReminderText {
    final days = _daysUntilEndOfCurrentMonth;
    final dayLabel = days == 1 ? '1 dia' : '$days dias';
    final count = _visiblePendingEvaluationsCount;
    final athleteLabel = count == 1
        ? '1 atleta ainda está sem avaliação mensal completa.'
        : '$count atletas ainda estão sem avaliação mensal completa.';

    if (_isUrgentMonthlyClosingReminder) {
      return 'Último aviso: faltam $dayLabel para fechar o mês. $athleteLabel';
    }

    return 'Lembrete: faltam $dayLabel para fechar o mês. $athleteLabel';
  }

  Widget _buildMonthlyClosingReminder() {
    if (!_shouldShowMonthlyClosingReminder) return const SizedBox.shrink();

    final color = _isUrgentMonthlyClosingReminder
        ? const Color(0xFFDC2626)
        : const Color(0xFFF59E0B);

    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.20),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.42)),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.14),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            _isUrgentMonthlyClosingReminder
                ? Icons.notification_important_rounded
                : Icons.notifications_active_outlined,
            color: Colors.white,
            size: 23,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _monthlyClosingReminderTitle,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13.2,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _monthlyClosingReminderText,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.88),
                    fontSize: 12.2,
                    fontWeight: FontWeight.w700,
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _planningAlertColor(DateTime eventAt) {
    final difference = eventAt.difference(DateTime.now());
    if (difference <= Duration.zero) return const Color(0xFFDC2626);
    if (difference <= const Duration(hours: 48)) {
      return const Color(0xFFE67E22);
    }
    if (difference <= const Duration(days: 7)) {
      return const Color(0xFFF59E0B);
    }
    return const Color(0xFF3B82F6);
  }

  Widget _buildCompactPlanningAlert() {
    if (_pendingPlanningEvents.isEmpty) return const SizedBox.shrink();

    final now = DateTime.now();
    final nextWeek = now.add(const Duration(days: 7));
    final weekCount = _pendingPlanningEvents.where((event) {
      final date = event['_event_at'] as DateTime;
      return date.isAfter(now) && !date.isAfter(nextWeek);
    }).length;
    final overdueCount = _pendingPlanningEvents
        .where((event) => (event['_event_at'] as DateTime).isBefore(now))
        .length;
    final first = _pendingPlanningEvents.first;
    final firstDate = first['_event_at'] as DateTime;
    final color = overdueCount > 0
        ? const Color(0xFFDC2626)
        : _planningAlertColor(firstDate);
    final eventName = (first['event_name'] ?? 'Treino').toString();
    final dateLabel = _isSameDay(firstDate, now)
        ? 'Hoje às ${firstDate.hour.toString().padLeft(2, '0')}:${firstDate.minute.toString().padLeft(2, '0')}'
        : '${firstDate.day.toString().padLeft(2, '0')}/${firstDate.month.toString().padLeft(2, '0')} às ${firstDate.hour.toString().padLeft(2, '0')}:${firstDate.minute.toString().padLeft(2, '0')}';

    return Container(
      margin: const EdgeInsets.only(top: 12),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _navigateToTrainingPlanner,
          borderRadius: BorderRadius.circular(15),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
            decoration: BoxDecoration(
              color: color.withOpacity(0.16),
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: color.withOpacity(0.42)),
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.22),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: const Icon(
                    Icons.pending_actions_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Planejamentos pendentes',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          Text(
                            '${_pendingPlanningEvents.length}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '$weekCount nesta semana${overdueCount > 0 ? ' • $overdueCount atrasado(s)' : ''}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.82),
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '$eventName • $dateLabel',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10.7,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: Colors.white,
                  size: 22,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSmartSummaryCard() {
    final visiblePendingEvaluations = _visiblePendingEvaluationsCount;
    final pendingTotal = visiblePendingEvaluations + _unplannedTrainingsCount;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              gradient: LinearGradient(
                colors: [
                  const Color(0xFFFFF4C7).withOpacity(0.34),
                  olympusGold.withOpacity(0.20),
                  Colors.white.withOpacity(0.12),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              border: Border.all(color: olympusGold.withOpacity(0.34)),
              boxShadow: [
                BoxShadow(
                  color: olympusGold.withOpacity(0.16),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
                BoxShadow(
                  color: Colors.black.withOpacity(0.18),
                  blurRadius: 16,
                  offset: const Offset(0, 7),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: olympusGold.withOpacity(0.16),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: olympusGold.withOpacity(0.30),
                        ),
                      ),
                      child: Icon(
                        Icons.auto_awesome_rounded,
                        color: Color.lerp(olympusGold, Colors.white, 0.62)!,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Resumo inteligente de hoje',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15.5,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            pendingTotal > 0
                                ? '$pendingTotal pendência(s) pedem atenção.'
                                : 'Nenhuma pendência crítica encontrada.',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.82),
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _buildSummaryBadge(
                      icon: Icons.fitness_center_rounded,
                      value: '$_todayTrainingsCount',
                      label: 'treinos hoje',
                      color: const Color(0xFF3B82F6),
                    ),
                    _buildSummaryBadge(
                      icon: Icons.mark_chat_unread_rounded,
                      value: '$_unreadMessagesCount',
                      label: 'mensagens',
                      color: const Color(0xFF2563EB),
                    ),
                    if (visiblePendingEvaluations > 0)
                      _buildSummaryBadge(
                        icon: Icons.warning_amber_rounded,
                        value: '$visiblePendingEvaluations',
                        label: 'sem avaliação no mês',
                        color: const Color(0xFFF59E0B),
                      ),
                  ],
                ),
                _buildCompactPlanningAlert(),
                _buildMonthlyClosingReminder(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryBadge({
    required IconData icon,
    required String value,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: color.withOpacity(0.14),
        border: Border.all(color: color.withOpacity(0.26)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 15),
          const SizedBox(width: 6),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withOpacity(0.84),
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  String _formatTrainingDuration(int minutes) {
    if (minutes < 60) return '${minutes}min';
    final hours = minutes ~/ 60;
    final remaining = minutes % 60;
    return remaining == 0 ? '${hours}h' : '${hours}h ${remaining}min';
  }

  Widget _buildTrainingHistoryCard() {
    const monthLabels = [
      'J',
      'F',
      'M',
      'A',
      'M',
      'J',
      'J',
      'A',
      'S',
      'O',
      'N',
      'D',
    ];
    final yearData = _trainingMinutesByYear[_trainingChartYear] ?? const {};
    final values = List<int>.generate(
      12,
      (index) => yearData[index + 1] ?? 0,
    );
    final total = values.fold<int>(0, (sum, value) => sum + value);
    final maxValue = math.max(1, values.fold<int>(0, math.max));

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _navigateToTrainingPlanningDashboard,
          borderRadius: BorderRadius.circular(22),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
              child: Container(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 13),
                decoration: BoxDecoration(
                  color: Color.lerp(olympusBlue, Colors.black, 0.28)!
                      .withOpacity(0.82),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: Colors.white.withOpacity(0.22)),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.stacked_bar_chart_rounded,
                          color: olympusGold,
                          size: 21,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Tempo de treino',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              Text(
                                '${_formatTrainingDuration(total)} planejados em $_trainingChartYear',
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.76),
                                  fontSize: 11.2,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          tooltip: 'Ano anterior',
                          onPressed: () => setState(() {
                            _trainingChartYear--;
                          }),
                          icon: const Icon(
                            Icons.chevron_left_rounded,
                            color: Colors.white,
                          ),
                        ),
                        Text(
                          '$_trainingChartYear',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          tooltip: 'Próximo ano',
                          onPressed: _trainingChartYear >= DateTime.now().year
                              ? null
                              : () => setState(() {
                                    _trainingChartYear++;
                                  }),
                          icon: Icon(
                            Icons.chevron_right_rounded,
                            color: _trainingChartYear >= DateTime.now().year
                                ? Colors.white24
                                : Colors.white,
                          ),
                        ),
                      ],
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Tempo em cada mês',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.70),
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(height: 5),
                    SizedBox(
                      height: 82,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: List.generate(12, (index) {
                          final value = values[index];
                          final barHeight =
                              value == 0 ? 4.0 : 8 + (48 * value / maxValue);
                          return Expanded(
                            child: Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 2),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  Tooltip(
                                    message:
                                        '${_formatTrainingDuration(value)} em ${index + 1}/$_trainingChartYear',
                                    child: AnimatedContainer(
                                      duration:
                                          const Duration(milliseconds: 280),
                                      height: barHeight,
                                      decoration: BoxDecoration(
                                        color: value == 0
                                            ? Colors.white.withOpacity(0.12)
                                            : olympusGold,
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 5),
                                  Text(
                                    monthLabels[index],
                                    style: TextStyle(
                                      color: Colors.white.withOpacity(0.74),
                                      fontSize: 9,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }),
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
  }

  Widget _buildCompactDashboardCard({
    required IconData icon,
    required String title,
    required Color color,
    required VoidCallback onTap,
    int? badgeCount,
    bool horizontal = false,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(11),
          decoration: BoxDecoration(
            color: const Color(0xFF173B61).withOpacity(0.72),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withOpacity(0.22)),
          ),
          child: Stack(
            children: [
              horizontal
                  ? Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: color.withOpacity(0.20),
                            borderRadius: BorderRadius.circular(11),
                          ),
                          child: Icon(icon, color: Colors.white, size: 21),
                        ),
                        const SizedBox(width: 11),
                        Expanded(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13.2,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        const Icon(
                          Icons.arrow_forward_rounded,
                          color: Colors.white70,
                          size: 19,
                        ),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: color.withOpacity(0.20),
                            borderRadius: BorderRadius.circular(11),
                          ),
                          child: Icon(icon, color: Colors.white, size: 20),
                        ),
                        const SizedBox(height: 7),
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12.8,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
              if (badgeCount != null && badgeCount > 0)
                Positioned(
                  right: 0,
                  top: 0,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEF4444),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '$badgeCount',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDashboardActions() {
    Widget compact(Widget child) => SizedBox(height: 92, child: child);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: compact(
                  _buildCompactDashboardCard(
                    icon: Icons.fact_check_outlined,
                    title: 'Avaliações',
                    color: const Color(0xFF8B5CF6),
                    onTap: _navigateToEvaluationsHub,
                    badgeCount: _evaluationsBadgeCount > 0
                        ? _evaluationsBadgeCount
                        : null,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: compact(
                  _buildCompactDashboardCard(
                    icon: Icons.emoji_events_outlined,
                    title: 'Competições',
                    color: const Color(0xFF2C5F8D),
                    onTap: _navigateToCompetitions,
                    badgeCount:
                        _competitionNewCount > 0 ? _competitionNewCount : null,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: compact(
                  _buildCompactDashboardCard(
                    icon: Icons.analytics_outlined,
                    title: 'Planejamento',
                    color: olympusGold,
                    onTap: _navigateToTrainingPlanningDashboard,
                    badgeCount: _unplannedTrainingsCount > 0
                        ? _unplannedTrainingsCount
                        : null,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: compact(
                  _buildCompactDashboardCard(
                    icon: Icons.mark_chat_unread_outlined,
                    title: 'Mensagens',
                    color: const Color(0xFF2563EB),
                    onTap: _navigateToMessages,
                    badgeCount:
                        _unreadMessagesCount > 0 ? _unreadMessagesCount : null,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 64,
            child: _buildCompactDashboardCard(
              icon: Icons.insights_rounded,
              title: 'Análise completa',
              color: const Color(0xFFF59E0B),
              onTap: _navigateToSmartDashboard,
              horizontal: true,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCoachCommandCenter() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
            decoration: BoxDecoration(
              color: Color.lerp(olympusBlue, Colors.black, 0.34)!
                  .withOpacity(0.90),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white.withOpacity(0.12)),
            ),
            child: Row(
              children: [
                _buildCoachStatusMetric(
                  value: '$_unplannedTrainingsCount',
                  label: 'Planejamentos',
                  color: olympusGold,
                ),
                _coachStatusDivider(),
                _buildCoachStatusMetric(
                  value: '$_evaluationsBadgeCount',
                  label: 'Avaliações',
                  color: const Color(0xFFB69CFF),
                ),
                _coachStatusDivider(),
                _buildCoachStatusMetric(
                  value: '$_unreadMessagesCount',
                  label: 'Mensagens',
                  color: const Color(0xFFFF8FA3),
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
          _buildCoachQuickActions(),
          const SizedBox(height: 17),
          _buildCoachFeaturedAction(),
          const SizedBox(height: 13),
          _buildCoachSportsDirectory(),
        ],
      ),
    );
  }

  Widget _coachStatusDivider() {
    return Container(
      width: 1,
      height: 34,
      margin: const EdgeInsets.symmetric(horizontal: 6),
      color: Colors.white.withOpacity(0.12),
    );
  }

  Widget _buildCoachStatusMetric({
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

  Widget _buildCoachQuickActions() {
    final actions = <({
      String label,
      IconData icon,
      Color color,
      int badge,
      VoidCallback onTap,
    })>[
      (
        label: 'Avaliações',
        icon: Icons.fact_check_rounded,
        color: const Color(0xFFB69CFF),
        badge: _evaluationsBadgeCount,
        onTap: _navigateToEvaluationsHub,
      ),
      (
        label: 'Agenda',
        icon: Icons.calendar_month_rounded,
        color: olympusGold,
        badge: 0,
        onTap: _navigateToAgenda,
      ),
      (
        label: 'Planejamento',
        icon: Icons.menu_book_rounded,
        color: olympusGold,
        badge: _unplannedTrainingsCount,
        onTap: _navigateToTrainingPlanningDashboard,
      ),
      (
        label: 'Mensagens',
        icon: Icons.forum_rounded,
        color: const Color(0xFFFF8FA3),
        badge: _unreadMessagesCount,
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
        label: 'Competições',
        icon: Icons.emoji_events_rounded,
        color: const Color(0xFF70E1F5),
        badge: _competitionNewCount,
        onTap: _navigateToCompetitions,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        const columns = 3;
        const spacing = 12.0;
        final itemWidth =
            (constraints.maxWidth - (spacing * (columns - 1))) / columns;
        return Wrap(
          alignment: WrapAlignment.center,
          spacing: spacing,
          runSpacing: 12,
          children: actions.indexed.map((entry) {
            final action = entry.$2;
            return SizedBox(
              width: itemWidth,
              height: 88,
              child: InkWell(
                onTap: action.onTap,
                borderRadius: BorderRadius.circular(18),
                child: Column(
                  children: [
                    Badge(
                      isLabelVisible: action.badge > 0,
                      label: Text(
                        action.badge > 99 ? '99+' : '${action.badge}',
                      ),
                      backgroundColor: Colors.redAccent,
                      child: Container(
                        width: 54,
                        height: 54,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: action.color.withOpacity(0.16),
                          border: Border.all(
                            color: action.color.withOpacity(0.52),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: action.color.withOpacity(0.14),
                              blurRadius: 12,
                            ),
                          ],
                        ),
                        child: Icon(action.icon, color: action.color, size: 25),
                      ),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      action.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 10.2,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }

  Widget _buildCoachFeaturedAction() {
    final hasPending = _unplannedTrainingsCount > 0 ||
        _visiblePendingEvaluationsCount > 0 ||
        _unreadMessagesCount > 0;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap:
            hasPending ? _navigateToPendingCenter : _navigateToTrainingPlanner,
        borderRadius: BorderRadius.circular(22),
        child: Ink(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            gradient: const LinearGradient(
              colors: [Color(0xFFF4CF4E), Color(0xFFD4A91E)],
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x33D4AF37),
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
                  color: Colors.white.withOpacity(0.26),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  hasPending
                      ? Icons.pending_actions_rounded
                      : Icons.add_task_rounded,
                  color: Color.lerp(olympusBlue, Colors.black, 0.26)!,
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      hasPending
                          ? 'Revisar pendências'
                          : 'Preparar próximo treino',
                      style: TextStyle(
                        color: Color.lerp(olympusBlue, Colors.black, 0.26)!,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      hasPending
                          ? 'Planejamentos, avaliações e mensagens em um só lugar'
                          : 'Seu painel está em dia. Comece um novo planejamento',
                      style: const TextStyle(
                        color: Color(0xCC0A2947),
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_rounded,
                  color: Color.lerp(olympusBlue, Colors.black, 0.26)!),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCoachSportsDirectory() {
    final items = <({
      String label,
      String subtitle,
      IconData icon,
      Color color,
      VoidCallback onTap,
    })>[
      if (_canViewTechnicalTeam)
        (
          label: 'Minha equipe técnica',
          subtitle: 'Profissionais, liderança e treinos',
          icon: Icons.account_tree_rounded,
          color: const Color(0xFFFFD166),
          onTap: _navigateToTechnicalTeam,
        ),
      (
        label: 'Análise completa',
        subtitle: 'Indicadores e evolução da equipe',
        icon: Icons.insights_rounded,
        color: const Color(0xFFB69CFF),
        onTap: _navigateToSmartDashboard,
      ),
    ];

    return Container(
      decoration: BoxDecoration(
        color: Color.lerp(olympusBlue, Colors.black, 0.20)!.withOpacity(0.90),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withOpacity(0.13)),
      ),
      child: Column(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(15, 14, 15, 7),
            child: Row(
              children: [
                Text(
                  'Gestão técnica',
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
                    color: olympusGold,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.2,
                  ),
                ),
              ],
            ),
          ),
          ...items.indexed.map((entry) => Column(
                children: [
                  if (entry.$1 > 0)
                    Divider(
                      height: 1,
                      indent: 65,
                      color: Colors.white.withOpacity(0.09),
                    ),
                  ListTile(
                    onTap: entry.$2.onTap,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 3,
                    ),
                    leading: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: entry.$2.color.withOpacity(0.14),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        entry.$2.icon,
                        color: entry.$2.color,
                        size: 21,
                      ),
                    ),
                    title: Text(
                      entry.$2.label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 13.5,
                      ),
                    ),
                    subtitle: Text(
                      entry.$2.subtitle,
                      style:
                          const TextStyle(color: Colors.white54, fontSize: 11),
                    ),
                    trailing: const Icon(
                      Icons.chevron_right_rounded,
                      color: Colors.white38,
                    ),
                  ),
                ],
              )),
          const SizedBox(height: 6),
        ],
      ),
    );
  }

  String _smartGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Bom dia';
    if (hour < 18) return 'Boa tarde';
    return 'Boa noite';
  }

  String _coachTeamLabel() {
    final normalized =
        _permissionService.normalizeCoachTeamGender(_coachTeamGender);
    switch (normalized) {
      case 'feminino':
        return 'Time feminino';
      case 'masculino':
        return 'Time masculino';
      default:
        return 'Todos os times';
    }
  }

  IconData _coachTeamIcon() {
    final normalized =
        _permissionService.normalizeCoachTeamGender(_coachTeamGender);
    if (normalized == 'feminino') return Icons.female_rounded;
    if (normalized == 'masculino') return Icons.male_rounded;
    return Icons.groups_rounded;
  }

  Widget _buildGlassPill({
    required IconData icon,
    required String label,
    Color? color,
  }) {
    final pillColor = color ?? Colors.white;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: Colors.black.withOpacity(0.18),
        border: Border.all(color: pillColor.withOpacity(0.30)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.18),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: pillColor, size: 14),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withOpacity(0.96),
              fontSize: 11.2,
              fontWeight: FontWeight.w900,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMonthlyEvaluationProgressPanel() {
    final completed = _monthlyEvaluationsCompletedCount;
    final total = _activeAthletesCount;
    final progress = _monthlyEvaluationProgress.clamp(0.0, 1.0);
    final percent = (progress * 100).round();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(15),
        color: Colors.black.withOpacity(0.18),
        border: Border.all(
          color: olympusGold.withOpacity(0.28),
        ),
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
                  borderRadius: BorderRadius.circular(12),
                  color: olympusGold.withOpacity(0.18),
                  border: Border.all(color: olympusGold.withOpacity(0.24)),
                ),
                child: Icon(
                  Icons.assignment_turned_in_rounded,
                  color: Color.lerp(olympusGold, Colors.white, 0.62)!,
                  size: 19,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Avaliações Mensais',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12.8,
                        fontWeight: FontWeight.w900,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      total <= 0
                          ? 'Nenhum atleta ativo no momento'
                          : '$completed de $total atletas avaliados • $percent%',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.82),
                        fontSize: 11.4,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              backgroundColor: Colors.white.withOpacity(0.18),
              valueColor: AlwaysStoppedAnimation<Color>(
                _isUrgentMonthlyClosingReminder
                    ? const Color(0xFFDC2626)
                    : olympusGold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNextCommitmentPanel() {
    final hasCommitment = _nextCommitmentTitle.trim().isNotEmpty &&
        _nextCommitmentAt != null &&
        _nextCommitmentAt!.isAfter(DateTime.now());
    if (!hasCommitment) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(15),
        color: Colors.black.withOpacity(0.18),
        border: Border.all(color: olympusGold.withOpacity(0.28)),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: olympusGold.withOpacity(0.18),
              border: Border.all(color: olympusGold.withOpacity(0.24)),
            ),
            child: Icon(
              _nextCommitmentIcon,
              color: Color.lerp(olympusGold, Colors.white, 0.62)!,
              size: 19,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Próxima ação: $_nextActionLabel',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12.2,
                    fontWeight: FontWeight.w900,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '$_nextCommitmentTitle • $_nextCommitmentMeta',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.82),
                    fontSize: 11.2,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCoachInfoCard() {
    final backgroundPhotoUrl = _resolvedCoachAvatarUrl();
    final hasBackgroundPhoto = backgroundPhotoUrl != null;

    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: Colors.white.withOpacity(0.24),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.34),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
          BoxShadow(
            color: olympusGold.withOpacity(0.16),
            blurRadius: 30,
            spreadRadius: 1,
          ),
        ],
        gradient: LinearGradient(
          colors: [
            Color.lerp(olympusBlue, Colors.black, 0.36)!,
            Color.lerp(olympusBlue, Colors.black, 0.08)!,
            Color.lerp(olympusBlue, Colors.white, 0.18)!,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(26),
        child: Stack(
          children: [
            if (hasBackgroundPhoto)
              Positioned.fill(
                child: Opacity(
                  opacity: 0.20,
                  child: CachedNetworkImage(
                    imageUrl: backgroundPhotoUrl!,
                    fit: BoxFit.cover,
                    alignment: const Alignment(0, -0.86),
                    memCacheWidth: 900,
                    fadeInDuration: const Duration(milliseconds: 120),
                    errorWidget: (_, __, ___) => const SizedBox.shrink(),
                  ),
                ),
              ),
            if (hasBackgroundPhoto)
              Positioned.fill(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 1.15, sigmaY: 1.15),
                  child: Container(color: Colors.transparent),
                ),
              ),
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: hasBackgroundPhoto
                        ? [
                            Color.lerp(olympusBlue, Colors.black, 0.54)!
                                .withOpacity(0.78),
                            Color.lerp(olympusBlue, Colors.black, 0.08)!
                                .withOpacity(0.62),
                            Color.lerp(olympusBlue, Colors.white, 0.18)!
                                .withOpacity(0.42),
                            Colors.black.withOpacity(0.22),
                          ]
                        : [
                            Color.lerp(olympusBlue, Colors.black, 0.36)!,
                            Color.lerp(olympusBlue, Colors.black, 0.08)!,
                            Color.lerp(olympusBlue, Colors.white, 0.18)!,
                          ],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(0.90, -0.72),
                    radius: 0.90,
                    colors: [
                      Colors.white.withOpacity(0.17),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.black.withOpacity(0.04),
                      Colors.transparent,
                      Colors.black.withOpacity(0.18),
                    ],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
              ),
            ),
            Positioned(
              top: -44,
              right: -28,
              child: Container(
                width: 150,
                height: 150,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withOpacity(0.09),
                ),
              ),
            ),
            Positioned(
              bottom: -58,
              left: -36,
              child: Container(
                width: 132,
                height: 132,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: olympusGold.withOpacity(0.09),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final isCompact = constraints.maxWidth < 360;

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildCoachAvatar(),
                          SizedBox(width: isCompact ? 12 : 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            '${_smartGreeting()}, ${_coachFirstName()}!',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: isCompact ? 17 : 19,
                                              fontWeight: FontWeight.w900,
                                              color: Colors.white,
                                              height: 1.05,
                                              shadows: [
                                                Shadow(
                                                  color: Colors.black
                                                      .withOpacity(0.38),
                                                  blurRadius: 8,
                                                  offset: const Offset(0, 2),
                                                ),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(height: 5),
                                          Text(
                                            _coachFullName,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: isCompact ? 12 : 13,
                                              fontWeight: FontWeight.w800,
                                              color: Colors.white
                                                  .withOpacity(0.92),
                                              height: 1.14,
                                              shadows: [
                                                Shadow(
                                                  color: Colors.black
                                                      .withOpacity(0.30),
                                                  blurRadius: 6,
                                                  offset: const Offset(0, 1),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    _buildGlassPill(
                                      icon: Icons.verified_user_outlined,
                                      label: _coachRoleLabel,
                                      color: Color.lerp(
                                          olympusGold, Colors.white, 0.62)!,
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                Wrap(
                                  spacing: 7,
                                  runSpacing: 7,
                                  children: [
                                    _buildGlassPill(
                                      icon: _coachTeamIcon(),
                                      label: _coachTeamLabel(),
                                      color: Color.lerp(
                                          olympusGold, Colors.white, 0.62)!,
                                    ),
                                    _buildGlassPill(
                                      icon: Icons.groups_rounded,
                                      label: '$_activeAthletesCount atletas',
                                      color: Colors.white,
                                    ),
                                    _buildGlassPill(
                                      icon: Icons.calendar_month_rounded,
                                      label: '$_weekTrainingsCount treinos/7d',
                                      color: Colors.white,
                                    ),
                                    _buildGlassPill(
                                      icon: Icons.mark_chat_unread_rounded,
                                      label: '$_unreadMessagesCount msgs',
                                      color: Colors.white,
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _buildMonthlyEvaluationProgressPanel(),
                      const SizedBox(height: 10),
                      _buildNextCommitmentPanel(),
                      _buildMonthlyClosingReminder(),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDashboardCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
    int? badgeCount,
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
                                  isCompact ? 14 : 16,
                                ),
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
                      if (badgeCount != null && badgeCount > 0)
                        Positioned(
                          right: badgeRight,
                          top: badgeTop,
                          child: Container(
                            constraints: BoxConstraints(
                              minWidth: isCompact ? 24 : 26,
                            ),
                            padding: EdgeInsets.symmetric(
                              horizontal: isCompact ? 7 : 9,
                              vertical: isCompact ? 4 : 5,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.red,
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color: Colors.white,
                                width: 1.8,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.red.withOpacity(0.38),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Text(
                              badgeCount.toString(),
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: isCompact ? 11.5 : 12.5,
                                fontWeight: FontWeight.w800,
                                height: 1,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_competitionsRealtimeChannel != null) {
      supabase.removeChannel(_competitionsRealtimeChannel!);
    }
    if (_messageParticipantsRealtimeChannel != null) {
      supabase.removeChannel(_messageParticipantsRealtimeChannel!);
    }
    if (_messagesRealtimeChannel != null) {
      supabase.removeChannel(_messagesRealtimeChannel!);
    }
    if (_messageThreadsRealtimeChannel != null) {
      supabase.removeChannel(_messageThreadsRealtimeChannel!);
    }
    if (_trainingPlanRealtimeChannel != null) {
      supabase.removeChannel(_trainingPlanRealtimeChannel!);
    }
    if (_coachEvaluationsRealtimeChannel != null) {
      supabase.removeChannel(_coachEvaluationsRealtimeChannel!);
    }
    _messagesBadgeFallbackTimer?.cancel();
    _chatUnreadSubscription?.cancel();
    _intelligenceDebounceTimer?.cancel();
    _nextCommitmentExpiryTimer?.cancel();
    super.dispose();
  }

  Widget _buildDashboardLoadingState() {
    return Center(
      child: Container(
        margin: const EdgeInsets.all(24),
        padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 24),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.96),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: olympusGold.withOpacity(0.72)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.22),
              blurRadius: 22,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 34,
              height: 34,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                color: olympusGold,
              ),
            ),
            SizedBox(height: 14),
            Text(
              'Carregando sua área...',
              style: TextStyle(
                color: olympusBlue,
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      backgroundColor: Colors.transparent,
      appBar: _isLoading
          ? null
          : AppBar(
              title: const Text('Área do Técnico'),
              backgroundColor: olympusBlue,
              foregroundColor: Colors.white,
              actions: [
                IconButton(
                  icon: const Icon(Icons.edit_note_rounded),
                  tooltip: 'Editar meus dados',
                  onPressed: _navigateToEditCoachProfile,
                ),
                IconButton(
                  icon: const Icon(Icons.logout),
                  tooltip: 'Sair',
                  onPressed: _redirectToLogin,
                ),
              ],
            ),
      body: SizedBox.expand(
        child: Stack(
          fit: StackFit.expand,
          children: [
            RepaintBoundary(
              child: _buildPremiumDashboardBackground(),
            ),
            if (_isLoading)
              _buildDashboardLoadingState()
            else
              SafeArea(
                top: false,
                minimum: const EdgeInsets.only(bottom: 12),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.only(bottom: 76),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: constraints.maxHeight,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            _buildCoachInfoCard(),
                            _buildCoachCommandCenter(),
                            _buildTrainingHistoryCard(),
                            const SizedBox(height: 18),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
