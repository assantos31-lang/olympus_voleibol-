import 'dart:ui';

import 'package:flutter/material.dart';

import 'coach_athlete_evaluations_page.dart';
import '../../pages/coach_received_evaluations_page.dart';
import 'coach_training_sessions_page.dart';

class CoachEvaluationsHubPage extends StatelessWidget {
  const CoachEvaluationsHubPage({
    super.key,
    this.pendingEvaluationsCount = 0,
    this.receivedEvaluationsCount = 0,
  });

  final int pendingEvaluationsCount;
  final int receivedEvaluationsCount;

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
                  _optionCard(
                    context: context,
                    icon: Icons.rate_review_outlined,
                    title: 'Avaliações Recebidas',
                    subtitle: 'Feedbacks liberados pelo administrador',
                    color: const Color(0xFFD4AF37),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const CoachReceivedEvaluationsPage(),
                        ),
                      );
                    },
                    badgeCount: receivedEvaluationsCount > 0
                        ? receivedEvaluationsCount
                        : null,
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
