import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'admin_competitions_page.dart';
import 'coach_training_sessions_page.dart';
import 'coach_ranking_page.dart';

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

  void _navigateToRanking() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const CoachRankingPage(),
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
                    icon: Icons.calendar_month_outlined,
                    title: 'Planejamento de treinos',
                    subtitle:
                        'Planejamento e avaliação rápida dos treinos marcados',
                    color: const Color(0xFF3B82F6),
                    onTap: _navigateToTrainingPlanner,
                  ),
                  _buildDashboardCard(
                    icon: Icons.assignment_turned_in_outlined,
                    title: 'Avaliação das atletas',
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

class CoachAthleteEvaluationsPage extends StatefulWidget {
  const CoachAthleteEvaluationsPage({super.key});

  @override
  State<CoachAthleteEvaluationsPage> createState() =>
      _CoachAthleteEvaluationsPageState();
}

class _CoachAthleteEvaluationsPageState
    extends State<CoachAthleteEvaluationsPage> {
  final List<AthleteEvaluationStatus> _athletes = [
    AthleteEvaluationStatus(
      athleteName: 'Maria',
      generalEvolution: 'Melhorando',
      mainFocus: 'Recepção',
      evaluationsSinceLastFull: 2,
      isPresent: true,
    ),
    AthleteEvaluationStatus(
      athleteName: 'Joana',
      generalEvolution: 'Estável',
      mainFocus: 'Saque',
      evaluationsSinceLastFull: 1,
      isPresent: true,
    ),
    AthleteEvaluationStatus(
      athleteName: 'Ana',
      generalEvolution: 'Precisa de atenção',
      mainFocus: 'Defesa',
      evaluationsSinceLastFull: 0,
      isPresent: true,
    ),
  ];

  static const Color olympusBlue = Color(0xFF1E3A5F);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Avaliação das atletas'),
        backgroundColor: olympusBlue,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFF7F3E8),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFE8DBB2)),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Regra ativa de avaliação',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF5C4721),
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  '2 avaliações rápidas seguidas + 1 avaliação completa obrigatória por atleta.',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF715C35),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              itemCount: _athletes.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final athlete = _athletes[index];
                return _AthleteEvaluationCard(
                  athlete: athlete,
                  onTap: () => _openEvaluationFlow(index),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openEvaluationFlow(int index) async {
    final athlete = _athletes[index];
    final requiresFull = athlete.requiresCompleteEvaluation;

    final result = await Navigator.push<EvaluationSubmissionResult>(
      context,
      MaterialPageRoute(
        builder: (_) => AthleteEvaluationFormPage(
          athleteName: athlete.athleteName,
          isCompleteMode: requiresFull,
          currentFocus: athlete.mainFocus,
        ),
      ),
    );

    if (result == null) return;

    setState(() {
      _athletes[index] = athlete.copyWith(
        generalEvolution: result.generalEvolution,
        mainFocus: result.mainFocus,
        evaluationsSinceLastFull:
            result.isComplete ? 0 : athlete.evaluationsSinceLastFull + 1,
      );
    });

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result.isComplete
              ? 'Avaliação completa salva para ${athlete.athleteName}.'
              : 'Avaliação rápida salva para ${athlete.athleteName}.',
        ),
      ),
    );
  }
}

class _AthleteEvaluationCard extends StatelessWidget {
  const _AthleteEvaluationCard({
    required this.athlete,
    required this.onTap,
  });

