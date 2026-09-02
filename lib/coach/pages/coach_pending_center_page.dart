import 'dart:ui';

import 'package:flutter/material.dart';
import '../../theme/olympus_theme.dart';

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


  int get _total =>
      pendingEvaluationsCount + unplannedTrainingsCount + unreadMessagesCount;

  Widget _background() {
    return Stack(
      fit: StackFit.expand,
      children: [
        OlympusBrandBackgroundImage(
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
                        Icon(
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
