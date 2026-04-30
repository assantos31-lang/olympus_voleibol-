import 'dart:ui';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'admin_competitions_page.dart';
import 'coach_training_sessions_page.dart';
import 'coach_ranking_page.dart';
import 'coach_smart_dashboard_page.dart';
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

  bool _isLoading = true;
  bool _isBackgroundReady = false;
  int _competitionNewCount = 0;
  DateTime? _lastCompetitionsViewedAt;
  RealtimeChannel? _competitionsRealtimeChannel;

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

    await _loadCompetitionNewCount();

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

  void _setupRealtimeListeners() {
    _competitionsRealtimeChannel ??=
        supabase.channel('coach-dashboard-competitions')
          ..onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'events',
            callback: (_) {
              _loadCompetitionNewCount();
            },
          )
          ..subscribe();
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
        builder: (context) => const CoachTrainingSessionsPage(),
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
        builder: (context) => const CoachAthleteEvaluationsPage(),
      ),
    );
  }

  Widget _buildPremiumDashboardBackground() {
    return Stack(
      children: [
        Positioned.fill(
          child: Image.asset(
            'assets/images/monte_olimpo_v2.png',
            fit: BoxFit.cover,
            alignment: Alignment.center,
            errorBuilder: (context, error, stackTrace) {
              return Container(color: const Color(0xFF102845));
            },
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

  Widget _buildCoachInfoCard() {
    final fullName = supabase.auth.currentUser?.userMetadata?['full_name']
        ?.toString()
        .trim();
    final firstName = (fullName != null && fullName.isNotEmpty)
        ? fullName.split(' ').first
        : 'Técnico';

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
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
              child: Row(
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
                      child: const Icon(
                        Icons.sports,
                        size: 42,
                        color: Color(0xFFFFF2B8),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Olá, $firstName!',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            height: 1.1,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Área do Técnico',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: Colors.white.withOpacity(0.88),
                          ),
                        ),
                        const SizedBox(height: 10),
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
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.verified_user_outlined,
                                size: 15,
                                color: Color(0xFF42576B),
                              ),
                              SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  'Painel premium do técnico',
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF2E4053),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
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
                            'Gerencie treinos, avaliações e acompanhe as novidades do painel.',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.88),
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF102845),
      appBar: _isLoading
          ? null
          : AppBar(
              title: const Text('Área do Técnico'),
              backgroundColor: olympusBlue,
              foregroundColor: Colors.white,
              actions: [
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
            SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  _buildCoachInfoCard(),
                  _buildDashboardCard(
                    icon: Icons.insights_rounded,
                    title: 'Smart Dashboard',
                    subtitle: 'Insights inteligentes da equipe',
                    color: const Color(0xFFF59E0B),
                    onTap: _navigateToSmartDashboard,
                  ),
                  _buildDashboardCard(
                    icon: Icons.calendar_month_outlined,
                    title: 'Planejamento de treinos',
                    subtitle:
                        'Planejamento e avaliação rápida dos treinos marcados',
                    color: const Color(0xFF3B82F6),
                    onTap: _navigateToTrainingPlanner,
                  ),
                  _buildDashboardCard(
                    icon: Icons.analytics_outlined,
                    title: 'Dashboard de Planejamento',
                    subtitle: 'Tempo mensal por Fundamentos, Tático e Físico',
                    color: const Color(0xFFD4AF37),
                    onTap: _navigateToTrainingPlanningDashboard,
                  ),
                  _buildDashboardCard(
                    icon: Icons.assignment_turned_in_outlined,
                    title: 'Avaliação de Atletas',
                    subtitle: 'Avaliação rápida e completa por ciclo',
                    color: const Color(0xFF8B5CF6),
                    onTap: _navigateToAthleteEvaluations,
                  ),
                  _buildDashboardCard(
                    icon: Icons.bar_chart_rounded,
                    title: 'Ranking dos atletas',
                    subtitle: 'Desempenho com base nas avaliações salvas',
                    color: const Color(0xFF0EA5A4),
                    onTap: _navigateToRanking,
                  ),
                  _buildDashboardCard(
                    icon: Icons.emoji_events_outlined,
                    title: 'Competições',
                    subtitle: 'Veja ligas, campeonatos e amistosos',
                    color: const Color(0xFF2C5F8D),
                    onTap: _navigateToCompetitions,
                    badgeCount:
                        _competitionNewCount > 0 ? _competitionNewCount : null,
                  ),
                  const SizedBox(height: 100),
                ],
              ),
            ),
        ],
      ),
    );
  }
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
                  SizedBox(height: MediaQuery.of(context).size.height * 0.25),
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