  final AthleteEvaluationStatus athlete;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final requiresComplete = athlete.requiresCompleteEvaluation;
    final chipColor =
        requiresComplete ? const Color(0xFFB45309) : const Color(0xFF2563EB);

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFE4EDF5)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 10,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: const Color(0xFF1E3A5F),
                child: Text(
                  athlete.athleteName.substring(0, 1),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      athlete.athleteName,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF17324D),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Evolução geral: ${athlete.generalEvolution}',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF53657B),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Principal foco: ${athlete.mainFocus}',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF6A7E94),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: chipColor.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        requiresComplete
                            ? 'Completa obrigatória'
                            : 'Avaliação rápida',
                        style: TextStyle(
                          color: chipColor,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              const Icon(Icons.arrow_forward_ios_rounded, size: 18),
            ],
          ),
        ),
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
  final TextEditingController _strengthController = TextEditingController();
  final TextEditingController _focusController = TextEditingController();
  final TextEditingController _generalNotesController = TextEditingController();

  String _generalEvolution = 'Melhorando';
  String _priority = 'Média';

  late final List<FundamentEvaluationModel> _fundamentals;

  @override
  void initState() {
    super.initState();
    _focusController.text = widget.currentFocus;

    _fundamentals = [
      FundamentEvaluationModel(name: 'Saque'),
      FundamentEvaluationModel(name: 'Recepção'),
      FundamentEvaluationModel(name: 'Toque'),
      FundamentEvaluationModel(name: 'Ataque'),
      FundamentEvaluationModel(name: 'Bloqueio'),
      FundamentEvaluationModel(name: 'Defesa'),
      FundamentEvaluationModel(name: 'Condicionamento'),
      FundamentEvaluationModel(name: 'Postura tática'),
    ];
  }

  @override
  void dispose() {
    _strengthController.dispose();
    _focusController.dispose();
    _generalNotesController.dispose();
    for (final item in _fundamentals) {
      item.notesController.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const olympusBlue = Color(0xFF1E3A5F);
    final pageTitle =
        widget.isCompleteMode ? 'Avaliação completa' : 'Avaliação rápida';

    return Scaffold(
      appBar: AppBar(
        title: Text('$pageTitle - ${widget.athleteName}'),
        backgroundColor: olympusBlue,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          if (widget.isCompleteMode)
            Container(
              padding: const EdgeInsets.all(14),
              margin: const EdgeInsets.only(bottom: 14),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF7E8),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFF1D38B)),
              ),
              child: const Text(
                'Avaliação completa obrigatória para esta atleta. O modo rápido foi bloqueado neste ciclo.',
                style: TextStyle(
                  color: Color(0xFF815A00),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          DropdownButtonFormField<String>(
            value: _generalEvolution,
            decoration: const InputDecoration(labelText: 'Evolução geral'),
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
            controller: _strengthController,
            decoration: const InputDecoration(
              labelText: 'Ponto forte',
              hintText: 'Ex: saque, liderança, defesa',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _focusController,
            decoration: const InputDecoration(
              labelText: 'Principal ponto a melhorar',
              hintText: 'Ex: recepção, posicionamento',
            ),
          ),
          const SizedBox(height: 12),
          if (widget.isCompleteMode) ...[
            DropdownButtonFormField<String>(
              value: _priority,
              decoration: const InputDecoration(labelText: 'Prioridade'),
              items: const [
                DropdownMenuItem(value: 'Baixa', child: Text('Baixa')),
                DropdownMenuItem(value: 'Média', child: Text('Média')),
                DropdownMenuItem(value: 'Alta', child: Text('Alta')),
              ],
              onChanged: (value) {
                if (value == null) return;
                setState(() => _priority = value);
              },
            ),
            const SizedBox(height: 16),
            const Text(
              'Fundamentos',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: Color(0xFF17324D),
              ),
            ),
            const SizedBox(height: 10),
            ..._fundamentals.map(_buildFundamentCard),
            const SizedBox(height: 12),
          ],
          TextField(
            controller: _generalNotesController,
            maxLines: widget.isCompleteMode ? 4 : 2,
            decoration: const InputDecoration(
              labelText: 'Observação do técnico',
              hintText: 'Resumo do treino para esta atleta',
            ),
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: _submit,
            icon: const Icon(Icons.save_outlined),
            label: Text(
              widget.isCompleteMode
                  ? 'Salvar avaliação completa'
                  : 'Salvar avaliação rápida',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFundamentCard(FundamentEvaluationModel item) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE4EDF5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            item.name,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              color: Color(0xFF17324D),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<int>(
                  value: item.score,
                  decoration: const InputDecoration(labelText: 'Nota'),
                  items: List.generate(
                    5,
                    (index) => DropdownMenuItem(
                      value: index + 1,
                      child: Text('${index + 1}'),
                    ),
                  ),
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() => item.score = value);
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: item.trend,
                  decoration: const InputDecoration(labelText: 'Tendência'),
                  items: const [
                    DropdownMenuItem(
                      value: 'Melhorando',
                      child: Text('Melhorando'),
                    ),
                    DropdownMenuItem(value: 'Estável', child: Text('Estável')),
                    DropdownMenuItem(value: 'Piorou', child: Text('Piorou')),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() => item.trend = value);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: item.notesController,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Observação',
              hintText: 'Observação curta deste fundamento',
            ),
          ),
        ],
      ),
    );
  }

  void _submit() {
    if (_focusController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Informe o principal ponto a melhorar.')),
      );
      return;
    }

    Navigator.pop(
      context,
      EvaluationSubmissionResult(
        isComplete: widget.isCompleteMode,
        generalEvolution: _generalEvolution,
        mainFocus: _focusController.text.trim(),
      ),
    );
  }
}

class AthleteEvaluationStatus {
  AthleteEvaluationStatus({
    required this.athleteName,
    required this.generalEvolution,
    required this.mainFocus,
    required this.evaluationsSinceLastFull,
    required this.isPresent,
  });

  final String athleteName;
  final String generalEvolution;
  final String mainFocus;
  final int evaluationsSinceLastFull;
  final bool isPresent;

  bool get requiresCompleteEvaluation => evaluationsSinceLastFull >= 2;

  AthleteEvaluationStatus copyWith({
    String? athleteName,
    String? generalEvolution,
    String? mainFocus,
    int? evaluationsSinceLastFull,
    bool? isPresent,
  }) {
    return AthleteEvaluationStatus(
      athleteName: athleteName ?? this.athleteName,
      generalEvolution: generalEvolution ?? this.generalEvolution,
      mainFocus: mainFocus ?? this.mainFocus,
      evaluationsSinceLastFull:
          evaluationsSinceLastFull ?? this.evaluationsSinceLastFull,
      isPresent: isPresent ?? this.isPresent,
    );
  }
}

class EvaluationSubmissionResult {
  EvaluationSubmissionResult({
    required this.isComplete,
    required this.generalEvolution,
    required this.mainFocus,
  });

  final bool isComplete;
  final String generalEvolution;
  final String mainFocus;
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
