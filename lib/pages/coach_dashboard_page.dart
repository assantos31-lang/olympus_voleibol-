import 'dart:async';
import 'dart:ui';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'admin_competitions_page.dart';
import 'coach_training_sessions_page.dart';
import 'coach_ranking_page.dart';
import 'coach_complete_profile_page.dart';
import '../coach/pages/coach_complete_monthly_evaluation_page.dart';
import '../coach/pages/coach_messages_page.dart';
import '../services/permission_service.dart';

Future<void> sendEvaluationMessageToAthlete({
  required SupabaseClient supabase,
  required String athleteId,
  required String title,
  required String body,
}) async {
  Object? lastError;

  final attempts = <Map<String, dynamic>>[
    {
      'table': 'app_messages',
      'data': {
        'recipient_id': athleteId,
        'title': title,
        'body': body,
        'message_type': 'evaluation',
        'created_at': DateTime.now().toIso8601String(),
      },
    },
    {
      'table': 'app_messages',
      'data': {
        'user_id': athleteId,
        'title': title,
        'message': body,
        'type': 'evaluation',
        'created_at': DateTime.now().toIso8601String(),
      },
    },
    {
      'table': 'user_messages',
      'data': {
        'user_id': athleteId,
        'title': title,
        'body': body,
        'created_at': DateTime.now().toIso8601String(),
      },
    },
    {
      'table': 'user_messages',
      'data': {
        'recipient_id': athleteId,
        'subject': title,
        'content': body,
        'created_at': DateTime.now().toIso8601String(),
      },
    },
  ];

  for (final attempt in attempts) {
    try {
      await supabase
          .from(attempt['table'] as String)
          .insert(Map<String, dynamic>.from(attempt['data'] as Map));
      return;
    } catch (e) {
      lastError = e;
    }
  }

  throw Exception(
    'Avaliação salva, mas não foi possível enviar para a atleta: $lastError',
  );
}

class CoachDashboardPage extends StatefulWidget {
  const CoachDashboardPage({super.key});

  @override
  State<CoachDashboardPage> createState() => _CoachDashboardPageState();
}