class CoachAthleteEvaluationsPage extends StatefulWidget {
  const CoachAthleteEvaluationsPage({super.key});

  @override
  State<CoachAthleteEvaluationsPage> createState() =>
      _CoachAthleteEvaluationsPageState();
}

class _CoachAthleteEvaluationsPageState
    extends State<CoachAthleteEvaluationsPage> {
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
    if (_genderFilter == 'Todos') return _athletes;

    final filter = _genderFilter.toLowerCase();
    return _athletes.where((athlete) {
      final gender = athlete.gender.toLowerCase().trim();

      if (filter == 'feminino') {
        return gender == 'feminino' || gender == 'female' || gender == 'f';
      }

      if (filter == 'masculino') {
        return gender == 'masculino' || gender == 'male' || gender == 'm';
      }

      return true;
    }).toList();
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

      final profiles =
          List<Map<String, dynamic>>.from(profilesResponse as List);

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
          ...['Todos', 'Feminino', 'Masculino'].map((gender) {
            final selected = _genderFilter == gender;
            return ChoiceChip(
              label: Text(gender),
              selected: selected,
              showCheckmark: false,
              selectedColor: olympusBlue,
              backgroundColor: Colors.white,
              side: BorderSide(
                color: selected ? olympusBlue : olympusBorder,
              ),
              labelStyle: TextStyle(
                color: selected ? Colors.white : olympusBlue,
                fontWeight: FontWeight.w800,
              ),
              onSelected: (_) => setState(() => _genderFilter = gender),
            );
          }),
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
                                    'Nenhuma atleta visível para avaliações.',
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

class CoachCompleteMonthlyEvaluationPage extends StatefulWidget {
  const CoachCompleteMonthlyEvaluationPage({
    super.key,
    required this.athletes,
  });

  final List<AthleteEvaluationStatus> athletes;

  @override
  State<CoachCompleteMonthlyEvaluationPage> createState() =>
      _CoachCompleteMonthlyEvaluationPageState();
}

class _CoachCompleteMonthlyEvaluationPageState
    extends State<CoachCompleteMonthlyEvaluationPage> {
  static const Color olympusBlue = Color(0xFF1E3A5F);
  static const Color olympusGold = Color(0xFFD4AF37);
  static const Color olympusBg = Color(0xFFF4F7FB);
  static const Color olympusCard = Colors.white;
  static const Color olympusText = Color(0xFF17324D);
  static const Color olympusMuted = Color(0xFF53657B);
  static const Color olympusSubtle = Color(0xFF6A7E94);
  static const Color olympusBorder = Color(0xFFE4EDF5);
  static const Color olympusSuccess = Color(0xFF16A34A);
  static const Color olympusWarning = Color(0xFFF59E0B);
  static const Color olympusDanger = Color(0xFFDC2626);

  final SupabaseClient _supabase = Supabase.instance.client;

  bool _saving = false;
  bool _sendToAthlete = false;
  String? _selectedAthleteId;

  final TextEditingController _mensagemAtletaController =
      TextEditingController();
  final TextEditingController _observacaoGeralController =
      TextEditingController();
  final TextEditingController _pontoForteController = TextEditingController();
  final TextEditingController _pontoMelhorarController =
      TextEditingController();

  String _evolucaoGeral = 'Estável';
  String _prioridade = 'Média';

  final List<String> _fundamentos = const [
    'Saque',
    'Recepção',
    'Toque',
    'Ataque',
    'Bloqueio',
    'Defesa',
    'Posicionamento tático',
    'Condicionamento físico',
  ];

  final Map<String, int> _notas = {};
  final Map<String, String> _tendencias = {};
  final Map<String, TextEditingController> _observacoesPorFundamento = {};

  @override
  void initState() {
    super.initState();

    _selectedAthleteId =
        widget.athletes.isNotEmpty ? widget.athletes.first.athleteId : null;

    for (final fundamento in _fundamentos) {
      _notas[fundamento] = 3;
      _tendencias[fundamento] = 'Estável';
      _observacoesPorFundamento[fundamento] = TextEditingController();
    }

    if (_selectedAthleteId != null) {
      _carregarAvaliacaoExistente(_selectedAthleteId!);
    }
  }

  @override
  void dispose() {
    _mensagemAtletaController.dispose();
    _observacaoGeralController.dispose();
    _pontoForteController.dispose();
    _pontoMelhorarController.dispose();

    for (final controller in _observacoesPorFundamento.values) {
      controller.dispose();
    }

    super.dispose();
  }

  bool _isMobile(BuildContext context) {
    return MediaQuery.of(context).size.width < 600;
  }

  bool get _isLastFourDaysOfMonth {
    final now = DateTime.now();
    final lastDay = DateTime(now.year, now.month + 1, 0).day;
    return now.day >= lastDay - 3;
  }

  String get _janelaAvaliacaoLabel {
    final now = DateTime.now();
    final lastDay = DateTime(now.year, now.month + 1, 0).day;
    final startDay = lastDay - 3;
    return '$startDay ao $lastDay';
  }

  AthleteEvaluationStatus? get _selectedAthlete {
    if (_selectedAthleteId == null) return null;

    for (final athlete in widget.athletes) {
      if (athlete.athleteId == _selectedAthleteId) return athlete;
    }

    return null;
  }

  Future<void> _carregarAvaliacaoExistente(String athleteId) async {
    try {
      final now = DateTime.now();
      final start = DateTime(now.year, now.month, 1);
      final end = DateTime(now.year, now.month + 1, 1);

      final rows = await _supabase
          .from('training_evaluations')
          .select('slot, fundamento, motivo, observacao, score, created_at')
          .eq('athlete_id', athleteId)
          .eq('tipo', 'completa')
          .gte('created_at', start.toIso8601String())
          .lt('created_at', end.toIso8601String())
          .order('created_at', ascending: false);

      _limparFormulario(manterAtleta: true);

      final list = List<Map<String, dynamic>>.from(rows as List);
      if (list.isEmpty) return;

      for (final row in list) {
        final slot = (row['slot'] ?? '').toString();

        if (slot == 'resumo_mensal') {
          final motivo = (row['motivo'] ?? '').toString();
          final parts = motivo.split('|').map((e) => e.trim()).toList();

          if (parts.isNotEmpty && parts[0].isNotEmpty) {
            _evolucaoGeral = parts[0];
          }
          if (parts.length > 1 && parts[1].isNotEmpty) {
            _prioridade = parts[1];
          }
          if (parts.length > 2) {
            _pontoForteController.text = parts[2];
          }
          if (parts.length > 3) {
            _pontoMelhorarController.text = parts[3];
          }

          _observacaoGeralController.text =
              (row['observacao'] ?? '').toString();
          continue;
        }

        final fundamento = (row['fundamento'] ?? '').toString();
        if (!_fundamentos.contains(fundamento)) continue;

        final score = row['score'];
        if (score is int) {
          _notas[fundamento] = score.clamp(1, 5);
        } else if (score is num) {
          _notas[fundamento] = score.toInt().clamp(1, 5);
        }

        final motivo = (row['motivo'] ?? '').toString();
        if (['Melhorando', 'Estável', 'Piorou'].contains(motivo)) {
          _tendencias[fundamento] = motivo;
        }

        _observacoesPorFundamento[fundamento]?.text =
            (row['observacao'] ?? '').toString();
      }

      if (mounted) setState(() {});
    } catch (_) {
      // Se não carregar histórico, mantém formulário disponível.
    }
  }

  void _limparFormulario({bool manterAtleta = false}) {
    _mensagemAtletaController.clear();
    _observacaoGeralController.clear();
    _pontoForteController.clear();
    _pontoMelhorarController.clear();
    _evolucaoGeral = 'Estável';
    _prioridade = 'Média';

    for (final fundamento in _fundamentos) {
      _notas[fundamento] = 3;
      _tendencias[fundamento] = 'Estável';
      _observacoesPorFundamento[fundamento]?.clear();
    }

    if (!manterAtleta) _selectedAthleteId = null;

    if (mounted) setState(() {});
  }

  int _mediaNotasArredondada() {
    if (_notas.isEmpty) return 3;
    final total = _notas.values.fold<int>(0, (sum, value) => sum + value);
    return (total / _notas.length).round().clamp(1, 5);
  }

  DateTime? _parseEventDate(dynamic value) {
    final raw = (value ?? '').toString().trim();
    if (raw.isEmpty) return null;

    try {
      final parts = raw.split('/');
      if (parts.length == 3) {
        return DateTime(
          int.parse(parts[2]),
          int.parse(parts[1]),
          int.parse(parts[0]),
        );
      }

      return DateTime.tryParse(raw);
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>> _buscarEventoBaseParaAvaliacaoMensal(
    String athleteId,
  ) async {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, 1);
    final end = DateTime(now.year, now.month + 1, 1);

    final checkinsResponse = await _supabase.from('checkins').select('''
event_id,
check_in_status,
events:event_id (
  id,
  event_name,
  event_type,
  event_date,
  event_time
)
''').eq('user_id', athleteId).inFilter('check_in_status', [
          'realizado',
          'realizado com sucesso',
          'checked_in',
          'checkin_realizado',
          'ok',
          'success',
          'completed',
          'done',
        ]);

    final checkins = List<Map<String, dynamic>>.from(checkinsResponse as List);

    final eventos = <Map<String, dynamic>>[];

    for (final checkin in checkins) {
      final rawEvent = checkin['events'];
      if (rawEvent == null || rawEvent is! Map) continue;

      final event = Map<String, dynamic>.from(rawEvent);
      final eventId = (event['id'] ?? checkin['event_id'] ?? '').toString();
      if (eventId.isEmpty) continue;

      final eventType =
          (event['event_type'] ?? '').toString().toLowerCase().trim();

      if (eventType != 'treino') continue;

      final eventDate = _parseEventDate(event['event_date']);
      if (eventDate == null) continue;

      if (eventDate.isBefore(start) || !eventDate.isBefore(end)) continue;

      eventos.add({
        'id': eventId,
        'event_name': (event['event_name'] ?? 'Avaliação mensal').toString(),
        'event_date': (event['event_date'] ?? '').toString(),
        'event_time': (event['event_time'] ?? '').toString(),
        'eventDate': eventDate,
      });
    }

    if (eventos.isEmpty) {
      throw Exception(
        'Não foi encontrado nenhum treino com check-in realizado neste mês para vincular a avaliação completa.',
      );
    }

    eventos.sort((a, b) {
      final ad = a['eventDate'] as DateTime;
      final bd = b['eventDate'] as DateTime;
      return bd.compareTo(ad);
    });

    return eventos.first;
  }

  Future<void> _salvarAvaliacaoCompleta() async {
    if (!_isLastFourDaysOfMonth) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'A avaliação completa só pode ser feita nos últimos 4 dias do mês ($_janelaAvaliacaoLabel).',
          ),
          backgroundColor: olympusWarning,
        ),
      );
      return;
    }

    final user = _supabase.auth.currentUser;
    final athlete = _selectedAthlete;

    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Usuário não autenticado.')),
      );
      return;
    }

    if (athlete == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecione uma atleta.')),
      );
      return;
    }

    if (_pontoMelhorarController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Informe o principal ponto a melhorar.')),
      );
      return;
    }

    setState(() => _saving = true);

    try {
      final athleteId = athlete.athleteId;
      final now = DateTime.now();
      final start = DateTime(now.year, now.month, 1);
      final end = DateTime(now.year, now.month + 1, 1);
      final eventoBase = await _buscarEventoBaseParaAvaliacaoMensal(athleteId);
      final eventId = (eventoBase['id'] ?? '').toString();
      final eventName =
          (eventoBase['event_name'] ?? 'Avaliação mensal').toString();
      final eventDate = (eventoBase['event_date'] ?? '').toString();

      if (eventId.isEmpty) {
        throw Exception(
            'Evento base inválido para salvar a avaliação completa.');
      }

      final existing = await _supabase
          .from('training_evaluations')
          .select('id')
          .eq('athlete_id', athleteId)
          .eq('tipo', 'completa')
          .gte('created_at', start.toIso8601String())
          .lt('created_at', end.toIso8601String());

      final existingIds = List<Map<String, dynamic>>.from(existing as List)
          .map((row) => (row['id'] ?? '').toString())
          .where((id) => id.isNotEmpty)
          .toList();

      if (existingIds.isNotEmpty) {
        await _supabase
            .from('training_evaluations')
            .delete()
            .inFilter('id', existingIds);
      }

      final rows = <Map<String, dynamic>>[];

      rows.add({
        'event_id': eventId,
        'event_name': eventName,
        'event_date': eventDate,
        'coach_id': user.id,
        'athlete_id': athleteId,
        'tipo': 'completa',
        'slot': 'resumo_mensal',
        'motivo':
            '$_evolucaoGeral | $_prioridade | ${_pontoForteController.text.trim()} | ${_pontoMelhorarController.text.trim()}',
        'fundamento': 'Resumo mensal',
        'observacao': _observacaoGeralController.text.trim(),
        'score': _mediaNotasArredondada(),
      });

      for (final fundamento in _fundamentos) {
        rows.add({
          'event_id': eventId,
          'event_name': eventName,
          'event_date': eventDate,
          'coach_id': user.id,
          'athlete_id': athleteId,
          'tipo': 'completa',
          'slot': 'completa_${fundamento.toLowerCase().replaceAll(' ', '_')}',
          'motivo': _tendencias[fundamento] ?? 'Estável',
          'fundamento': fundamento,
          'observacao':
              _observacoesPorFundamento[fundamento]?.text.trim() ?? '',
          'score': _notas[fundamento] ?? 3,
        });
      }

      await _supabase.from('training_evaluations').insert(rows);

      if (_sendToAthlete) {
        final message = _mensagemAtletaController.text.trim().isEmpty
            ? 'Sua avaliação completa mensal foi registrada. Evolução: $_evolucaoGeral. Prioridade: $_prioridade. Ponto principal: ${_pontoMelhorarController.text.trim()}.'
            : _mensagemAtletaController.text.trim();

        await sendEvaluationMessageToAthlete(
          supabase: _supabase,
          athleteId: athleteId,
          title: 'Avaliação completa mensal',
          body: message,
        );
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text('Avaliação completa salva para ${athlete.athleteName}.'),
          backgroundColor: olympusSuccess,
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao salvar avaliação completa: $e'),
          backgroundColor: olympusDanger,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _buildBackground() {
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

  Widget _buildWindowInfo(bool isMobile) {
    final opened = _isLastFourDaysOfMonth;

    return Container(
      padding: EdgeInsets.all(isMobile ? 12 : 14),
      decoration: BoxDecoration(
        color: opened
            ? olympusSuccess.withOpacity(0.12)
            : olympusWarning.withOpacity(0.14),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: opened
              ? olympusSuccess.withOpacity(0.28)
              : olympusWarning.withOpacity(0.35),
        ),
      ),
      child: Row(
        children: [
          Icon(
            opened ? Icons.check_circle_outline : Icons.lock_clock_rounded,
            color: opened ? olympusSuccess : olympusWarning,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              opened
                  ? 'Janela mensal aberta. Você pode preencher a avaliação completa.'
                  : 'Liberada apenas nos últimos 4 dias do mês ($_janelaAvaliacaoLabel).',
              style: TextStyle(
                color: opened ? olympusSuccess : olympusBlue,
                fontWeight: FontWeight.w900,
                fontSize: isMobile ? 12 : 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCard({
    required List<Widget> children,
    EdgeInsetsGeometry? padding,
  }) {
    return Container(
      width: double.infinity,
      padding: padding ?? const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: olympusCard.withOpacity(0.96),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: olympusBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }

  Widget _buildHeader(bool isMobile) {
    return _buildCard(
      padding: EdgeInsets.all(isMobile ? 14 : 16),
      children: [
        Text(
          'Avaliação completa mensal',
          style: TextStyle(
            color: olympusBlue,
            fontSize: isMobile ? 19 : 21,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Avaliação aprofundada por atleta, feita no fechamento do mês.',
          style: TextStyle(
            color: olympusMuted,
            fontSize: isMobile ? 12 : 13,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 12),
        _buildWindowInfo(isMobile),
      ],
    );
  }

  Widget _buildAthleteSelector(bool isMobile) {
    return _buildCard(
      padding: EdgeInsets.all(isMobile ? 14 : 16),
      children: [
        Text(
          'Atleta',
          style: TextStyle(
            color: olympusBlue,
            fontSize: isMobile ? 15 : 16,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          value: _selectedAthleteId,
          decoration: const InputDecoration(
            labelText: 'Selecionar atleta',
            border: OutlineInputBorder(),
          ),
          items: widget.athletes.map((athlete) {
            return DropdownMenuItem<String>(
              value: athlete.athleteId,
              child: Text(athlete.athleteName),
            );
          }).toList(),
          onChanged: _saving
              ? null
              : (value) async {
                  setState(() => _selectedAthleteId = value);
                  if (value != null) {
                    await _carregarAvaliacaoExistente(value);
                  }
                },
        ),
      ],
    );
  }

  Widget _buildSummaryCard(bool isMobile) {
    return _buildCard(
      padding: EdgeInsets.all(isMobile ? 14 : 16),
      children: [
        Text(
          'Resumo geral',
          style: TextStyle(
            color: olympusBlue,
            fontSize: isMobile ? 15 : 16,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          value: _evolucaoGeral,
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
          onChanged: _saving
              ? null
              : (value) {
                  if (value == null) return;
                  setState(() => _evolucaoGeral = value);
                },
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          value: _prioridade,
          decoration: const InputDecoration(
            labelText: 'Prioridade de acompanhamento',
            border: OutlineInputBorder(),
          ),
          items: const [
            DropdownMenuItem(value: 'Baixa', child: Text('Baixa')),
            DropdownMenuItem(value: 'Média', child: Text('Média')),
            DropdownMenuItem(value: 'Alta', child: Text('Alta')),
          ],
          onChanged: _saving
              ? null
              : (value) {
                  if (value == null) return;
                  setState(() => _prioridade = value);
                },
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _pontoForteController,
          enabled: !_saving,
          decoration: const InputDecoration(
            labelText: 'Ponto forte',
            hintText: 'Ex: liderança, saque, regularidade',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _pontoMelhorarController,
          enabled: !_saving,
          decoration: const InputDecoration(
            labelText: 'Principal ponto a melhorar',
            hintText: 'Ex: recepção, tomada de decisão',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _observacaoGeralController,
          enabled: !_saving,
          maxLines: 4,
          decoration: const InputDecoration(
            labelText: 'Observação geral',
            hintText: 'Resumo mensal da atleta',
            border: OutlineInputBorder(),
          ),
        ),
      ],
    );
  }

  Widget _buildFundamentoCard(String fundamento, bool isMobile) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: EdgeInsets.all(isMobile ? 12 : 14),
      decoration: BoxDecoration(
        color: olympusCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: olympusBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            fundamento,
            style: TextStyle(
              color: olympusText,
              fontSize: isMobile ? 14 : 15,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final narrow = constraints.maxWidth < 380;

              final notaField = DropdownButtonFormField<int>(
                value: _notas[fundamento],
                decoration: const InputDecoration(
                  labelText: 'Nota',
                  border: OutlineInputBorder(),
                ),
                items: List.generate(
                  5,
                  (index) => DropdownMenuItem<int>(
                    value: index + 1,
                    child: Text('${index + 1}'),
                  ),
                ),
                onChanged: _saving
                    ? null
                    : (value) {
                        if (value == null) return;
                        setState(() => _notas[fundamento] = value);
                      },
              );

              final tendenciaField = DropdownButtonFormField<String>(
                value: _tendencias[fundamento],
                decoration: const InputDecoration(
                  labelText: 'Tendência',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(
                    value: 'Melhorando',
                    child: Text('Melhorando'),
                  ),
                  DropdownMenuItem(value: 'Estável', child: Text('Estável')),
                  DropdownMenuItem(value: 'Piorou', child: Text('Piorou')),
                ],
                onChanged: _saving
                    ? null
                    : (value) {
                        if (value == null) return;
                        setState(() => _tendencias[fundamento] = value);
                      },
              );

              if (narrow) {
                return Column(
                  children: [
                    notaField,
                    const SizedBox(height: 10),
                    tendenciaField,
                  ],
                );
              }

              return Row(
                children: [
                  Expanded(child: notaField),
                  const SizedBox(width: 10),
                  Expanded(child: tendenciaField),
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _observacoesPorFundamento[fundamento],
            enabled: !_saving,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Observação do fundamento',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSendToAthleteCard(bool isMobile) {
    return _buildCard(
      padding: EdgeInsets.all(isMobile ? 14 : 16),
      children: [
        SwitchListTile(
          value: _sendToAthlete,
          contentPadding: EdgeInsets.zero,
          activeColor: olympusBlue,
          secondary: const Icon(
            Icons.send_outlined,
            color: olympusBlue,
          ),
          title: const Text(
            'Enviar para atleta',
            style: TextStyle(
              color: olympusBlue,
              fontWeight: FontWeight.w900,
            ),
          ),
          subtitle: const Text(
            'Ao salvar, a atleta receberá uma mensagem com o resumo mensal.',
            style: TextStyle(
              color: olympusMuted,
              fontWeight: FontWeight.w600,
            ),
          ),
          onChanged: _saving
              ? null
              : (value) {
                  setState(() => _sendToAthlete = value);
                },
        ),
        if (_sendToAthlete) ...[
          const SizedBox(height: 12),
          TextField(
            controller: _mensagemAtletaController,
            enabled: !_saving,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Mensagem para atleta',
              hintText:
                  'Ex: Parabéns pela evolução no saque. Para o próximo mês, o foco será recepção e tomada de decisão.',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildFundamentosSection(bool isMobile) {
    return _buildCard(
      padding: EdgeInsets.all(isMobile ? 14 : 16),
      children: [
        Text(
          'Fundamentos',
          style: TextStyle(
            color: olympusBlue,
            fontSize: isMobile ? 15 : 16,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Dê nota de 1 a 5 e registre a tendência de evolução.',
          style: TextStyle(
            color: olympusMuted,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 12),
        ..._fundamentos.map((item) => _buildFundamentoCard(item, isMobile)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = _isMobile(context);

    return Scaffold(
      backgroundColor: olympusBg,
      appBar: AppBar(
        title: const Text('Avaliação completa'),
        backgroundColor: olympusBlue,
        foregroundColor: Colors.white,
      ),
      body: Stack(
        children: [
          Positioned.fill(child: _buildBackground()),
          SafeArea(
            child: widget.athletes.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'Nenhuma atleta visível para avaliação completa.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  )
                : ListView(
                    padding: EdgeInsets.all(isMobile ? 12 : 16),
                    children: [
                      _buildHeader(isMobile),
                      const SizedBox(height: 14),
                      _buildAthleteSelector(isMobile),
                      const SizedBox(height: 14),
                      _buildSendToAthleteCard(isMobile),
                      const SizedBox(height: 14),
                      _buildSummaryCard(isMobile),
                      const SizedBox(height: 14),
                      _buildFundamentosSection(isMobile),
                      const SizedBox(height: 18),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _saving || !_isLastFourDaysOfMonth
                              ? null
                              : _salvarAvaliacaoCompleta,
                          icon: _saving
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      Colors.white,
                                    ),
                                  ),
                                )
                              : const Icon(Icons.save_outlined),
                          label: Text(
                            _saving
                                ? 'Salvando...'
                                : 'Salvar avaliação completa',
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: olympusBlue,
                            foregroundColor: Colors.white,
                            disabledBackgroundColor:
                                Colors.grey.withOpacity(0.35),
                            padding: const EdgeInsets.symmetric(vertical: 15),
                          ),
                        ),
                      ),
                      const SizedBox(height: 28),
                    ],
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