class _CoachDashboardPageState extends State<CoachDashboardPage>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final supabase = Supabase.instance.client;
  final PermissionService _permissionService = PermissionService();

  bool _isLoading = true;
  bool _isBackgroundReady = false;
  int _competitionNewCount = 0;
  int _unreadMessagesCount = 0;
  DateTime? _lastCompetitionsViewedAt;
  RealtimeChannel? _competitionsRealtimeChannel;
  RealtimeChannel? _messageParticipantsRealtimeChannel;
  RealtimeChannel? _messagesRealtimeChannel;
  RealtimeChannel? _messageThreadsRealtimeChannel;
  Timer? _messagesBadgeFallbackTimer;
  DateTime? _lastMessageNotificationAt;
  String _coachFullName = 'Técnico';
  String _coachAvatarUrl = '';
  String _coachRoleLabel = 'Técnico';
  String _coachTeamGender = 'all';
  int _activeAthletesCount = 0;
  int _todayTrainingsCount = 0;
  int _weekTrainingsCount = 0;
  int _activeCompetitionsCount = 0;
  int _pendingEvaluationsCount = 0;
  int _unplannedTrainingsCount = 0;
  int _championshipsWithoutScoutCount = 0;

  static const Color olympusBlue = Color(0xFF1E3A5F);
  static const Color olympusGold = Color(0xFFD4AF37);
  static const Color olympusLightBlue = Color(0xFF2C5F8D);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshDashboard();
  }

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

  Future<void> _refreshDashboard() async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
    });

    await Future.wait([
      _loadCoachProfile(),
      _loadCompetitionNewCount(),
      _loadUnreadMessagesCount(showNotification: false),
      _loadDashboardIntelligence(),
    ]);

    if (mounted) {
      setState(() {
        _isLoading = false;
      });
      _setupRealtimeListeners();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshDashboard();
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
        _coachRoleLabel = _profileRoleLabel(userType);
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
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final nextSevenDays = today.add(const Duration(days: 7));
      final currentMonthStart = DateTime(now.year, now.month, 1);
      final nextMonthStart = DateTime(now.year, now.month + 1, 1);

      final results = await Future.wait([
        supabase.from('profiles').select('id, user_type, gender, is_active'),
        supabase
            .from('events')
            .select('id, event_type, event_date, created_at'),
        supabase
            .from('training_evaluations')
            .select('id, event_id, athlete_id, tipo, created_at'),
        supabase
            .from('match_scouts')
            .select('id, event_id, athlete_id, updated_at, created_at'),
      ]);

      final profiles = List<Map<String, dynamic>>.from(results[0] as List);
      final events = List<Map<String, dynamic>>.from(results[1] as List);
      final trainingEvaluations =
          List<Map<String, dynamic>>.from(results[2] as List);
      final matchScouts = List<Map<String, dynamic>>.from(results[3] as List);

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
      final trainingEventIdsNextSevenDays = <String>{};
      final competitionEventIds = <String>{};

      for (final event in events) {
        final id = (event['id'] ?? '').toString();
        final type = (event['event_type'] ?? '').toString();
        final date = _parseFlexibleDate(event['event_date']) ??
            _parseFlexibleDate(event['created_at']);

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
            if (id.isNotEmpty) trainingEventIdsNextSevenDays.add(id);
          }
        }

        if (_isCompetitionType(type)) {
          if (!date.isBefore(today.subtract(const Duration(days: 30)))) {
            activeCompetitions++;
          }
          if (id.isNotEmpty) competitionEventIds.add(id);
        }
      }

      final evaluatedAthleteIdsThisMonth = <String>{};
      final trainingEventsWithEvaluation = <String>{};
      for (final row in trainingEvaluations) {
        final createdAt = _parseFlexibleDate(row['created_at']);
        if (createdAt == null ||
            createdAt.isBefore(currentMonthStart) ||
            !createdAt.isBefore(nextMonthStart)) {
          continue;
        }

        final eventId = (row['event_id'] ?? '').toString();
        if (eventId.isNotEmpty) trainingEventsWithEvaluation.add(eventId);

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

      final unplannedTrainings = trainingEventIdsNextSevenDays
          .where((id) => !trainingEventsWithEvaluation.contains(id))
          .length;

      final championshipsWithoutScout = competitionEventIds
          .where((id) => !championshipEventsWithScout.contains(id))
          .length;

      if (!mounted) return;
      setState(() {
        _activeAthletesCount = activeAthleteIds.length;
        _todayTrainingsCount = todayTrainings;
        _weekTrainingsCount = weekTrainings;
        _activeCompetitionsCount = activeCompetitions;
        _pendingEvaluationsCount = pendingEvaluations;
        _unplannedTrainingsCount = unplannedTrainings;
        _championshipsWithoutScoutCount = championshipsWithoutScout;
      });
    } catch (e) {
      debugPrint('Erro ao carregar inteligência do dashboard: $e');
    }
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
              _loadDashboardIntelligence();
            },
          )
          ..subscribe();

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

    _messagesBadgeFallbackTimer ??= Timer.periodic(
      const Duration(seconds: 8),
      (_) => _loadUnreadMessagesCount(showNotification: true),
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

  void _navigateToTrainingPlanner() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const CoachTrainingSessionsPage(
          initialTipoEvento: 'treino',
          lockTipoEvento: true,
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

  void _navigateToRanking() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const CoachRankingPage(),
      ),
    );
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
        ),
      ),
    );
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
    return SizedBox.expand(
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            'assets/images/monte_olimpo_v2.png',
            width: double.infinity,
            height: double.infinity,
            fit: BoxFit.cover,
            alignment: Alignment.center,
            errorBuilder: (context, error, stackTrace) {
              return Container(color: const Color(0xFF102845));
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

  Widget _buildCoachAvatar() {
    final hasPhoto = _coachAvatarUrl.trim().isNotEmpty;

    return Container(
      width: 92,
      height: 92,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
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
      child: ClipRRect(
        borderRadius: BorderRadius.circular(23),
        child: Container(
          color: const Color(0xFF113457),
          child: hasPhoto
              ? Image.network(
                  _coachAvatarUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => _buildCoachInitialsFallback(),
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
        style: const TextStyle(
          color: Color(0xFFFFF2B8),
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
          Icon(icon, color: const Color(0xFFFFF2B8), size: 14),
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
                  const Color(0xFFD4AF37).withOpacity(0.20),
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
                      child: const Icon(
                        Icons.auto_awesome_rounded,
                        color: Color(0xFFFFF2B8),
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

  Widget _buildCoachInfoCard() {
    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: Colors.white.withOpacity(0.22),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.28),
            blurRadius: 20,
            offset: const Offset(0, 9),
          ),
          BoxShadow(
            color: olympusGold.withOpacity(0.14),
            blurRadius: 26,
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
        borderRadius: BorderRadius.circular(22),
        child: Stack(
          children: [
            Positioned(
              top: -42,
              right: -30,
              child: Container(
                width: 142,
                height: 142,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withOpacity(0.08),
                ),
              ),
            ),
            Positioned(
              bottom: -54,
              left: -34,
              child: Container(
                width: 122,
                height: 122,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: olympusGold.withOpacity(0.08),
                ),
              ),
            ),
            Positioned(
              right: 18,
              bottom: 16,
              child: Icon(
                Icons.verified_rounded,
                color: Colors.white.withOpacity(0.10),
                size: 44,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
              child: Row(
                children: [
                  _buildCoachAvatar(),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Olá, ${_coachFirstName()}!',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                            height: 1.08,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          _coachFullName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: Colors.white.withOpacity(0.90),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 7,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 7,
                              ),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(999),
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
                                  width: 1.1,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.verified_user_outlined,
                                    size: 14,
                                    color: Color(0xFF42576B),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    _coachRoleLabel,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w900,
                                      color: Color(0xFF2E4053),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 7,
                              ),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(999),
                                color: olympusGold.withOpacity(0.15),
                                border: Border.all(
                                  color: olympusGold.withOpacity(0.28),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: const [
                                  Icon(
                                    Icons.workspace_premium_outlined,
                                    size: 14,
                                    color: Color(0xFFFFF2B8),
                                  ),
                                  SizedBox(width: 6),
                                  Text(
                                    'Painel premium',
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w900,
                                      color: Color(0xFFFFF2B8),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        _buildCoachStatsWrap(),
                        const SizedBox(height: 10),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(13),
                            color: Colors.white.withOpacity(0.07),
                            border: Border.all(
                              color: olympusGold.withOpacity(0.23),
                            ),
                          ),
                          child: Text(
                            'Gerencie treinos, avaliações e acompanhe as novidades do painel.',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.90),
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              height: 1.24,
                            ),
                          ),
                        ),
                      ],
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
    _messagesBadgeFallbackTimer?.cancel();
    super.dispose();
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
            _buildPremiumDashboardBackground(),
            if (_isLoading)
              const Center(
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            else
              LayoutBuilder(
                builder: (context, constraints) {
                  return SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: constraints.maxHeight,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          _buildCoachInfoCard(),
                          _buildSmartSummaryCard(),
                          _buildDashboardCard(
                            icon: Icons.fact_check_outlined,
                            title: 'Avaliações',
                            subtitle: 'Avaliação de atletas e campeonatos',
                            color: const Color(0xFF8B5CF6),
                            onTap: _navigateToEvaluationsHub,
                            badgeCount: _visiblePendingEvaluationsCount > 0
                                ? _visiblePendingEvaluationsCount
                                : null,
                          ),
                          _buildDashboardCard(
                            icon: Icons.emoji_events_outlined,
                            title: 'Competições',
                            subtitle: 'Veja ligas, campeonatos e amistosos',
                            color: const Color(0xFF2C5F8D),
                            onTap: _navigateToCompetitions,
                            badgeCount: _competitionNewCount > 0
                                ? _competitionNewCount
                                : null,
                          ),
                          _buildDashboardCard(
                            icon: Icons.analytics_outlined,
                            title: 'Dashboard de Planejamento',
                            subtitle:
                                'Tempo mensal por Fundamentos, Tático e Físico',
                            color: const Color(0xFFD4AF37),
                            onTap: _navigateToTrainingPlanningDashboard,
                          ),
                          _buildDashboardCard(
                            icon: Icons.mark_chat_unread_outlined,
                            title: 'Mensagens',
                            subtitle: 'Mensagens enviadas pelo administrador',
                            color: const Color(0xFF2563EB),
                            onTap: _navigateToMessages,
                            badgeCount: _unreadMessagesCount > 0
                                ? _unreadMessagesCount
                                : null,
                          ),
                          _buildDashboardCard(
                            icon: Icons.bar_chart_rounded,
                            title: 'Ranking dos atletas',
                            subtitle:
                                'Desempenho com base nas avaliações salvas',
                            color: const Color(0xFF0EA5A4),
                            onTap: _navigateToRanking,
                          ),
                          _buildDashboardCard(
                            icon: Icons.insights_rounded,
                            title: 'Smart Dashboard',
                            subtitle:
                                'Geral, treinos, campeonatos e radar da equipe',
                            color: const Color(0xFFF59E0B),
                            onTap: _navigateToSmartDashboard,
                          ),
                          const SizedBox(height: 28),
                        ],
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}

class CoachPendingCenterPage extends StatelessWidget {
  const CoachPendingCenterPage({
    super.key,
    required this.pendingEvaluationsCount,
    required this.unplannedTrainingsCount,
    required this.championshipsWithoutScoutCount,
    required this.unreadMessagesCount,
    required this.onOpenEvaluations,
    required this.onOpenPlanning,
    required this.onOpenMessages,
  });

  final int pendingEvaluationsCount;
  final int unplannedTrainingsCount;
  final int championshipsWithoutScoutCount;
  final int unreadMessagesCount;
  final VoidCallback onOpenEvaluations;
  final VoidCallback onOpenPlanning;
  final VoidCallback onOpenMessages;

  static const Color olympusBlue = Color(0xFF1E3A5F);
  static const Color olympusLightBlue = Color(0xFF2C5F8D);
  static const Color olympusGold = Color(0xFFD4AF37);

  int get _total =>
      pendingEvaluationsCount + unplannedTrainingsCount + unreadMessagesCount;

  Widget _background() {
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.asset(
          'assets/images/monte_olimpo_v2.png',
          fit: BoxFit.cover,
          alignment: Alignment.center,
          errorBuilder: (_, __, ___) {
            return Container(color: const Color(0xFF102845));
          },
        ),
        Container(color: Colors.black.withOpacity(0.26)),
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                olympusBlue.withOpacity(0.68),
                olympusLightBlue.withOpacity(0.25),
                Colors.black.withOpacity(0.68),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _pendingCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required int count,
    required Color color,
    required VoidCallback onTap,
  }) {
    final hasPending = count > 0;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 9, 16, 9),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(22),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(22),
                  gradient: LinearGradient(
                    colors: [
                      Colors.white.withOpacity(0.24),
                      Colors.white.withOpacity(0.14),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  border: Border.all(color: Colors.white.withOpacity(0.30)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.20),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      width: 58,
                      height: 58,
                      decoration: BoxDecoration(
                        color: color.withOpacity(hasPending ? 0.22 : 0.10),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: color.withOpacity(0.28)),
                      ),
                      child: Icon(icon, color: Colors.white, size: 30),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            subtitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.84),
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    ConstrainedBox(
                      constraints: const BoxConstraints(
                        minWidth: 38,
                        minHeight: 34,
                      ),
                      child: Container(
                        height: 34,
                        alignment: Alignment.center,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        decoration: BoxDecoration(
                          color: hasPending
                              ? color.withOpacity(0.24)
                              : Colors.white.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: hasPending
                                ? color.withOpacity(0.38)
                                : Colors.white.withOpacity(0.16),
                          ),
                        ),
                        child: Text(
                          '$count',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
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
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Pendências'),
        backgroundColor: olympusBlue,
        foregroundColor: Colors.white,
      ),
      body: SizedBox.expand(
        child: Stack(
          fit: StackFit.expand,
          children: [
            _background(),
            SafeArea(
              child: ListView(
                padding: const EdgeInsets.only(top: 14, bottom: 28),
                children: [
                  Container(
                    margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.16),
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: Colors.white.withOpacity(0.26)),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.notifications_active_outlined,
                          color: olympusGold,
                          size: 30,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _total > 0
                                    ? '$_total item(ns) exigem atenção'
                                    : 'Tudo em dia',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _total > 0
                                    ? 'Priorize os pontos abaixo para manter a equipe organizada.'
                                    : 'Nenhuma pendência crítica encontrada no momento.',
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
                  ),
                  _pendingCard(
                    icon: Icons.assignment_late_outlined,
                    title: 'Atletas sem avaliação do mês',
                    subtitle:
                        'Atletas ativos sem avaliação mensal completa no mês corrente.',
                    count: pendingEvaluationsCount,
                    color: const Color(0xFFF59E0B),
                    onTap: onOpenEvaluations,
                  ),
                  _pendingCard(
                    icon: Icons.calendar_month_outlined,
                    title: 'Treinos sem planejamento',
                    subtitle:
                        'Treinos próximos ainda sem avaliação ou planejamento.',
                    count: unplannedTrainingsCount,
                    color: const Color(0xFF3B82F6),
                    onTap: onOpenPlanning,
                  ),
                  _pendingCard(
                    icon: Icons.mark_chat_unread_outlined,
                    title: 'Mensagens não lidas',
                    subtitle:
                        'Comunicados do administrador aguardando leitura.',
                    count: unreadMessagesCount,
                    color: const Color(0xFF2563EB),
                    onTap: onOpenMessages,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class CoachEvaluationsHubPage extends StatelessWidget {
  const CoachEvaluationsHubPage({
    super.key,
    this.pendingEvaluationsCount = 0,
  });

  final int pendingEvaluationsCount;

  static const Color olympusBlue = Color(0xFF1E3A5F);
  static const Color olympusLightBlue = Color(0xFF2C5F8D);
  static const Color olympusGold = Color(0xFFD4AF37);

  void _openAthleteEvaluations(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const CoachAthleteEvaluationTeamSelectPage(),
      ),
    );
  }

  void _openChampionshipEvaluations(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const CoachTrainingSessionsPage(
          initialTipoEvento: 'campeonato',
          lockTipoEvento: true,
        ),
      ),
    );
  }

  Widget _background() {
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.asset(
          'assets/images/monte_olimpo_v2.png',
          fit: BoxFit.cover,
          alignment: Alignment.center,
          errorBuilder: (_, __, ___) {
            return Container(color: const Color(0xFF102845));
          },
        ),
        Container(color: Colors.black.withOpacity(0.22)),
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                olympusBlue.withOpacity(0.62),
                olympusLightBlue.withOpacity(0.24),
                Colors.black.withOpacity(0.64),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _optionCard({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
    int? badgeCount,
  }) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(22),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(22),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                  child: Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(22),
                      gradient: LinearGradient(
                        colors: [
                          Colors.white.withOpacity(0.24),
                          Colors.white.withOpacity(0.15),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      border: Border.all(color: Colors.white.withOpacity(0.32)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.22),
                          blurRadius: 18,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 58,
                          height: 58,
                          decoration: BoxDecoration(
                            color: color.withOpacity(0.22),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                                color: Colors.white.withOpacity(0.18)),
                          ),
                          child: Icon(icon, color: Colors.white, size: 30),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 5),
                              Text(
                                subtitle,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.88),
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.08),
                            shape: BoxShape.circle,
                            border: Border.all(
                                color: Colors.white.withOpacity(0.14)),
                          ),
                          child: Icon(
                            Icons.arrow_forward_ios_rounded,
                            color: Colors.white.withOpacity(0.82),
                            size: 18,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (badgeCount != null && badgeCount > 0)
            Positioned(
              right: 8,
              top: 2,
              child: Container(
                constraints: const BoxConstraints(minWidth: 26, minHeight: 24),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.red,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: Colors.white, width: 1.8),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.red.withOpacity(0.38),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Text(
                  badgeCount > 99 ? '99+' : badgeCount.toString(),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    height: 1,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Avaliações'),
        backgroundColor: olympusBlue,
        foregroundColor: Colors.white,
      ),
      body: SizedBox.expand(
        child: Stack(
          fit: StackFit.expand,
          children: [
            _background(),
            SafeArea(
              child: ListView(
                padding: const EdgeInsets.only(top: 14, bottom: 28),
                children: [
                  _optionCard(
                    context: context,
                    icon: Icons.assignment_turned_in_outlined,
                    title: 'Avaliação de Atletas',
                    subtitle: 'Avaliação rápida e completa por ciclo',
                    color: const Color(0xFF8B5CF6),
                    onTap: () => _openAthleteEvaluations(context),
                    badgeCount: pendingEvaluationsCount > 0
                        ? pendingEvaluationsCount
                        : null,
                  ),
                  _optionCard(
                    context: context,
                    icon: Icons.emoji_events_outlined,
                    title: 'Avaliar Campeonatos',
                    subtitle: 'Avalie jogos de campeonatos separadamente',
                    color: const Color(0xFF7C3AED),
                    onTap: () => _openChampionshipEvaluations(context),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class CoachSmartDashboardPage extends StatefulWidget {
  const CoachSmartDashboardPage({super.key});

  @override
  State<CoachSmartDashboardPage> createState() =>
      _CoachSmartDashboardPageState();
}

class _CoachSmartDashboardPageState extends State<CoachSmartDashboardPage> {
  final SupabaseClient _supabase = Supabase.instance.client;

  static const Color olympusBlue = Color(0xFF1E3A5F);
  static const Color olympusLightBlue = Color(0xFF2C5F8D);
  static const Color olympusGold = Color(0xFFD4AF37);
  static const Color olympusPurple = Color(0xFF7C3AED);
  static const Color olympusBg = Color(0xFFF4F7FB);
  static const Color olympusText = Color(0xFF17324D);
  static const Color olympusMuted = Color(0xFF53657B);
  static const Color olympusBorder = Color(0xFFE4EDF5);
  static const Color olympusSuccess = Color(0xFF16A34A);
  static const Color olympusWarning = Color(0xFFF59E0B);
  static const Color olympusDanger = Color(0xFFDC2626);

  bool _loading = true;
  String? _error;

  String _scope = 'geral';
  String _period = 'mes';

  List<Map<String, dynamic>> _profiles = [];
  List<Map<String, dynamic>> _events = [];
  List<Map<String, dynamic>> _convocations = [];
  List<Map<String, dynamic>> _checkins = [];
  List<Map<String, dynamic>> _trainingEvaluations = [];
  List<Map<String, dynamic>> _matchScouts = [];

  @override
  void initState() {
    super.initState();
    _loadDashboard();
  }

  DateTime? _periodStart() {
    final now = DateTime.now();

    switch (_period) {
      case 'semana':
        return DateTime(now.year, now.month, now.day)
            .subtract(const Duration(days: 7));
      case 'mes':
        return DateTime(now.year, now.month, 1);
      case 'geral':
        return null;
      default:
        return DateTime(now.year, now.month, 1);
    }
  }

  String get _scopeLabel {
    switch (_scope) {
      case 'treinos':
        return 'Treinos';
      case 'campeonatos':
        return 'Campeonatos';
      default:
        return 'Geral';
    }
  }

  String get _periodLabel {
    switch (_period) {
      case 'semana':
        return 'Semana';
      case 'mes':
        return 'Mês';
      case 'geral':
        return 'Geral';
      default:
        return 'Mês';
    }
  }

  Future<List<Map<String, dynamic>>> _safeSelect(
    String table,
    String columns,
  ) async {
    try {
      final rows = await _supabase.from(table).select(columns);
      return List<Map<String, dynamic>>.from(rows as List);
    } catch (e) {
      debugPrint('Smart Dashboard: tabela $table indisponível: $e');
      return <Map<String, dynamic>>[];
    }
  }

  Future<void> _loadDashboard() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final user = _supabase.auth.currentUser;
      if (user == null) {
        throw Exception('Usuário não autenticado.');
      }

      final results = await Future.wait([
        _safeSelect(
          'profiles',
          'id, full_name, avatar_url, gender, user_type, created_at',
        ),
        _safeSelect(
          'events',
          'id, event_name, event_type, event_date, event_time, championship_name, created_at',
        ),
        _safeSelect(
          'convocations',
          'id, user_id, event_id, status, created_at',
        ),
        _safeSelect(
          'checkins',
          'id, user_id, event_id, check_in_status, created_at, checked_in_at',
        ),
        _safeSelect(
          'training_evaluations',
          'id, event_id, coach_id, athlete_id, tipo, slot, fundamento, motivo, observacao, score, created_at',
        ),
        _safeSelect(
          'match_scouts',
          'id, event_id, coach_id, athlete_id, set_number, '
              'saque_ponto, saque_erro, '
              'recepcao_boa, recepcao_erro, '
              'passe_bom, passe_erro, '
              'levantamento_bom, levantamento_erro, '
              'ataque_ponto, ataque_erro, '
              'largada_bola_boa, largada_bola_erro, '
              'bloqueio_ponto, bloqueio_erro, '
              'defesa_boa, defesa_erro, '
              'observacao, created_at, updated_at',
        ),
      ]);

      if (!mounted) return;
      setState(() {
        _profiles = results[0];
        _events = results[1];
        _convocations = results[2];
        _checkins = results[3];
        _trainingEvaluations = results[4];
        _matchScouts = results[5];
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Erro ao carregar Smart Dashboard: $e';
        _loading = false;
      });
    }
  }

  DateTime? _parseDate(dynamic value) {
    final raw = (value ?? '').toString().trim();
    if (raw.isEmpty) return null;

    final parsedIso = DateTime.tryParse(raw);
    if (parsedIso != null) return parsedIso.toLocal();

    try {
      final parts = raw.split('/');
      if (parts.length == 3) {
        return DateTime(
          int.parse(parts[2]),
          int.parse(parts[1]),
          int.parse(parts[0]),
        );
      }
    } catch (_) {}

    return null;
  }

  bool _isInsidePeriod(dynamic value) {
    final start = _periodStart();
    if (start == null) return true;

    final date = _parseDate(value);
    if (date == null) return false;

    return !date.isBefore(start);
  }

  int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse((value ?? '0').toString()) ?? 0;
  }

  String _eventType(String eventId) {
    if (eventId.isEmpty) return '';

    for (final event in _events) {
      if ((event['id'] ?? '').toString() == eventId) {
        return (event['event_type'] ?? '').toString().toLowerCase().trim();
      }
    }

    return '';
  }

  bool _isTrainingEvent(String eventId) {
    return _eventType(eventId) == 'treino';
  }

  bool _isChampionshipEvent(String eventId) {
    final type = _eventType(eventId);
    return type == 'campeonato' ||
        type == 'amistoso' ||
        type == 'jogo' ||
        type == 'liga';
  }

  bool _scopeMatchesEvent(String eventId) {
    if (_scope == 'geral') return true;
    if (_scope == 'treinos') return _isTrainingEvent(eventId);
    if (_scope == 'campeonatos') return _isChampionshipEvent(eventId);
    return true;
  }

  List<Map<String, dynamic>> get _athletes {
    final list = _profiles.where((profile) {
      final userType = (profile['user_type'] ?? '').toString().toLowerCase();
      return userType == 'athlete' || userType == 'atleta';
    }).toList();

    list.sort((a, b) {
      return (a['full_name'] ?? '')
          .toString()
          .compareTo((b['full_name'] ?? '').toString());
    });

    return list;
  }

  List<Map<String, dynamic>> get _periodEvents {
    return _events.where((event) {
      final eventId = (event['id'] ?? '').toString();
      if (!_scopeMatchesEvent(eventId)) return false;

      final date =
          _parseDate(event['event_date']) ?? _parseDate(event['created_at']);

      final start = _periodStart();
      if (start == null) return true;
      if (date == null) return false;

      return !date.isBefore(start);
    }).toList();
  }

  Set<String> get _periodEventIds {
    return _periodEvents
        .map((event) => (event['id'] ?? '').toString())
        .where((id) => id.isNotEmpty)
        .toSet();
  }

  List<Map<String, dynamic>> get _periodConvocations {
    final eventIds = _periodEventIds;

    return _convocations.where((row) {
      final eventId = (row['event_id'] ?? '').toString();
      return eventIds.contains(eventId) && _scopeMatchesEvent(eventId);
    }).toList();
  }

  bool _isValidCheckin(Map<String, dynamic> row) {
    final status = (row['check_in_status'] ?? '').toString().toLowerCase();
    return status.contains('realizado') ||
        status.contains('checked') ||
        status.contains('success') ||
        status.contains('completed') ||
        status.contains('done') ||
        status.contains('ok');
  }

  List<Map<String, dynamic>> get _periodCheckins {
    final eventIds = _periodEventIds;

    return _checkins.where((row) {
      final eventId = (row['event_id'] ?? '').toString();
      if (!eventIds.contains(eventId)) return false;
      if (!_scopeMatchesEvent(eventId)) return false;

      final dateSource = row['checked_in_at'] ?? row['created_at'];
      return _isInsidePeriod(dateSource);
    }).toList();
  }

  List<Map<String, dynamic>> get _periodTrainingEvaluations {
    return _trainingEvaluations.where((row) {
      final eventId = (row['event_id'] ?? '').toString();

      if (_scope == 'campeonatos') return false;
      if (_scope == 'treinos' &&
          eventId.isNotEmpty &&
          !_isTrainingEvent(eventId)) {
        return false;
      }

      return _isInsidePeriod(row['created_at']);
    }).toList();
  }

  List<Map<String, dynamic>> get _periodMatchScouts {
    final eventIds = _periodEventIds;

    return _matchScouts.where((row) {
      final eventId = (row['event_id'] ?? '').toString();

      if (_scope == 'treinos') return false;
      if (eventId.isNotEmpty && !eventIds.contains(eventId)) return false;
      if (eventId.isNotEmpty && !_scopeMatchesEvent(eventId)) return false;

      final dateSource = row['updated_at'] ?? row['created_at'];
      return _isInsidePeriod(dateSource);
    }).toList();
  }

  int get _validCheckins {
    return _periodCheckins.where(_isValidCheckin).length;
  }

  int get _activeAthletes {
    final ids = <String>{};

    for (final row in _periodConvocations) {
      final id = (row['user_id'] ?? '').toString();
      if (id.isNotEmpty) ids.add(id);
    }

    for (final row in _periodCheckins) {
      final id = (row['user_id'] ?? '').toString();
      if (id.isNotEmpty) ids.add(id);
    }

    for (final row in _periodTrainingEvaluations) {
      final id = (row['athlete_id'] ?? '').toString();
      if (id.isNotEmpty) ids.add(id);
    }

    for (final row in _periodMatchScouts) {
      final id = (row['athlete_id'] ?? '').toString();
      if (id.isNotEmpty) ids.add(id);
    }

    return ids.isEmpty ? _athletes.length : ids.length;
  }

  int get _presencePercent {
    final convocados = _periodConvocations.length;
    if (convocados <= 0) return 0;

    return ((_validCheckins / convocados) * 100).round().clamp(0, 100);
  }

  int get _trainingScore {
    var total = 0;

    for (final row in _periodTrainingEvaluations) {
      final tipo = (row['tipo'] ?? '').toString().toLowerCase();
      final score = row['score'];

      if (score is num) {
        total += score.toInt();
      } else if (tipo == 'destaque') {
        total += 2;
      } else if (tipo == 'atencao' || tipo == 'atenção') {
        total -= 1;
      } else if (tipo == 'completa') {
        total += 1;
      }
    }

    return total;
  }

  int _positiveActionsFor(Map<String, dynamic> row) {
    return _toInt(row['saque_ponto']) +
        _toInt(row['recepcao_boa']) +
        _toInt(row['passe_bom']) +
        _toInt(row['levantamento_bom']) +
        _toInt(row['ataque_ponto']) +
        _toInt(row['largada_bola_boa']) +
        _toInt(row['bloqueio_ponto']) +
        _toInt(row['defesa_boa']);
  }

  int _errorsFor(Map<String, dynamic> row) {
    return _toInt(row['saque_erro']) +
        _toInt(row['recepcao_erro']) +
        _toInt(row['passe_erro']) +
        _toInt(row['levantamento_erro']) +
        _toInt(row['ataque_erro']) +
        _toInt(row['largada_bola_erro']) +
        _toInt(row['bloqueio_erro']) +
        _toInt(row['defesa_erro']);
  }

  int get _championshipPositiveActions {
    return _periodMatchScouts.fold<int>(
      0,
      (sum, row) => sum + _positiveActionsFor(row),
    );
  }

  int get _championshipErrors {
    return _periodMatchScouts.fold<int>(
      0,
      (sum, row) => sum + _errorsFor(row),
    );
  }

  int get _championshipEfficiency {
    final total = _championshipPositiveActions + _championshipErrors;
    if (total == 0) return 0;

    return ((_championshipPositiveActions / total) * 100).round().clamp(0, 100);
  }

  int get _engagementPercent {
    final totalSignals = _periodConvocations.length +
        _periodTrainingEvaluations.length +
        _periodMatchScouts.length;

    if (_activeAthletes <= 0) return 0;

    final base = totalSignals / math.max(1, _activeAthletes * 3);
    return (base * 100).round().clamp(0, 100);
  }

  int get _evolutionScore {
    if (_scope == 'campeonatos') {
      return ((_championshipPositiveActions / 5) - (_championshipErrors / 4))
          .round();
    }

    if (_scope == 'treinos') {
      return _trainingScore;
    }

    return (_trainingScore +
            ((_championshipPositiveActions / 5) - (_championshipErrors / 4)))
        .round();
  }

  Map<String, int> get _trainingHighlightsByFundament {
    final map = <String, int>{};

    for (final row in _periodTrainingEvaluations) {
      final tipo = (row['tipo'] ?? '').toString().toLowerCase();
      final fundamento = (row['fundamento'] ?? '').toString().trim();

      if (fundamento.isEmpty) continue;
      if (tipo == 'destaque') {
        map[fundamento] = (map[fundamento] ?? 0) + 1;
      }
    }

    return map;
  }

  Map<String, int> get _trainingAttentionByFundament {
    final map = <String, int>{};

    for (final row in _periodTrainingEvaluations) {
      final tipo = (row['tipo'] ?? '').toString().toLowerCase();
      final fundamento = (row['fundamento'] ?? '').toString().trim();

      if (fundamento.isEmpty) continue;
      if (tipo == 'atencao' || tipo == 'atenção') {
        map[fundamento] = (map[fundamento] ?? 0) + 1;
      }
    }

    return map;
  }

  Map<String, int> get _championshipPositiveByFundament {
    final map = <String, int>{
      'Saque': 0,
      'Recepção': 0,
      'Levantamento': 0,
      'Ataque': 0,
      'Bloqueio': 0,
      'Defesa': 0,
    };

    for (final row in _periodMatchScouts) {
      map['Saque'] = map['Saque']! + _toInt(row['saque_ponto']);
      map['Recepção'] = map['Recepção']! + _toInt(row['recepcao_boa']);
      map['Levantamento'] =
          map['Levantamento']! + _toInt(row['levantamento_bom']);
      map['Ataque'] = map['Ataque']! + _toInt(row['ataque_ponto']);
      map['Bloqueio'] = map['Bloqueio']! + _toInt(row['bloqueio_ponto']);
      map['Defesa'] = map['Defesa']! + _toInt(row['defesa_boa']);
    }

    map.removeWhere((_, value) => value <= 0);
    return map;
  }

  Map<String, int> get _championshipErrorsByFundament {
    final map = <String, int>{
      'Saque': 0,
      'Recepção': 0,
      'Levantamento': 0,
      'Ataque': 0,
      'Bloqueio': 0,
      'Defesa': 0,
    };

    for (final row in _periodMatchScouts) {
      map['Saque'] = map['Saque']! + _toInt(row['saque_erro']);
      map['Recepção'] = map['Recepção']! + _toInt(row['recepcao_erro']);
      map['Levantamento'] =
          map['Levantamento']! + _toInt(row['levantamento_erro']);
      map['Ataque'] = map['Ataque']! + _toInt(row['ataque_erro']);
      map['Bloqueio'] = map['Bloqueio']! + _toInt(row['bloqueio_erro']);
      map['Defesa'] = map['Defesa']! + _toInt(row['defesa_erro']);
    }

    map.removeWhere((_, value) => value <= 0);
    return map;
  }

  Map<String, int> get _athleteRiskScore {
    final map = <String, int>{};

    for (final athlete in _athletes) {
      final id = (athlete['id'] ?? '').toString();
      if (id.isNotEmpty) map[id] = 0;
    }

    final athleteCheckins = <String, int>{};
    for (final row in _periodCheckins.where(_isValidCheckin)) {
      final id = (row['user_id'] ?? '').toString();
      if (id.isEmpty) continue;
      athleteCheckins[id] = (athleteCheckins[id] ?? 0) + 1;
    }

    final athleteConvocations = <String, int>{};
    for (final row in _periodConvocations) {
      final id = (row['user_id'] ?? '').toString();
      if (id.isEmpty) continue;
      athleteConvocations[id] = (athleteConvocations[id] ?? 0) + 1;
    }

    final athleteAttention = <String, int>{};
    for (final row in _periodTrainingEvaluations) {
      final tipo = (row['tipo'] ?? '').toString().toLowerCase();
      final id = (row['athlete_id'] ?? '').toString();
      if (id.isEmpty) continue;

      if (tipo == 'atencao' || tipo == 'atenção') {
        athleteAttention[id] = (athleteAttention[id] ?? 0) + 1;
      }
    }

    final athleteErrors = <String, int>{};
    for (final row in _periodMatchScouts) {
      final id = (row['athlete_id'] ?? '').toString();
      if (id.isEmpty) continue;
      athleteErrors[id] = (athleteErrors[id] ?? 0) + _errorsFor(row);
    }

    for (final id in map.keys.toList()) {
      final convocado = athleteConvocations[id] ?? 0;
      final presente = athleteCheckins[id] ?? 0;
      final atencoes = athleteAttention[id] ?? 0;
      final erros = athleteErrors[id] ?? 0;

      var risk = 0;

      if (convocado > 0 && presente == 0) risk += 3;
      if (convocado >= 2 && presente / math.max(1, convocado) < 0.5) risk += 2;
      risk += atencoes;
      risk += (erros / 3).floor();

      map[id] = risk;
    }

    map.removeWhere((_, value) => value <= 0);
    return map;
  }

  String _athleteName(String athleteId) {
    for (final athlete in _athletes) {
      if ((athlete['id'] ?? '').toString() == athleteId) {
        return (athlete['full_name'] ?? 'Atleta').toString();
      }
    }

    return 'Atleta';
  }

  String _leaderName() {
    final scores = <String, int>{};

    for (final row in _periodTrainingEvaluations) {
      final id = (row['athlete_id'] ?? '').toString();
      if (id.isEmpty) continue;

      final tipo = (row['tipo'] ?? '').toString().toLowerCase();
      final score = row['score'];

      var value = 0;
      if (score is num) {
        value = score.toInt();
      } else if (tipo == 'destaque') {
        value = 2;
      } else if (tipo == 'atencao' || tipo == 'atenção') {
        value = -1;
      }

      scores[id] = (scores[id] ?? 0) + value;
    }

    for (final row in _periodMatchScouts) {
      final id = (row['athlete_id'] ?? '').toString();
      if (id.isEmpty) continue;

      scores[id] =
          (scores[id] ?? 0) + _positiveActionsFor(row) - _errorsFor(row);
    }

    if (scores.isEmpty) return '';

    final ordered = scores.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    if (ordered.first.value <= 0) return '';

    return _athleteName(ordered.first.key);
  }

  List<_SmartDashboardInsight> get _insights {
    final items = <_SmartDashboardInsight>[];

    if (_scope != 'campeonatos' && _trainingAttentionByFundament.isNotEmpty) {
      final attention = _trainingAttentionByFundament.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));

      items.add(
        _SmartDashboardInsight(
          icon: Icons.warning_amber_rounded,
          title: '${attention.first.key} exige atenção',
          body:
              '${attention.first.value} ponto(s) de atenção foram registrados nos treinos.',
          color: olympusWarning,
        ),
      );
    }

    if (_scope != 'treinos' && _championshipErrorsByFundament.isNotEmpty) {
      final errors = _championshipErrorsByFundament.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));

      items.add(
        _SmartDashboardInsight(
          icon: Icons.sports_volleyball_rounded,
          title: '${errors.first.key} preocupa nos campeonatos',
          body:
              '${errors.first.value} erro(s) registrados nesse fundamento nos jogos avaliados.',
          color: olympusDanger,
        ),
      );
    }

    final risk = _athleteRiskScore.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    if (risk.isNotEmpty) {
      items.add(
        _SmartDashboardInsight(
          icon: Icons.health_and_safety_outlined,
          title: '${risk.length} atleta(s) em risco',
          body:
              'Há atletas com baixa presença, atenção recorrente ou erros concentrados.',
          color: olympusDanger,
        ),
      );
    }

    if (_scope != 'treinos' && _championshipPositiveByFundament.isNotEmpty) {
      final positives = _championshipPositiveByFundament.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));

      items.add(
        _SmartDashboardInsight(
          icon: Icons.trending_up_rounded,
          title: '${positives.first.key} é força nos jogos',
          body:
              '${positives.first.value} ação(ões) positiva(s) nesse fundamento.',
          color: olympusSuccess,
        ),
      );
    }

    final leader = _leaderName();
    if (leader.isNotEmpty) {
      items.add(
        _SmartDashboardInsight(
          icon: Icons.emoji_events_outlined,
          title: '$leader lidera o período',
          body: 'Maior combinação de score, presença e desempenho no painel.',
          color: olympusSuccess,
        ),
      );
    }

    if (_presencePercent < 50 && _periodConvocations.isNotEmpty) {
      items.add(
        _SmartDashboardInsight(
          icon: Icons.event_busy_outlined,
          title: 'Presença abaixo do ideal',
          body:
              'A presença média está em $_presencePercent%. Revise convocações e disponibilidade.',
          color: olympusWarning,
        ),
      );
    }

    if (items.isEmpty) {
      items.add(
        const _SmartDashboardInsight(
          icon: Icons.check_circle_outline_rounded,
          title: 'Sem alertas críticos',
          body: 'Os dados do período não indicam riscos relevantes.',
          color: olympusSuccess,
        ),
      );
    }

    return items.take(6).toList();
  }

  Widget _background() {
    return Stack(
      children: [
        Positioned.fill(
          child: Image.asset(
            'assets/images/monte_olimpo_v2.png',
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) {
              return Container(color: const Color(0xFF102845));
            },
          ),
        ),
        Positioned.fill(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 2.2, sigmaY: 2.2),
            child: Container(color: Colors.transparent),
          ),
        ),
        Positioned.fill(
          child: Container(
            color: Colors.black.withOpacity(0.30),
          ),
        ),
        Positioned.fill(
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  olympusBlue.withOpacity(0.80),
                  olympusLightBlue.withOpacity(0.38),
                  Colors.black.withOpacity(0.68),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _glassCard({
    required List<Widget> children,
    EdgeInsetsGeometry? padding,
    EdgeInsetsGeometry? margin,
  }) {
    return Container(
      width: double.infinity,
      margin: margin ?? const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: Container(
            padding: padding ?? const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.94),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white.withOpacity(0.48)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.13),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: children,
            ),
          ),
        ),
      ),
    );
  }

  Widget _choiceButton({
    required String label,
    required bool selected,
    required VoidCallback onTap,
    IconData? icon,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: 15,
                color: selected ? olympusBlue : Colors.white,
              ),
              const SizedBox(width: 5),
            ],
            Text(label),
          ],
        ),
        selected: selected,
        showCheckmark: false,
        selectedColor: olympusGold,
        backgroundColor: Colors.white.withOpacity(0.22),
        side: BorderSide(
          color: selected ? olympusGold : Colors.white.withOpacity(0.22),
        ),
        labelStyle: TextStyle(
          color: selected ? olympusBlue : Colors.white,
          fontWeight: FontWeight.w900,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(999),
        ),
        onSelected: (_) => onTap(),
      ),
    );
  }

  Widget _scopeSelector() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _choiceButton(
            label: 'Geral',
            icon: Icons.dashboard_rounded,
            selected: _scope == 'geral',
            onTap: () => setState(() => _scope = 'geral'),
          ),
          _choiceButton(
            label: 'Treinos',
            icon: Icons.fitness_center_rounded,
            selected: _scope == 'treinos',
            onTap: () => setState(() => _scope = 'treinos'),
          ),
          _choiceButton(
            label: 'Campeonatos',
            icon: Icons.emoji_events_rounded,
            selected: _scope == 'campeonatos',
            onTap: () => setState(() => _scope = 'campeonatos'),
          ),
        ],
      ),
    );
  }

  Widget _periodSelector() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _choiceButton(
            label: 'Semana',
            selected: _period == 'semana',
            onTap: () => setState(() => _period = 'semana'),
          ),
          _choiceButton(
            label: 'Mês',
            selected: _period == 'mes',
            onTap: () => setState(() => _period = 'mes'),
          ),
          _choiceButton(
            label: 'Geral',
            selected: _period == 'geral',
            onTap: () => setState(() => _period = 'geral'),
          ),
        ],
      ),
    );
  }

  Widget _header() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: const LinearGradient(
          colors: [
            Color(0xFF0D223B),
            Color(0xFF123861),
            Color(0xFF235E94),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: Colors.white.withOpacity(0.18), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: olympusGold.withOpacity(0.18),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
          BoxShadow(
            color: Colors.black.withOpacity(0.24),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            top: -40,
            right: -30,
            child: Container(
              width: 132,
              height: 132,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.07),
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.auto_graph_rounded,
                    color: olympusGold,
                    size: 30,
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Smart Dashboard',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 23,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Atualizar',
                    onPressed: _loadDashboard,
                    icon: const Icon(Icons.refresh_rounded),
                    color: Colors.white,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Insights inteligentes • $_scopeLabel • $_periodLabel',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.82),
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 14),
              _scopeSelector(),
              const SizedBox(height: 10),
              _periodSelector(),
            ],
          ),
        ],
      ),
    );
  }

  Widget _metricCard({
    required IconData icon,
    required String value,
    required String title,
    required String subtitle,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.94),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withOpacity(0.52)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.13),
            blurRadius: 16,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            right: -24,
            bottom: -24,
            child: Container(
              width: 92,
              height: 92,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color.withOpacity(0.07),
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: color, size: 21),
              ),
              const SizedBox(height: 15),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: olympusBlue,
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: olympusText,
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: olympusMuted,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  height: 1.22,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _metricsGrid() {
    final trainingMode = _scope == 'treinos';
    final championshipMode = _scope == 'campeonatos';

    final cards = <Widget>[
      _metricCard(
        icon: Icons.groups_rounded,
        value: '$_activeAthletes',
        title: 'Atletas ativos',
        subtitle: 'Com atividade no período',
        color: const Color(0xFF2563EB),
      ),
      _metricCard(
        icon: Icons.fact_check_rounded,
        value: '$_presencePercent%',
        title: 'Presença média',
        subtitle: 'Check-ins / convocações',
        color: olympusSuccess,
      ),
      _metricCard(
        icon: trainingMode
            ? Icons.bolt_rounded
            : championshipMode
                ? Icons.sports_volleyball_rounded
                : Icons.auto_graph_rounded,
        value: championshipMode
            ? '$_championshipEfficiency%'
            : '$_engagementPercent%',
        title: championshipMode ? 'Eficiência de jogo' : 'Engajamento',
        subtitle: championshipMode
            ? 'Ações positivas / total'
            : 'Participação e avaliações',
        color: olympusWarning,
      ),
      _metricCard(
        icon: Icons.trending_up_rounded,
        value: _evolutionScore >= 0 ? '+$_evolutionScore' : '$_evolutionScore',
        title: 'Evolução',
        subtitle: _evolutionScore >= 0 ? 'Melhorando' : 'Exige atenção',
        color: _evolutionScore >= 0 ? olympusSuccess : olympusDanger,
      ),
    ];

    if (!trainingMode) {
      cards.add(
        _metricCard(
          icon: Icons.add_task_rounded,
          value: '$_championshipPositiveActions',
          title: 'Ações em jogos',
          subtitle: 'Scout de campeonatos',
          color: olympusPurple,
        ),
      );
      cards.add(
        _metricCard(
          icon: Icons.error_outline_rounded,
          value: '$_championshipErrors',
          title: 'Erros em jogos',
          subtitle: 'Fundamentos com falha',
          color: olympusDanger,
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final crossAxisCount = constraints.maxWidth >= 720 ? 3 : 2;
          final ratio = constraints.maxWidth < 390 ? 0.82 : 0.92;

          return GridView.count(
            crossAxisCount: crossAxisCount,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: ratio,
            children: cards,
          );
        },
      ),
    );
  }

  Widget _sectionTitle(String text, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: olympusGold, size: 24),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              color: olympusBlue,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ],
    );
  }

  Widget _insightsSection() {
    return _glassCard(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      children: [
        _sectionTitle('Insights inteligentes', Icons.lightbulb_outline_rounded),
        const SizedBox(height: 13),
        ..._insights.map((insight) {
          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              color: insight.color.withOpacity(0.09),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: insight.color.withOpacity(0.20)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(insight.icon, color: insight.color, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        insight.title,
                        style: TextStyle(
                          color: insight.color,
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        insight.body,
                        style: const TextStyle(
                          color: olympusMuted,
                          fontSize: 12.2,
                          fontWeight: FontWeight.w700,
                          height: 1.32,
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
    );
  }

  Widget _foundationLine({
    required String title,
    required int value,
    required String label,
    required Color color,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 9),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.07),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.16)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                color: olympusBlue,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          Text(
            '$value $label',
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _championshipBreakdownSection() {
    if (_scope == 'treinos') return const SizedBox.shrink();

    final positives = _championshipPositiveByFundament.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final errors = _championshipErrorsByFundament.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return _glassCard(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      children: [
        _sectionTitle(
          'Campeonatos por fundamento',
          Icons.emoji_events_rounded,
        ),
        const SizedBox(height: 12),
        if (positives.isEmpty && errors.isEmpty)
          const Text(
            'Sem scout de campeonato no período selecionado.',
            style: TextStyle(
              color: olympusMuted,
              fontWeight: FontWeight.w700,
            ),
          )
        else ...[
          ...positives.take(5).map(
                (entry) => _foundationLine(
                  title: entry.key,
                  value: entry.value,
                  label: 'ações',
                  color: olympusSuccess,
                ),
              ),
          ...errors.take(5).map(
                (entry) => _foundationLine(
                  title: entry.key,
                  value: entry.value,
                  label: 'erros',
                  color: olympusDanger,
                ),
              ),
        ],
      ],
    );
  }

  Widget _trainingBreakdownSection() {
    if (_scope == 'campeonatos') return const SizedBox.shrink();

    final positive = _trainingHighlightsByFundament.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final attention = _trainingAttentionByFundament.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return _glassCard(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      children: [
        _sectionTitle('Treinos por fundamento', Icons.fitness_center_rounded),
        const SizedBox(height: 12),
        if (positive.isEmpty && attention.isEmpty)
          const Text(
            'Sem avaliações de treino no período selecionado.',
            style: TextStyle(
              color: olympusMuted,
              fontWeight: FontWeight.w700,
            ),
          )
        else ...[
          ...positive.take(5).map(
                (entry) => _foundationLine(
                  title: entry.key,
                  value: entry.value,
                  label: 'destaques',
                  color: olympusSuccess,
                ),
              ),
          ...attention.take(5).map(
                (entry) => _foundationLine(
                  title: entry.key,
                  value: entry.value,
                  label: 'atenções',
                  color: olympusWarning,
                ),
              ),
        ],
      ],
    );
  }

  Widget _riskSection() {
    final risk = _athleteRiskScore.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return _glassCard(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 28),
      children: [
        _sectionTitle('Radar de atletas', Icons.health_and_safety_outlined),
        const SizedBox(height: 12),
        if (risk.isEmpty)
          const Text(
            'Nenhuma atleta em risco relevante no período.',
            style: TextStyle(
              color: olympusMuted,
              fontWeight: FontWeight.w700,
            ),
          )
        else
          ...risk.take(6).map((entry) {
            final name = _athleteName(entry.key);
            final high = entry.value >= 4;

            return Container(
              margin: const EdgeInsets.only(bottom: 9),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color:
                    (high ? olympusDanger : olympusWarning).withOpacity(0.08),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color:
                      (high ? olympusDanger : olympusWarning).withOpacity(0.18),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    high
                        ? Icons.priority_high_rounded
                        : Icons.info_outline_rounded,
                    color: high ? olympusDanger : olympusWarning,
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      name,
                      style: const TextStyle(
                        color: olympusBlue,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  Text(
                    'risco ${entry.value}',
                    style: TextStyle(
                      color: high ? olympusDanger : olympusWarning,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            );
          }),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: olympusBg,
      appBar: AppBar(
        title: const Text('Smart Dashboard'),
        backgroundColor: olympusBlue,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Atualizar',
            onPressed: _loadDashboard,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: Stack(
        children: [
          Positioned.fill(child: _background()),
          if (_loading)
            const Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            )
          else if (_error != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(22),
                child: Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            )
          else
            RefreshIndicator(
              onRefresh: _loadDashboard,
              child: ListView(
                padding: const EdgeInsets.only(bottom: 8),
                children: [
                  _header(),
                  _metricsGrid(),
                  _insightsSection(),
                  _championshipBreakdownSection(),
                  _trainingBreakdownSection(),
                  _riskSection(),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _SmartDashboardInsight {
  const _SmartDashboardInsight({
    required this.icon,
    required this.title,
    required this.body,
    required this.color,
  });

  final IconData icon;
  final String title;
  final String body;
  final Color color;
}

class CoachTrainingPlanningDashboardPage extends StatefulWidget {
  const CoachTrainingPlanningDashboardPage({super.key});

  @override
  State<CoachTrainingPlanningDashboardPage> createState() =>
      _CoachTrainingPlanningDashboardPageState();
}

class _CoachTrainingPlanningDashboardPageState
    extends State<CoachTrainingPlanningDashboardPage> {
  final SupabaseClient _supabase = Supabase.instance.client;

  static const Color olympusBlue = Color(0xFF1E3A5F);
  static const Color olympusGold = Color(0xFFD4AF37);
  static const Color olympusLightBlue = Color(0xFF2C5F8D);
  static const Color olympusBg = Color(0xFFF4F7FB);
  static const Color olympusMuted = Color(0xFF53657B);
  static const Color olympusBorder = Color(0xFFE4EDF5);
  static const Color olympusSuccess = Color(0xFF16A34A);
  static const Color olympusWarning = Color(0xFFF59E0B);
  static const Color olympusDanger = Color(0xFFDC2626);
  static const Color olympusPurple = Color(0xFF7C3AED);

  bool _loading = true;
  String? _error;

  List<_TrainingSummaryItem> _allRows = [];
  DateTime _selectedMonth = DateTime(DateTime.now().year, DateTime.now().month);

  @override
  void initState() {
    super.initState();
    _loadDashboard();
  }

  Future<void> _loadDashboard() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final user = _supabase.auth.currentUser;
      if (user == null) {
        throw Exception('Usuário não autenticado.');
      }

      final response = await _supabase
          .from('monthly_training_plan_summary')
          .select(
            'coach_id, month, category, type, total_minutes, total_hours, total_blocks',
          )
          .eq('coach_id', user.id)
          .order('month', ascending: false)
          .order('category', ascending: true);

      final rows = List<Map<String, dynamic>>.from(response as List);

      final parsedRows = rows.map(_TrainingSummaryItem.fromMap).toList();

      if (parsedRows.isNotEmpty) {
        final months = parsedRows.map((e) => e.month).toList()
          ..sort((a, b) => b.compareTo(a));

        final currentMonth =
            DateTime(DateTime.now().year, DateTime.now().month);
        final hasCurrent = months.any((m) => _sameMonth(m, currentMonth));

        _selectedMonth = hasCurrent ? currentMonth : months.first;
      }

      if (!mounted) return;
      setState(() {
        _allRows = parsedRows;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Erro ao carregar dashboard de planejamento: $e';
        _loading = false;
      });
    }
  }

  bool _sameMonth(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month;
  }

  List<_TrainingSummaryItem> get _selectedRows {
    return _allRows
        .where((row) => _sameMonth(row.month, _selectedMonth))
        .toList();
  }

  List<DateTime> get _availableMonths {
    final months = <String, DateTime>{};

    for (final row in _allRows) {
      final key =
          '${row.month.year}-${row.month.month.toString().padLeft(2, '0')}';
      months[key] = row.month;
    }

    final list = months.values.toList()..sort((a, b) => b.compareTo(a));
    if (list.isEmpty) {
      return [DateTime(DateTime.now().year, DateTime.now().month)];
    }

    return list;
  }

  int get _totalMinutes {
    return _selectedRows.fold<int>(0, (sum, item) => sum + item.totalMinutes);
  }

  int get _totalBlocks {
    return _selectedRows.fold<int>(0, (sum, item) => sum + item.totalBlocks);
  }

  Map<String, int> get _minutesByCategory {
    final map = <String, int>{
      'Fundamentos': 0,
      'Tático': 0,
      'Físico': 0,
    };

    for (final row in _selectedRows) {
      map[row.category] = (map[row.category] ?? 0) + row.totalMinutes;
    }

    return map;
  }

  Map<String, List<_TrainingSummaryItem>> get _rowsByCategory {
    final map = <String, List<_TrainingSummaryItem>>{
      'Fundamentos': [],
      'Tático': [],
      'Físico': [],
    };

    for (final row in _selectedRows) {
      map.putIfAbsent(row.category, () => []);
      map[row.category]!.add(row);
    }

    for (final entry in map.entries) {
      entry.value.sort((a, b) {
        final timeCompare = b.totalMinutes.compareTo(a.totalMinutes);
        if (timeCompare != 0) return timeCompare;
        return a.type.compareTo(b.type);
      });
    }

    return map;
  }

  List<_TrainingSummaryItem> get _ranking {
    final list = _selectedRows.toList()
      ..sort((a, b) {
        final timeCompare = b.totalMinutes.compareTo(a.totalMinutes);
        if (timeCompare != 0) return timeCompare;
        return a.type.compareTo(b.type);
      });

    return list;
  }

  String _monthLabel(DateTime month) {
    const labels = [
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

    return '${labels[month.month]}/${month.year}';
  }

  String _shortMonthLabel(DateTime month) {
    const labels = [
      '',
      'Jan',
      'Fev',
      'Mar',
      'Abr',
      'Mai',
      'Jun',
      'Jul',
      'Ago',
      'Set',
      'Out',
      'Nov',
      'Dez',
    ];

    return '${labels[month.month]}/${month.year}';
  }

  String _formatMinutes(int minutes) {
    final hours = minutes ~/ 60;
    final mins = minutes % 60;

    if (hours <= 0) return '${mins}min';
    if (mins == 0) return '${hours}h';
    return '${hours}h ${mins}min';
  }

  Color _categoryColor(String category) {
    switch (category) {
      case 'Fundamentos':
        return olympusSuccess;
      case 'Tático':
        return olympusPurple;
      case 'Físico':
        return olympusWarning;
      default:
        return olympusBlue;
    }
  }

  IconData _categoryIcon(String category) {
    switch (category) {
      case 'Fundamentos':
        return Icons.sports_volleyball_rounded;
      case 'Tático':
        return Icons.account_tree_rounded;
      case 'Físico':
        return Icons.fitness_center_rounded;
      default:
        return Icons.insights_rounded;
    }
  }

  List<String> get _insights {
    if (_selectedRows.isEmpty) {
      return [
        'Ainda não há blocos planejados neste mês.',
        'Abra um treino, crie blocos e salve categoria, tipo e horários para gerar esta visão.',
      ];
    }

    final categoryMinutes = _minutesByCategory;
    final total = math.max(1, _totalMinutes);
    final ranking = _ranking;

    final top = ranking.isEmpty ? null : ranking.first;

    final fundamentos = categoryMinutes['Fundamentos'] ?? 0;
    final tatico = categoryMinutes['Tático'] ?? 0;
    final fisico = categoryMinutes['Físico'] ?? 0;

    final items = <String>[];

    if (top != null) {
      items.add(
        '${top.type} foi o foco principal do mês com ${_formatMinutes(top.totalMinutes)} planejados.',
      );
    }

    final fundamentosPct = (fundamentos / total * 100).round();
    final taticoPct = (tatico / total * 100).round();
    final fisicoPct = (fisico / total * 100).round();

    if (fundamentosPct >= 55) {
      items.add(
          'O mês está muito concentrado em fundamentos ($fundamentosPct%).');
    } else if (fundamentosPct <= 20 && fundamentos > 0) {
      items.add(
          'Fundamentos estão com baixo volume relativo ($fundamentosPct%).');
    }

    if (taticoPct <= 15 && _totalMinutes >= 120) {
      items.add(
          'Volume tático baixo ($taticoPct%). Considere incluir leitura de jogo, transição ou sistema.');
    }

    if (fisicoPct <= 10 && _totalMinutes >= 120) {
      items.add(
          'Volume físico baixo ($fisicoPct%). Pode valer inserir mobilidade, força ou prevenção.');
    }

    if (items.length < 4) {
      items.add(
        'Distribuição atual: Fundamentos $fundamentosPct%, Tático $taticoPct%, Físico $fisicoPct%.',
      );
    }

    return items.take(5).toList();
  }

  Widget _background() {
    return Stack(
      children: [
        Positioned.fill(
          child: Image.asset(
            'assets/images/monte_olimpo_v2.png',
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) {
              return Container(color: const Color(0xFF102845));
            },
          ),
        ),
        Positioned.fill(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 2.5, sigmaY: 2.5),
            child: Container(color: Colors.transparent),
          ),
        ),
        Positioned.fill(
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  const Color(0xFF102845).withOpacity(0.78),
                  olympusBlue.withOpacity(0.46),
                  Colors.black.withOpacity(0.74),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _header() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: const LinearGradient(
          colors: [
            Color(0xFF071A30),
            Color(0xFF123861),
            Color(0xFF2C5F8D),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: olympusGold.withOpacity(0.72), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: olympusGold.withOpacity(0.20),
            blurRadius: 24,
            spreadRadius: 1,
            offset: const Offset(0, 10),
          ),
          BoxShadow(
            color: Colors.black.withOpacity(0.24),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            top: -36,
            right: -26,
            child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.06),
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 54,
                    height: 54,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      gradient: const LinearGradient(
                        colors: [
                          Color(0xFFF8E08E),
                          Color(0xFFD4AF37),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: olympusGold.withOpacity(0.34),
                          blurRadius: 14,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.analytics_rounded,
                      color: olympusBlue,
                      size: 30,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Dashboard do Treinador',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Atualizar',
                    onPressed: _loadDashboard,
                    icon: const Icon(Icons.refresh_rounded),
                    color: Colors.white,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                'Planejamento mensal por Fundamentos, Tático e Físico',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.78),
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 14),
              _monthSelector(),
            ],
          ),
        ],
      ),
    );
  }

  Widget _monthSelector() {
    final months = _availableMonths;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: months.map((month) {
          final selected = _sameMonth(month, _selectedMonth);

          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(_shortMonthLabel(month)),
              selected: selected,
              onSelected: (_) {
                setState(() {
                  _selectedMonth = month;
                });
              },
              showCheckmark: false,
              selectedColor: olympusGold,
              backgroundColor: Colors.white.withOpacity(0.12),
              side: BorderSide(
                color: selected ? olympusGold : Colors.white.withOpacity(0.20),
              ),
              labelStyle: TextStyle(
                color: selected ? olympusBlue : Colors.white,
                fontWeight: FontWeight.w900,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _glassCard({
    required List<Widget> children,
    EdgeInsetsGeometry? padding,
    EdgeInsetsGeometry? margin,
  }) {
    return Container(
      width: double.infinity,
      margin: margin ?? const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: Container(
            padding: padding ?? const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.94),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white.withOpacity(0.50)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.13),
                  blurRadius: 16,
                  offset: const Offset(0, 7),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: children,
            ),
          ),
        ),
      ),
    );
  }

  Widget _overviewCard() {
    final categoryMinutes = _minutesByCategory;
    final total = math.max(1, _totalMinutes);

    return _glassCard(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      children: [
        Row(
          children: [
            const Icon(Icons.timer_rounded, color: olympusGold, size: 26),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _monthLabel(_selectedMonth),
                style: const TextStyle(
                  color: olympusBlue,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            Text(
              _formatMinutes(_totalMinutes),
              style: const TextStyle(
                color: olympusBlue,
                fontSize: 22,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
        const SizedBox(height: 5),
        Text(
          '$_totalBlocks bloco(s) planejado(s) no mês',
          style: const TextStyle(
            color: olympusMuted,
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 172,
          child: _totalMinutes == 0
              ? const Center(
                  child: Text(
                    'Sem tempo planejado neste mês.',
                    style: TextStyle(
                      color: olympusMuted,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                )
              : CustomPaint(
                  painter: _CategoryDistributionPainter(
                    data: categoryMinutes,
                    colors: {
                      'Fundamentos': olympusSuccess,
                      'Tático': olympusPurple,
                      'Físico': olympusWarning,
                    },
                    labelColor: olympusMuted,
                    total: total,
                  ),
                  child: const SizedBox.expand(),
                ),
        ),
        const SizedBox(height: 12),
        _categoryProgressRow(
          category: 'Fundamentos',
          minutes: categoryMinutes['Fundamentos'] ?? 0,
          total: total,
        ),
        const SizedBox(height: 9),
        _categoryProgressRow(
          category: 'Tático',
          minutes: categoryMinutes['Tático'] ?? 0,
          total: total,
        ),
        const SizedBox(height: 9),
        _categoryProgressRow(
          category: 'Físico',
          minutes: categoryMinutes['Físico'] ?? 0,
          total: total,
        ),
      ],
    );
  }

  Widget _categoryProgressRow({
    required String category,
    required int minutes,
    required int total,
  }) {
    final color = _categoryColor(category);
    final percent = total == 0 ? 0.0 : minutes / total;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(_categoryIcon(category), color: color, size: 18),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                category,
                style: const TextStyle(
                  color: olympusBlue,
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            Text(
              '${_formatMinutes(minutes)} • ${(percent * 100).round()}%',
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: percent.clamp(0, 1),
            minHeight: 9,
            backgroundColor: olympusBorder,
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
      ],
    );
  }

  Widget _categoryCards() {
    final grouped = _rowsByCategory;
    final categories = ['Fundamentos', 'Tático', 'Físico'];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isNarrow = constraints.maxWidth < 680;

          if (isNarrow) {
            return Column(
              children: categories.map((category) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _categoryCard(
                    category: category,
                    rows: grouped[category] ?? [],
                  ),
                );
              }).toList(),
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: categories.map((category) {
              final isLast = category == categories.last;
              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(right: isLast ? 0 : 10),
                  child: _categoryCard(
                    category: category,
                    rows: grouped[category] ?? [],
                  ),
                ),
              );
            }).toList(),
          );
        },
      ),
    );
  }

  Widget _categoryCard({
    required String category,
    required List<_TrainingSummaryItem> rows,
  }) {
    final color = _categoryColor(category);
    final total = rows.fold<int>(0, (sum, row) => sum + row.totalMinutes);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.95),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: color.withOpacity(0.22)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.10),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Icon(_categoryIcon(category), color: color, size: 22),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  category,
                  style: const TextStyle(
                    color: olympusBlue,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Text(
                _formatMinutes(total),
                style: TextStyle(
                  color: color,
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (rows.isEmpty)
            const Text(
              'Sem blocos neste mês.',
              style: TextStyle(
                color: olympusMuted,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            )
          else
            ...rows.take(5).map((row) {
              final max = math.max(1, rows.first.totalMinutes);
              final percent = row.totalMinutes / max;

              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            row.type,
                            style: const TextStyle(
                              color: olympusBlue,
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        Text(
                          _formatMinutes(row.totalMinutes),
                          style: TextStyle(
                            color: color,
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        value: percent.clamp(0, 1),
                        minHeight: 7,
                        backgroundColor: olympusBorder,
                        valueColor: AlwaysStoppedAnimation<Color>(color),
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

  Widget _rankingSection() {
    final ranking = _ranking.take(10).toList();

    return _glassCard(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      children: [
        Row(
          children: [
            const Icon(Icons.leaderboard_rounded, color: olympusGold, size: 24),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'Ranking de foco do mês',
                style: TextStyle(
                  color: olympusBlue,
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (ranking.isEmpty)
          const Text(
            'Sem dados para montar ranking.',
            style: TextStyle(
              color: olympusMuted,
              fontWeight: FontWeight.w700,
            ),
          )
        else
          ...ranking.asMap().entries.map((entry) {
            final index = entry.key;
            final row = entry.value;
            final color = _categoryColor(row.category);

            return Container(
              margin: const EdgeInsets.only(bottom: 9),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withOpacity(0.08),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: color.withOpacity(0.16)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.16),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${index + 1}',
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          row.type,
                          style: const TextStyle(
                            color: olympusBlue,
                            fontSize: 13,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${row.category} • ${row.totalBlocks} bloco(s)',
                          style: const TextStyle(
                            color: olympusMuted,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    _formatMinutes(row.totalMinutes),
                    style: TextStyle(
                      color: color,
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            );
          }),
      ],
    );
  }

  Widget _insightsSection() {
    return _glassCard(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 28),
      children: [
        Row(
          children: [
            const Icon(Icons.lightbulb_outline_rounded,
                color: olympusGold, size: 24),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'Insights do planejamento',
                style: TextStyle(
                  color: olympusBlue,
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ..._insights.map((text) {
          return Container(
            margin: const EdgeInsets.only(bottom: 9),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: olympusBlue.withOpacity(0.06),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: olympusBlue.withOpacity(0.10)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.bolt_rounded, color: olympusGold, size: 21),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    text,
                    style: const TextStyle(
                      color: olympusMuted,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      height: 1.32,
                    ),
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  void _openTrainingPlanner() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const CoachTrainingSessionsPage(
          initialTipoEvento: 'treino',
          lockTipoEvento: true,
        ),
      ),
    );
  }

  Widget _trainingPlannerAccessCard() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _openTrainingPlanner,
          borderRadius: BorderRadius.circular(22),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.96),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: olympusBorder),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.12),
                  blurRadius: 16,
                  offset: const Offset(0, 7),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: olympusBlue.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(
                    Icons.calendar_month_outlined,
                    color: olympusBlue,
                    size: 26,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Planejamento de Treinos',
                        style: TextStyle(
                          color: olympusBlue,
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Planejamento e avaliação rápida dos treinos marcados',
                        style: TextStyle(
                          color: olympusMuted,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.arrow_forward_ios_rounded,
                    color: olympusBlue, size: 18),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Container(
        margin: const EdgeInsets.all(20),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.96),
          borderRadius: BorderRadius.circular(22),
        ),
        child: const Text(
          'Ainda não há planejamento salvo no Supabase.\n\nAbra um treino, crie os blocos e salve categoria, tipo e horários.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: olympusBlue,
            fontSize: 14,
            fontWeight: FontWeight.w800,
            height: 1.35,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasAnyData = _allRows.isNotEmpty;

    return Scaffold(
      backgroundColor: olympusBg,
      appBar: AppBar(
        title: const Text('Dashboard do Treinador'),
        backgroundColor: olympusBlue,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Atualizar',
            onPressed: _loadDashboard,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: Stack(
        children: [
          Positioned.fill(child: _background()),
          if (_loading)
            const Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            )
          else if (_error != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(22),
                child: Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            )
          else if (!hasAnyData)
            RefreshIndicator(
              onRefresh: _loadDashboard,
              child: ListView(
                children: [
                  const SizedBox(height: 16),
                  _trainingPlannerAccessCard(),
                  SizedBox(height: MediaQuery.of(context).size.height * 0.18),
                  _emptyState(),
                ],
              ),
            )
          else
            RefreshIndicator(
              onRefresh: _loadDashboard,
              child: ListView(
                padding: const EdgeInsets.only(bottom: 8),
                children: [
                  _header(),
                  _trainingPlannerAccessCard(),
                  _overviewCard(),
                  _categoryCards(),
                  _rankingSection(),
                  _insightsSection(),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _TrainingSummaryItem {
  const _TrainingSummaryItem({
    required this.coachId,
    required this.month,
    required this.category,
    required this.type,
    required this.totalMinutes,
    required this.totalHours,
    required this.totalBlocks,
  });

  final String coachId;
  final DateTime month;
  final String category;
  final String type;
  final int totalMinutes;
  final double totalHours;
  final int totalBlocks;

  factory _TrainingSummaryItem.fromMap(Map<String, dynamic> map) {
    final monthRaw = (map['month'] ?? '').toString();
    final parsedMonth = DateTime.tryParse(monthRaw) ?? DateTime.now();

    return _TrainingSummaryItem(
      coachId: (map['coach_id'] ?? '').toString(),
      month: DateTime(parsedMonth.year, parsedMonth.month),
      category: (map['category'] ?? 'Sem categoria').toString(),
      type: (map['type'] ?? 'Sem tipo').toString(),
      totalMinutes: _toInt(map['total_minutes']),
      totalHours: _toDouble(map['total_hours']),
      totalBlocks: _toInt(map['total_blocks']),
    );
  }

  static int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse((value ?? '0').toString()) ?? 0;
  }

  static double _toDouble(dynamic value) {
    if (value is double) return value;
    if (value is num) return value.toDouble();
    return double.tryParse((value ?? '0').toString()) ?? 0;
  }
}

class _CategoryDistributionPainter extends CustomPainter {
  _CategoryDistributionPainter({
    required this.data,
    required this.colors,
    required this.labelColor,
    required this.total,
  });

  final Map<String, int> data;
  final Map<String, Color> colors;
  final Color labelColor;
  final int total;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width * 0.30, size.height / 2);
    final radius = math.min(size.height * 0.38, size.width * 0.22);

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 18
      ..strokeCap = StrokeCap.round;

    double startAngle = -math.pi / 2;
    final categories = ['Fundamentos', 'Tático', 'Físico'];

    for (final category in categories) {
      final value = data[category] ?? 0;
      if (value <= 0) continue;

      final sweep = (value / math.max(1, total)) * math.pi * 2;
      paint.color = (colors[category] ?? Colors.blue);

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweep,
        false,
        paint,
      );

      startAngle += sweep;
    }

    final innerPaint = Paint()..color = Colors.white.withOpacity(0.92);
    canvas.drawCircle(center, radius - 18, innerPaint);

    final totalPainter = TextPainter(
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
      text: const TextSpan(
        text: 'Total',
        style: TextStyle(
          color: Color(0xFF53657B),
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    )..layout();

    totalPainter.paint(
      canvas,
      Offset(center.dx - totalPainter.width / 2, center.dy - 20),
    );

    final minutesText = '${total}min';
    final minutesPainter = TextPainter(
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
      text: TextSpan(
        text: minutesText,
        style: const TextStyle(
          color: Color(0xFF1E3A5F),
          fontSize: 16,
          fontWeight: FontWeight.w900,
        ),
      ),
    )..layout(maxWidth: radius * 1.6);

    minutesPainter.paint(
      canvas,
      Offset(center.dx - minutesPainter.width / 2, center.dy - 2),
    );

    final legendX = size.width * 0.58;
    double legendY = size.height * 0.24;

    for (final category in categories) {
      final value = data[category] ?? 0;
      final percent = total == 0 ? 0 : (value / total * 100).round();
      final color = colors[category] ?? Colors.blue;

      canvas.drawCircle(
        Offset(legendX, legendY + 6),
        5,
        Paint()..color = color,
      );

      final legendPainter = TextPainter(
        textDirection: TextDirection.ltr,
        text: TextSpan(
          children: [
            TextSpan(
              text: '$category\n',
              style: const TextStyle(
                color: Color(0xFF1E3A5F),
                fontSize: 12,
                fontWeight: FontWeight.w900,
                height: 1.2,
              ),
            ),
            TextSpan(
              text: '$value min • $percent%',
              style: TextStyle(
                color: labelColor,
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                height: 1.25,
              ),
            ),
          ],
        ),
      )..layout(maxWidth: size.width - legendX - 8);

      legendPainter.paint(canvas, Offset(legendX + 12, legendY));
      legendY += 42;
    }
  }

  @override
  bool shouldRepaint(covariant _CategoryDistributionPainter oldDelegate) {
    return oldDelegate.data != data ||
        oldDelegate.total != total ||
        oldDelegate.colors != colors;
  }
}

class CoachAthleteEvaluationTeamSelectPage extends StatefulWidget {
  const CoachAthleteEvaluationTeamSelectPage({super.key});

  @override
  State<CoachAthleteEvaluationTeamSelectPage> createState() =>
      _CoachAthleteEvaluationTeamSelectPageState();
}

class _CoachAthleteEvaluationTeamSelectPageState
    extends State<CoachAthleteEvaluationTeamSelectPage> {
  static const Color olympusBlue = Color(0xFF1E3A5F);
  static const Color olympusLightBlue = Color(0xFF2C5F8D);
  static const Color olympusGold = Color(0xFFD4AF37);
  static const Color olympusPurple = Color(0xFF7C3AED);
  static const Color olympusBg = Color(0xFFF4F7FB);

  final PermissionService _permissionService = PermissionService();
  bool _loadingScope = true;
  String _coachTeamGender = 'all';

  @override
  void initState() {
    super.initState();
    _loadCoachScope();
  }

  Future<void> _loadCoachScope() async {
    try {
      final scope = await _permissionService.getCoachTeamGender();
      if (!mounted) return;
      setState(() {
        _coachTeamGender = scope;
        _loadingScope = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _coachTeamGender = 'all';
        _loadingScope = false;
      });
    }
  }

  bool _canOpenGender(String gender) {
    final normalized = _coachTeamGender.trim().toLowerCase();
    if (normalized == 'all' || normalized == 'ambos' || normalized.isEmpty) {
      return true;
    }
    return normalized == gender.trim().toLowerCase();
  }

  String get _scopeLabel {
    switch (_coachTeamGender.trim().toLowerCase()) {
      case 'feminino':
        return 'Time Feminino';
      case 'masculino':
        return 'Time Masculino';
      default:
        return 'Times Feminino e Masculino';
    }
  }

  void _openTeam(BuildContext context, String gender) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CoachAthleteEvaluationsPage(
          initialGenderFilter: gender,
        ),
      ),
    );
  }

  Widget _background() {
    return Stack(
      children: [
        Positioned.fill(
          child: Image.asset(
            'assets/images/monte_olimpo_v2.png',
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) {
              return Container(color: const Color(0xFF102845));
            },
          ),
        ),
        Positioned.fill(
          child: Container(color: Colors.black.withOpacity(0.34)),
        ),
        Positioned.fill(
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  olympusBlue.withOpacity(0.88),
                  olympusLightBlue.withOpacity(0.44),
                  Colors.black.withOpacity(0.76),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _heroCard() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 18, 16, 18),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: const LinearGradient(
          colors: [
            Color(0xFF071A30),
            Color(0xFF123861),
            Color(0xFF2C5F8D),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: olympusGold, width: 1.1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.30),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Avaliação de Atletas',
            style: TextStyle(
              color: Colors.white,
              fontSize: 23,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Escopo liberado para este treinador: $_scopeLabel.',
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 13,
              fontWeight: FontWeight.w700,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }

  Widget _teamButton({
    required BuildContext context,
    required String title,
    required String gender,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 14),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _openTeam(context, gender),
          borderRadius: BorderRadius.circular(24),
          child: Ink(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.96),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: color.withOpacity(0.35)),
              boxShadow: [
                BoxShadow(
                  color: color.withOpacity(0.20),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: color.withOpacity(0.15),
                  ),
                  child: Icon(icon, color: color, size: 32),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      color: olympusBlue,
                      fontSize: 19,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                Icon(
                  Icons.arrow_forward_ios_rounded,
                  color: color,
                  size: 18,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: olympusBg,
      appBar: AppBar(
        title: const Text('Avaliação de Atletas'),
        backgroundColor: olympusBlue,
        foregroundColor: Colors.white,
      ),
      body: Stack(
        children: [
          Positioned.fill(child: _background()),
          if (_loadingScope)
            const Center(
              child: CircularProgressIndicator(color: Colors.white),
            )
          else
            ListView(
              padding: const EdgeInsets.only(bottom: 28),
              children: [
                _heroCard(),
                if (_canOpenGender('Feminino'))
                  _teamButton(
                    context: context,
                    title: 'Time Feminino',
                    gender: 'Feminino',
                    icon: Icons.female_rounded,
                    color: olympusPurple,
                  ),
                if (_canOpenGender('Masculino'))
                  _teamButton(
                    context: context,
                    title: 'Time Masculino',
                    gender: 'Masculino',
                    icon: Icons.male_rounded,
                    color: olympusBlue,
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class CoachAthleteEvaluationsPage extends StatefulWidget {
  const CoachAthleteEvaluationsPage({super.key, this.initialGenderFilter});

  final String? initialGenderFilter;

  @override
  State<CoachAthleteEvaluationsPage> createState() =>
      _CoachAthleteEvaluationsPageState();
}

class _CoachAthleteEvaluationsPageState
    extends State<CoachAthleteEvaluationsPage> {
  String _completeEvaluationFilter = 'Todas';

  final SupabaseClient _supabase = Supabase.instance.client;
  final PermissionService _permissionService = PermissionService();

  static const Color olympusBlue = Color(0xFF1E3A5F);
  static const Color olympusGold = Color(0xFFD4AF37);
  static const Color olympusPurple = Color(0xFF7C3AED);
  static const Color olympusSuccess = Color(0xFF16A34A);
  static const Color olympusWarning = Color(0xFFF59E0B);
  static const Color olympusDanger = Color(0xFFDC2626);
  static const Color olympusBorder = Color(0xFFE4EDF5);
  static const Color olympusMuted = Color(0xFF53657B);

  bool _loading = true;
  String? _error;
  String _genderFilter = 'Todos';
  DateTime _selectedMonth = DateTime(DateTime.now().year, DateTime.now().month);

  List<AthleteEvaluationStatus> _athletes = [];

  @override
  void initState() {
    super.initState();
    if (widget.initialGenderFilter != null &&
        widget.initialGenderFilter!.trim().isNotEmpty) {
      final initialGender = widget.initialGenderFilter!;
      if (initialGender == 'Feminino' || initialGender == 'Masculino') {
        _genderFilter = initialGender;
      }
    }

    if (widget.initialGenderFilter != null &&
        widget.initialGenderFilter!.trim().isNotEmpty) {}

    _carregarAtletasVisiveis();
  }

  DateTime get _monthStart =>
      DateTime(_selectedMonth.year, _selectedMonth.month, 1);

  DateTime get _monthEnd =>
      DateTime(_selectedMonth.year, _selectedMonth.month + 1, 1);

  bool get _isCurrentMonth {
    final now = DateTime.now();
    return _selectedMonth.year == now.year && _selectedMonth.month == now.month;
  }

  bool get _isLastFourDaysOfMonth {
    final now = DateTime.now();
    final lastDay = DateTime(now.year, now.month + 1, 0).day;
    return now.day >= lastDay - 3;
  }

  bool get _canCompleteMonthly => _isCurrentMonth && _isLastFourDaysOfMonth;

  int get _pendingMonthlyCount =>
      _athletes.where((a) => !a.hasMonthlyComplete).length;

  List<AthleteEvaluationStatus> get _filteredAthletes {
    Iterable<AthleteEvaluationStatus> base = _athletes;

    if (_genderFilter != 'Todos') {
      final filter = _genderFilter.toLowerCase();
      base = base.where((athlete) {
        final gender = athlete.gender.toLowerCase().trim();

        if (filter == 'feminino') {
          return gender == 'feminino' || gender == 'female' || gender == 'f';
        }

        if (filter == 'masculino') {
          return gender == 'masculino' || gender == 'male' || gender == 'm';
        }

        return true;
      });
    }

    final filtered = base.where(_matchesCompleteEvaluationFilter).toList()
      ..sort(
        (a, b) => a.athleteName
            .toLowerCase()
            .trim()
            .compareTo(b.athleteName.toLowerCase().trim()),
      );

    return filtered;
  }

  List<DateTime> _monthOptions() {
    final now = DateTime.now();
    final months = List.generate(
      12,
      (index) => DateTime(now.year, now.month - index, 1),
    );

    months.sort((a, b) {
      final yearCompare = a.year.compareTo(b.year);
      if (yearCompare != 0) return yearCompare;
      return a.month.compareTo(b.month);
    });

    return months;
  }

  String _monthLabel(DateTime date) {
    const names = [
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

    return '${names[date.month - 1]}/${date.year}';
  }

  Future<void> _carregarAtletasVisiveis() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final visibleIds =
          await _permissionService.getVisibleUserIdsForPage('avaliacoes');

      if (visibleIds.isEmpty) {
        if (!mounted) return;
        setState(() {
          _athletes = [];
          _loading = false;
        });
        return;
      }

      final profilesResponse = await _supabase
          .from('profiles')
          .select('id, full_name, avatar_url, gender, user_type')
          .inFilter('id', visibleIds)
          .eq('user_type', 'athlete')
          .order('full_name', ascending: true);

      final loadedProfiles =
          List<Map<String, dynamic>>.from(profilesResponse as List);

      final profiles = await _permissionService.filterAthletesForCurrentCoach(
        loadedProfiles,
      );

      final athleteIds = profiles
          .map((profile) => (profile['id'] ?? '').toString())
          .where((id) => id.isNotEmpty)
          .toList();

      if (athleteIds.isEmpty) {
        if (!mounted) return;
        setState(() {
          _athletes = [];
          _loading = false;
        });
        return;
      }

      final evaluationsResponse = await _supabase
          .from('training_evaluations')
          .select(
            'athlete_id, tipo, fundamento, motivo, observacao, created_at, score',
          )
          .inFilter('athlete_id', athleteIds)
          .order('created_at', ascending: false);

      final evaluations =
          List<Map<String, dynamic>>.from(evaluationsResponse as List);

      final evaluationsByAthlete = <String, List<Map<String, dynamic>>>{};
      for (final row in evaluations) {
        final athleteId = (row['athlete_id'] ?? '').toString();
        if (athleteId.isEmpty) continue;
        evaluationsByAthlete.putIfAbsent(athleteId, () => []);
        evaluationsByAthlete[athleteId]!.add(row);
      }

      final list = profiles.map((profile) {
        final athleteId = (profile['id'] ?? '').toString();
        final athleteEvaluations =
            evaluationsByAthlete[athleteId] ?? <Map<String, dynamic>>[];

        int destaques = 0;
        int atencoes = 0;
        int totalAvaliacoesMes = 0;
        bool hasMonthlyComplete = false;
        DateTime? lastEvaluationDate;
        final attentionFundamentCount = <String, int>{};

        for (final evaluation in athleteEvaluations) {
          final tipo = (evaluation['tipo'] ?? '').toString().toLowerCase();
          final fundamento = (evaluation['fundamento'] ?? '').toString().trim();
          final createdAt = DateTime.tryParse(
            (evaluation['created_at'] ?? '').toString(),
          )?.toLocal();

          if (createdAt != null &&
              (lastEvaluationDate == null ||
                  createdAt.isAfter(lastEvaluationDate!))) {
            lastEvaluationDate = createdAt;
          }

          final isInSelectedMonth = createdAt != null &&
              !createdAt.isBefore(_monthStart) &&
              createdAt.isBefore(_monthEnd);

          if (tipo == 'completa' && isInSelectedMonth) {
            hasMonthlyComplete = true;
          }

          if (!isInSelectedMonth) continue;

          if (tipo == 'destaque' ||
              tipo == 'atencao' ||
              tipo == 'atenção' ||
              tipo == 'rapida') {
            totalAvaliacoesMes++;
          }

          if (tipo == 'destaque') {
            destaques++;
          } else if (tipo == 'atencao' || tipo == 'atenção') {
            atencoes++;
            if (fundamento.isNotEmpty) {
              attentionFundamentCount[fundamento] =
                  (attentionFundamentCount[fundamento] ?? 0) + 1;
            }
          }
        }

        String mainFocus = 'A definir';
        if (attentionFundamentCount.isNotEmpty) {
          final sorted = attentionFundamentCount.entries.toList()
            ..sort((a, b) => b.value.compareTo(a.value));
          mainFocus = sorted.first.key;
        } else {
          final lastFundamento = athleteEvaluations
              .map((e) => (e['fundamento'] ?? '').toString().trim())
              .firstWhere((value) => value.isNotEmpty, orElse: () => '');
          if (lastFundamento.isNotEmpty) {
            mainFocus = lastFundamento;
          }
        }

        String generalEvolution = 'Sem histórico no mês';
        if (totalAvaliacoesMes > 0) {
          if (destaques > atencoes) {
            generalEvolution = 'Melhorando';
          } else if (atencoes > destaques) {
            generalEvolution = 'Precisa de atenção';
          } else {
            generalEvolution = 'Estável';
          }
        }

        return AthleteEvaluationStatus(
          athleteId: athleteId,
          athleteName: (profile['full_name'] ?? 'Atleta').toString(),
          avatarUrl: (profile['avatar_url'] ?? '').toString(),
          gender: (profile['gender'] ?? '').toString(),
          generalEvolution: generalEvolution,
          mainFocus: mainFocus,
          evaluationsSinceLastFull: totalAvaliacoesMes % 3,
          isPresent: true,
          totalEvaluations: totalAvaliacoesMes,
          destaques: destaques,
          atencoes: atencoes,
          hasMonthlyComplete: hasMonthlyComplete,
          lastEvaluationAt: lastEvaluationDate,
        );
      }).toList();

      if (!mounted) return;
      setState(() {
        _athletes = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Erro ao carregar atletas visíveis: $e';
        _loading = false;
      });
    }
  }

  Future<void> _salvarAvaliacaoRapida(
    AthleteEvaluationStatus athlete,
    EvaluationSubmissionResult result,
  ) async {
    final user = _supabase.auth.currentUser;
    if (user == null) {
      throw Exception('Usuário não autenticado');
    }

    final tipo = result.generalEvolution == 'Melhorando'
        ? 'destaque'
        : result.generalEvolution == 'Precisa de atenção'
            ? 'atencao'
            : 'rapida';

    await _supabase.from('training_evaluations').insert({
      'coach_id': user.id,
      'athlete_id': athlete.athleteId,
      'tipo': tipo,
      'slot': 'avaliacao_rapida',
      'motivo': result.generalEvolution,
      'fundamento': result.mainFocus,
      'observacao': result.messageToAthlete.trim().isEmpty
          ? 'Avaliação rápida registrada pelo técnico.'
          : result.messageToAthlete.trim(),
      'score': tipo == 'destaque'
          ? 2
          : tipo == 'atencao'
              ? -1
              : 0,
    });

    if (result.sendToAthlete) {
      await sendEvaluationMessageToAthlete(
        supabase: _supabase,
        athleteId: athlete.athleteId,
        title: 'Avaliação rápida',
        body: result.messageToAthlete.trim().isEmpty
            ? 'Sua avaliação rápida foi registrada. Evolução: ${result.generalEvolution}. Foco: ${result.mainFocus}.'
            : result.messageToAthlete.trim(),
      );
    }
  }

  Widget _buildEvaluationBackground() {
    return Stack(
      children: [
        Positioned.fill(
          child: Image.asset(
            'assets/images/monte_olimpo_v2.png',
            fit: BoxFit.cover,
          ),
        ),
        Positioned.fill(
          child: Container(color: Colors.black.withOpacity(0.35)),
        ),
      ],
    );
  }

  Widget _buildFilters() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.96),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: olympusBorder),
      ),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final screenWidth = MediaQuery.of(context).size.width;
              final fieldWidth = screenWidth < 390 ? double.infinity : 172.0;

              return SizedBox(
                width: fieldWidth,
                child: DropdownButtonFormField<DateTime>(
                  value: DateTime(_selectedMonth.year, _selectedMonth.month, 1),
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Mês',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  items: _monthOptions().map((month) {
                    return DropdownMenuItem<DateTime>(
                      value: month,
                      child: Text(
                        _monthLabel(month),
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                  }).toList(),
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() => _selectedMonth = value);
                    _carregarAtletasVisiveis();
                  },
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildMonthlyReminder() {
    if (!_isCurrentMonth ||
        !_isLastFourDaysOfMonth ||
        _pendingMonthlyCount == 0) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: olympusWarning.withOpacity(0.96),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(0.38)),
      ),
      child: Row(
        children: [
          const Icon(Icons.notifications_active_outlined, color: olympusBlue),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Fechamento mensal: $_pendingMonthlyCount atleta(s) ainda sem avaliação completa.',
              style: const TextStyle(
                color: olympusBlue,
                fontSize: 13,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openQuickEvaluation(AthleteEvaluationStatus athlete) async {
    final result = await Navigator.push<EvaluationSubmissionResult>(
      context,
      MaterialPageRoute(
        builder: (_) => AthleteEvaluationFormPage(
          athleteName: athlete.athleteName,
          isCompleteMode: false,
          currentFocus:
              athlete.mainFocus == 'A definir' ? '' : athlete.mainFocus,
        ),
      ),
    );

    if (result == null) return;

    try {
      await _salvarAvaliacaoRapida(athlete, result);
      await _carregarAtletasVisiveis();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Avaliação rápida salva para ${athlete.athleteName}.'),
          backgroundColor: olympusSuccess,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao salvar avaliação rápida: $e'),
          backgroundColor: olympusDanger,
        ),
      );
    }
  }

  Future<void> _openCompleteEvaluation(AthleteEvaluationStatus athlete) async {
    if (!_canCompleteMonthly) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Avaliação completa liberada apenas nos últimos 4 dias do mês atual.',
          ),
        ),
      );
      return;
    }

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CoachCompleteMonthlyEvaluationPage(
          athletes: [athlete],
        ),
      ),
    );

    await _carregarAtletasVisiveis();
  }

  Future<void> _viewAthleteEvaluations(AthleteEvaluationStatus athlete) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AthleteEvaluationsHistoryPage(
          athlete: athlete,
          selectedMonth: _selectedMonth,
          canEdit: false,
        ),
      ),
    );
  }

  Future<void> _editAthleteEvaluations(AthleteEvaluationStatus athlete) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AthleteEvaluationsHistoryPage(
          athlete: athlete,
          selectedMonth: _selectedMonth,
          canEdit: true,
        ),
      ),
    );

    await _carregarAtletasVisiveis();
  }

  bool _hasCompleteMonthlyEvaluation(AthleteEvaluationStatus athlete) {
    return athlete.hasMonthlyComplete;
  }

  bool _matchesCompleteEvaluationFilter(AthleteEvaluationStatus athlete) {
    if (_completeEvaluationFilter == 'Todas') return true;
    if (_completeEvaluationFilter == 'Realizadas') {
      return _hasCompleteMonthlyEvaluation(athlete);
    }
    if (_completeEvaluationFilter == 'Pendentes') {
      return !_hasCompleteMonthlyEvaluation(athlete);
    }
    return true;
  }

  Widget _buildCompleteEvaluationFilterChip(String label) {
    final selected = _completeEvaluationFilter == label;

    final icon = label == 'Realizadas'
        ? Icons.check_circle_outline_rounded
        : label == 'Pendentes'
            ? Icons.pending_actions_rounded
            : Icons.list_alt_rounded;

    return ChoiceChip(
      avatar: Icon(
        icon,
        size: 16,
        color: selected ? Colors.white : olympusBlue,
      ),
      label: Text(label),
      selected: selected,
      showCheckmark: false,
      selectedColor: olympusBlue,
      backgroundColor: const Color(0xFFF7FAFC),
      side: BorderSide(
        color: selected ? olympusBlue : olympusBorder,
      ),
      labelStyle: TextStyle(
        color: selected ? Colors.white : olympusBlue,
        fontWeight: FontWeight.w900,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
      onSelected: (_) {
        setState(() => _completeEvaluationFilter = label);
      },
    );
  }

  Widget _buildCompleteEvaluationFilterBar() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.96),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: olympusBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.10),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(left: 4, bottom: 10),
            child: Text(
              'Avaliação completa',
              style: TextStyle(
                color: olympusBlue,
                fontSize: 13,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildCompleteEvaluationFilterChip('Todas'),
                const SizedBox(width: 8),
                _buildCompleteEvaluationFilterChip('Realizadas'),
                const SizedBox(width: 8),
                _buildCompleteEvaluationFilterChip('Pendentes'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredAthletes;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Avaliação de Atletas'),
        backgroundColor: olympusBlue,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            onPressed: _carregarAtletasVisiveis,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Stack(
        children: [
          Positioned.fill(child: _buildEvaluationBackground()),
          Column(
            children: [
              _buildFilters(),
              _buildCompleteEvaluationFilterBar(),
              _buildMonthlyReminder(),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _error != null
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Text(
                                _error!,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          )
                        : filtered.isEmpty
                            ? const Center(
                                child: Padding(
                                  padding: EdgeInsets.all(24),
                                  child: Text(
                                    'Nenhum atleta encontrado para o mês e status selecionados.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              )
                            : RefreshIndicator(
                                onRefresh: _carregarAtletasVisiveis,
                                child: ListView.separated(
                                  padding:
                                      const EdgeInsets.fromLTRB(16, 0, 16, 24),
                                  itemCount: filtered.length,
                                  separatorBuilder: (_, __) =>
                                      const SizedBox(height: 12),
                                  itemBuilder: (context, index) {
                                    final athlete = filtered[index];

                                    return _AthleteEvaluationCard(
                                      athlete: athlete,
                                      completeEnabled: _canCompleteMonthly &&
                                          !athlete.hasMonthlyComplete,
                                      completeStatus: athlete.hasMonthlyComplete
                                          ? 'Concluída'
                                          : _canCompleteMonthly
                                              ? 'Pendente'
                                              : 'Bloqueada',
                                      onQuickTap: () =>
                                          _openQuickEvaluation(athlete),
                                      onCompleteTap: () =>
                                          _openCompleteEvaluation(athlete),
                                      onViewTap: () =>
                                          _viewAthleteEvaluations(athlete),
                                      onEditTap: () =>
                                          _editAthleteEvaluations(athlete),
                                    );
                                  },
                                ),
                              ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AthleteEvaluationCard extends StatelessWidget {
  const _AthleteEvaluationCard({
    required this.athlete,
    required this.completeEnabled,
    required this.completeStatus,
    required this.onQuickTap,
    required this.onCompleteTap,
    required this.onViewTap,
    required this.onEditTap,
  });

  final AthleteEvaluationStatus athlete;
  final bool completeEnabled;
  final String completeStatus;
  final VoidCallback onQuickTap;
  final VoidCallback onCompleteTap;
  final VoidCallback onViewTap;
  final VoidCallback onEditTap;

  static const Color olympusBlue = Color(0xFF1E3A5F);
  static const Color olympusGold = Color(0xFFD4AF37);
  static const Color olympusPurple = Color(0xFF7C3AED);
  static const Color olympusSuccess = Color(0xFF16A34A);
  static const Color olympusWarning = Color(0xFFF59E0B);

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final compact = screenWidth < 390;
    final tablet = screenWidth >= 700;

    final avatarUrl = athlete.avatarUrl.trim();
    final cardPadding = compact
        ? 14.0
        : tablet
            ? 18.0
            : 16.0;
    final avatarRadius = compact
        ? 23.0
        : tablet
            ? 28.0
            : 26.0;
    final titleSize = compact
        ? 15.0
        : tablet
            ? 18.0
            : 16.0;
    final bodySize = compact
        ? 11.5
        : tablet
            ? 13.5
            : 12.5;

    Widget avatar() {
      return CircleAvatar(
        radius: avatarRadius,
        backgroundColor: olympusBlue,
        backgroundImage: avatarUrl.isNotEmpty ? NetworkImage(avatarUrl) : null,
        child: avatarUrl.isEmpty
            ? Text(
                athlete.athleteName.isNotEmpty
                    ? athlete.athleteName.substring(0, 1)
                    : '?',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: compact ? 14 : 16,
                ),
              )
            : null,
      );
    }

    Widget statusChip() {
      final done = athlete.hasMonthlyComplete;
      return Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 8 : 10,
          vertical: compact ? 6 : 7,
        ),
        decoration: BoxDecoration(
          color: (done ? olympusSuccess : olympusWarning).withOpacity(0.12),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: (done ? olympusSuccess : olympusWarning).withOpacity(0.24),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              done ? Icons.check_circle_outline : Icons.warning_amber_rounded,
              size: compact ? 14 : 15,
              color: done ? olympusSuccess : olympusWarning,
            ),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                done ? 'Mensal concluída' : 'Mensal pendente',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: done ? olympusSuccess : olympusWarning,
                  fontSize: bodySize,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
      );
    }

    Widget buttons() {
      return LayoutBuilder(
        builder: (context, constraints) {
          final stackButtons = constraints.maxWidth < 320;

          final quickButton = SizedBox(
            height: 48,
            child: ElevatedButton.icon(
              onPressed: onQuickTap,
              icon: const Icon(Icons.fact_check_outlined, size: 16),
              label: const Text(
                'Rápida',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: olympusPurple,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                textStyle: TextStyle(
                  fontSize: compact ? 12 : 13,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          );

          final completeButton = SizedBox(
            height: 48,
            child: ElevatedButton.icon(
              onPressed: completeEnabled ? onCompleteTap : null,
              icon: const Icon(Icons.assignment_turned_in_outlined, size: 16),
              label: Text(
                stackButtons ? 'Completa • $completeStatus' : 'Completa',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: olympusGold,
                foregroundColor: olympusBlue,
                disabledBackgroundColor: Colors.grey.withOpacity(0.28),
                disabledForegroundColor: Colors.grey.shade600,
                elevation: 0,
                padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                textStyle: TextStyle(
                  fontSize: compact ? 12 : 13,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          );

          final viewButton = SizedBox(
            height: 46,
            child: OutlinedButton.icon(
              onPressed: onViewTap,
              icon: const Icon(Icons.visibility_outlined, size: 16),
              label: const Text(
                'Visualizar',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: olympusBlue,
                side: const BorderSide(color: Color(0xFFE4EDF5)),
                padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                textStyle: TextStyle(
                  fontSize: compact ? 12 : 13,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          );

          final editButton = SizedBox(
            height: 46,
            child: OutlinedButton.icon(
              onPressed: onEditTap,
              icon: const Icon(Icons.edit_outlined, size: 16),
              label: const Text(
                'Editar',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: olympusPurple,
                side: BorderSide(color: olympusPurple.withOpacity(0.35)),
                padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                textStyle: TextStyle(
                  fontSize: compact ? 12 : 13,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          );

          if (stackButtons) {
            return Column(
              children: [
                SizedBox(width: double.infinity, child: quickButton),
                const SizedBox(height: 8),
                SizedBox(width: double.infinity, child: completeButton),
                const SizedBox(height: 8),
                SizedBox(width: double.infinity, child: viewButton),
                const SizedBox(height: 8),
                SizedBox(width: double.infinity, child: editButton),
              ],
            );
          }

          return Column(
            children: [
              Row(
                children: [
                  Expanded(child: quickButton),
                  const SizedBox(width: 8),
                  Expanded(child: completeButton),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: viewButton),
                  const SizedBox(width: 8),
                  Expanded(child: editButton),
                ],
              ),
            ],
          );
        },
      );
    }

    Widget details() {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            athlete.athleteName,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: titleSize,
              fontWeight: FontWeight.w900,
              color: const Color(0xFF17324D),
              height: 1.08,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Evolução: ${athlete.generalEvolution}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: bodySize,
              fontWeight: FontWeight.w800,
              color: const Color(0xFF53657B),
            ),
          ),
          const SizedBox(height: 3),
          Text(
            'Foco: ${athlete.mainFocus}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: bodySize,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF6A7E94),
            ),
          ),
          const SizedBox(height: 3),
          Text(
            'Mês: ${athlete.destaques} destaque(s) • ${athlete.atencoes} atenção • ${athlete.totalEvaluations} avaliação(ões)',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: bodySize,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF6A7E94),
            ),
          ),
          const SizedBox(height: 3),
          Text(
            'Última: ${athlete.lastEvaluationLabel}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: bodySize,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF6A7E94),
            ),
          ),
          const SizedBox(height: 8),
          statusChip(),
          const SizedBox(height: 12),
          buttons(),
        ],
      );
    }

    return Material(
      color: Colors.white.withOpacity(0.97),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: EdgeInsets.all(cardPadding),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFE4EDF5)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.10),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: compact
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      avatar(),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          athlete.athleteName,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: titleSize,
                            fontWeight: FontWeight.w900,
                            color: const Color(0xFF17324D),
                            height: 1.08,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Evolução: ${athlete.generalEvolution}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: bodySize,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF53657B),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'Foco: ${athlete.mainFocus}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: bodySize,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF6A7E94),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'Mês: ${athlete.destaques} destaque(s) • ${athlete.atencoes} atenção • ${athlete.totalEvaluations} avaliação(ões)',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: bodySize,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF6A7E94),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'Última: ${athlete.lastEvaluationLabel}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: bodySize,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF6A7E94),
                    ),
                  ),
                  const SizedBox(height: 8),
                  statusChip(),
                  const SizedBox(height: 12),
                  buttons(),
                ],
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  avatar(),
                  const SizedBox(width: 14),
                  Expanded(child: details()),
                ],
              ),
      ),
    );
  }
}

class AthleteEvaluationsHistoryPage extends StatefulWidget {
  const AthleteEvaluationsHistoryPage({
    super.key,
    required this.athlete,
    required this.selectedMonth,
    required this.canEdit,
  });

  final AthleteEvaluationStatus athlete;
  final DateTime selectedMonth;
  final bool canEdit;

  @override
  State<AthleteEvaluationsHistoryPage> createState() =>
      _AthleteEvaluationsHistoryPageState();
}

class _AthleteEvaluationsHistoryPageState
    extends State<AthleteEvaluationsHistoryPage> {
  final SupabaseClient _supabase = Supabase.instance.client;

  static const Color olympusBlue = Color(0xFF1E3A5F);
  static const Color olympusGold = Color(0xFFD4AF37);
  static const Color olympusPurple = Color(0xFF7C3AED);
  static const Color olympusBg = Color(0xFFF4F7FB);
  static const Color olympusMuted = Color(0xFF53657B);
  static const Color olympusBorder = Color(0xFFE4EDF5);
  static const Color olympusDanger = Color(0xFFDC2626);
  static const Color olympusSuccess = Color(0xFF16A34A);

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _evaluations = [];

  DateTime get _monthStart =>
      DateTime(widget.selectedMonth.year, widget.selectedMonth.month, 1);

  DateTime get _monthEnd =>
      DateTime(widget.selectedMonth.year, widget.selectedMonth.month + 1, 1);

  @override
  void initState() {
    super.initState();
    _loadEvaluations();
  }

  String _monthLabel() {
    const names = [
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
    return '${names[widget.selectedMonth.month - 1]}/${widget.selectedMonth.year}';
  }

  Future<void> _loadEvaluations() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final rows = await _supabase
          .from('training_evaluations')
          .select(
            'id, event_id, coach_id, athlete_id, tipo, slot, motivo, fundamento, observacao, created_at, event_name, event_date, score',
          )
          .eq('athlete_id', widget.athlete.athleteId)
          .gte('created_at', _monthStart.toIso8601String())
          .lt('created_at', _monthEnd.toIso8601String())
          .order('created_at', ascending: false);

      if (!mounted) return;
      setState(() {
        _evaluations = List<Map<String, dynamic>>.from(rows as List);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Erro ao carregar avaliações: $e';
        _loading = false;
      });
    }
  }

  String _formatDate(dynamic value) {
    final parsed = DateTime.tryParse((value ?? '').toString())?.toLocal();
    if (parsed == null) return 'Sem data';
    return '${parsed.day.toString().padLeft(2, '0')}/${parsed.month.toString().padLeft(2, '0')}/${parsed.year}';
  }

  Color _typeColor(String tipo) {
    final normalized = tipo.toLowerCase();
    if (normalized == 'destaque') return olympusSuccess;
    if (normalized == 'atencao' || normalized == 'atenção') {
      return const Color(0xFFF59E0B);
    }
    if (normalized == 'completa') return olympusGold;
    return olympusBlue;
  }

  Future<void> _editEvaluation(Map<String, dynamic> evaluation) async {
    final motivoController = TextEditingController(
      text: (evaluation['motivo'] ?? '').toString(),
    );
    final fundamentoController = TextEditingController(
      text: (evaluation['fundamento'] ?? '').toString(),
    );
    final observacaoController = TextEditingController(
      text: (evaluation['observacao'] ?? '').toString(),
    );
    final scoreController = TextEditingController(
      text: (evaluation['score'] ?? '').toString(),
    );

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
            ),
            child: SafeArea(
              top: false,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 46,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Editar avaliação',
                      style: TextStyle(
                        color: olympusBlue,
                        fontSize: 19,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: motivoController,
                      decoration: const InputDecoration(
                        labelText: 'Motivo / tendência',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: fundamentoController,
                      decoration: const InputDecoration(
                        labelText: 'Fundamento',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: scoreController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Score / nota',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: observacaoController,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        labelText: 'Observação',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => Navigator.pop(context, false),
                            icon: const Icon(Icons.close),
                            label: const Text('Cancelar'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () async {
                              final id = (evaluation['id'] ?? '').toString();
                              if (id.isEmpty) return;

                              await _supabase
                                  .from('training_evaluations')
                                  .update({
                                'motivo': motivoController.text.trim(),
                                'fundamento': fundamentoController.text.trim(),
                                'observacao': observacaoController.text.trim(),
                                'score':
                                    int.tryParse(scoreController.text.trim()),
                              }).eq('id', id);

                              if (context.mounted) {
                                Navigator.pop(context, true);
                              }
                            },
                            icon: const Icon(Icons.save_outlined),
                            label: const Text('Salvar'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: olympusBlue,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );

    motivoController.dispose();
    fundamentoController.dispose();
    observacaoController.dispose();
    scoreController.dispose();

    if (saved == true) {
      await _loadEvaluations();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Avaliação atualizada.'),
          backgroundColor: olympusSuccess,
        ),
      );
    }
  }

  Future<void> _deleteEvaluation(Map<String, dynamic> evaluation) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Excluir avaliação?'),
        content: const Text('Essa ação não pode ser desfeita.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: olympusDanger),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final id = (evaluation['id'] ?? '').toString();
    if (id.isEmpty) return;

    await _supabase.from('training_evaluations').delete().eq('id', id);
    await _loadEvaluations();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Avaliação excluída.'),
        backgroundColor: olympusDanger,
      ),
    );
  }

  Widget _evaluationCard(Map<String, dynamic> evaluation) {
    final tipo = (evaluation['tipo'] ?? 'avaliação').toString();
    final color = _typeColor(tipo);
    final motivo = (evaluation['motivo'] ?? '').toString();
    final fundamento = (evaluation['fundamento'] ?? '').toString();
    final observacao = (evaluation['observacao'] ?? '').toString();
    final slot = (evaluation['slot'] ?? '').toString();
    final score = (evaluation['score'] ?? '').toString();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.97),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: olympusBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.07),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  tipo.toUpperCase(),
                  style: TextStyle(
                    color: color,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const Spacer(),
              Text(
                _formatDate(evaluation['created_at']),
                style: const TextStyle(
                  color: olympusMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (slot.isNotEmpty)
            Text(
              'Slot: $slot',
              style: const TextStyle(
                color: olympusMuted,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          if (fundamento.isNotEmpty) ...[
            const SizedBox(height: 5),
            Text(
              'Fundamento: $fundamento',
              style: const TextStyle(
                color: olympusBlue,
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
          if (motivo.isNotEmpty) ...[
            const SizedBox(height: 5),
            Text(
              'Motivo: $motivo',
              style: const TextStyle(
                color: olympusMuted,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          if (score.isNotEmpty && score != 'null') ...[
            const SizedBox(height: 5),
            Text(
              'Score/nota: $score',
              style: const TextStyle(
                color: olympusMuted,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          if (observacao.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              observacao,
              style: const TextStyle(
                color: Color(0xFF6A7E94),
                fontSize: 13,
                fontWeight: FontWeight.w600,
                height: 1.35,
              ),
            ),
          ],
          if (widget.canEdit) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _editEvaluation(evaluation),
                    icon: const Icon(Icons.edit_outlined, size: 16),
                    label: const Text('Editar'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: olympusPurple,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _deleteEvaluation(evaluation),
                    icon: const Icon(Icons.delete_outline, size: 16),
                    label: const Text('Excluir'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: olympusDanger,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.canEdit ? 'Editar avaliações' : 'Avaliações';

    return Scaffold(
      backgroundColor: olympusBg,
      appBar: AppBar(
        title: Text(title),
        backgroundColor: olympusBlue,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            onPressed: _loadEvaluations,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: Image.asset(
              'assets/images/monte_olimpo_v2.png',
              fit: BoxFit.cover,
            ),
          ),
          Positioned.fill(
            child: Container(color: Colors.black.withOpacity(0.35)),
          ),
          SafeArea(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            _error!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      )
                    : ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          Container(
                            padding: const EdgeInsets.all(14),
                            margin: const EdgeInsets.only(bottom: 12),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.97),
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(color: olympusBorder),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  widget.athlete.athleteName,
                                  style: const TextStyle(
                                    color: olympusBlue,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'Período: ${_monthLabel()}',
                                  style: const TextStyle(
                                    color: olympusMuted,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (_evaluations.isEmpty)
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.97),
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(color: olympusBorder),
                              ),
                              child: const Text(
                                'Nenhuma avaliação registrada neste mês.',
                                style: TextStyle(
                                  color: olympusMuted,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            )
                          else
                            ..._evaluations.map(_evaluationCard),
                        ],
                      ),
          ),
        ],
      ),
    );
  }
}

class AthleteEvaluationFormPage extends StatefulWidget {
  const AthleteEvaluationFormPage({
    super.key,
    required this.athleteName,
    required this.isCompleteMode,
    required this.currentFocus,
  });

  final String athleteName;
  final bool isCompleteMode;
  final String currentFocus;

  @override
  State<AthleteEvaluationFormPage> createState() =>
      _AthleteEvaluationFormPageState();
}

class _AthleteEvaluationFormPageState extends State<AthleteEvaluationFormPage> {
  static const Color olympusBlue = Color(0xFF1E3A5F);

  final TextEditingController _focusController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();

  bool _sendToAthlete = false;
  String _generalEvolution = 'Melhorando';

  @override
  void initState() {
    super.initState();
    _focusController.text = widget.currentFocus;
  }

  @override
  void dispose() {
    _focusController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  void _submit() {
    if (_focusController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Informe o principal foco da atleta.')),
      );
      return;
    }

    Navigator.pop(
      context,
      EvaluationSubmissionResult(
        isComplete: false,
        generalEvolution: _generalEvolution,
        mainFocus: _focusController.text.trim(),
        sendToAthlete: _sendToAthlete,
        messageToAthlete: _notesController.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FB),
      appBar: AppBar(
        title: Text('Avaliação rápida - ${widget.athleteName}'),
        backgroundColor: olympusBlue,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          DropdownButtonFormField<String>(
            value: _generalEvolution,
            decoration: const InputDecoration(
              labelText: 'Evolução geral',
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(value: 'Melhorando', child: Text('Melhorando')),
              DropdownMenuItem(value: 'Estável', child: Text('Estável')),
              DropdownMenuItem(
                value: 'Precisa de atenção',
                child: Text('Precisa de atenção'),
              ),
            ],
            onChanged: (value) {
              if (value == null) return;
              setState(() => _generalEvolution = value);
            },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _focusController,
            decoration: const InputDecoration(
              labelText: 'Principal foco',
              hintText: 'Ex: saque, recepção, posicionamento',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE4EDF5)),
            ),
            child: SwitchListTile(
              value: _sendToAthlete,
              contentPadding: EdgeInsets.zero,
              activeColor: olympusBlue,
              secondary: const Icon(
                Icons.send_outlined,
                color: olympusBlue,
              ),
              title: const Text(
                'Enviar para atleta',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
              subtitle: const Text(
                'Ao salvar, a atleta receberá a mensagem abaixo.',
              ),
              onChanged: (value) {
                setState(() => _sendToAthlete = value);
              },
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _notesController,
            maxLines: 4,
            decoration: InputDecoration(
              labelText: _sendToAthlete
                  ? 'Mensagem para atleta'
                  : 'Observação do técnico',
              hintText: _sendToAthlete
                  ? 'Escreva o feedback que será enviado para a atleta.'
                  : 'Observação interna da avaliação rápida.',
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _submit,
              icon: const Icon(Icons.save_outlined),
              label: const Text('Salvar avaliação rápida'),
              style: ElevatedButton.styleFrom(
                backgroundColor: olympusBlue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class AthleteEvaluationStatus {
  AthleteEvaluationStatus({
    required this.athleteId,
    required this.athleteName,
    required this.avatarUrl,
    required this.gender,
    required this.generalEvolution,
    required this.mainFocus,
    required this.evaluationsSinceLastFull,
    required this.isPresent,
    required this.totalEvaluations,
    required this.destaques,
    required this.atencoes,
    required this.hasMonthlyComplete,
    required this.lastEvaluationAt,
  });

  final String athleteId;
  final String athleteName;
  final String avatarUrl;
  final String gender;
  final String generalEvolution;
  final String mainFocus;
  final int evaluationsSinceLastFull;
  final bool isPresent;
  final int totalEvaluations;
  final int destaques;
  final int atencoes;
  final bool hasMonthlyComplete;
  final DateTime? lastEvaluationAt;

  String get lastEvaluationLabel {
    if (lastEvaluationAt == null) return 'Sem avaliação registrada';
    final d = lastEvaluationAt!.toLocal();
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
  }

  bool get requiresCompleteEvaluation => evaluationsSinceLastFull >= 2;

  AthleteEvaluationStatus copyWith({
    String? athleteId,
    String? athleteName,
    String? avatarUrl,
    String? gender,
    String? generalEvolution,
    String? mainFocus,
    int? evaluationsSinceLastFull,
    bool? isPresent,
    int? totalEvaluations,
    int? destaques,
    int? atencoes,
    bool? hasMonthlyComplete,
    DateTime? lastEvaluationAt,
  }) {
    return AthleteEvaluationStatus(
      athleteId: athleteId ?? this.athleteId,
      athleteName: athleteName ?? this.athleteName,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      gender: gender ?? this.gender,
      generalEvolution: generalEvolution ?? this.generalEvolution,
      mainFocus: mainFocus ?? this.mainFocus,
      evaluationsSinceLastFull:
          evaluationsSinceLastFull ?? this.evaluationsSinceLastFull,
      isPresent: isPresent ?? this.isPresent,
      totalEvaluations: totalEvaluations ?? this.totalEvaluations,
      destaques: destaques ?? this.destaques,
      atencoes: atencoes ?? this.atencoes,
      hasMonthlyComplete: hasMonthlyComplete ?? this.hasMonthlyComplete,
      lastEvaluationAt: lastEvaluationAt ?? this.lastEvaluationAt,
    );
  }
}

class EvaluationSubmissionResult {
  EvaluationSubmissionResult({
    required this.isComplete,
    required this.generalEvolution,
    required this.mainFocus,
    required this.sendToAthlete,
    required this.messageToAthlete,
  });

  final bool isComplete;
  final String generalEvolution;
  final String mainFocus;
  final bool sendToAthlete;
  final String messageToAthlete;
}

class FundamentEvaluationModel {
  FundamentEvaluationModel({
    required this.name,
    this.score = 3,
    this.trend = 'Estável',
  }) : notesController = TextEditingController();

  final String name;
  int score;
  String trend;
  final TextEditingController notesController;
}
