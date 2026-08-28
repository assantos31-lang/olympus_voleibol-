import 'dart:ui';

import 'package:flutter/material.dart';
import '../../theme/olympus_theme.dart';

class CoachTrainingCategoryDetailPage extends StatelessWidget {
  const CoachTrainingCategoryDetailPage({
    super.key,
    required this.category,
    required this.monthLabel,
    required this.rows,
  });

  final String category;
  final String monthLabel;
  final List<Map<String, dynamic>> rows;

  static const Color olympusBlue = Color(0xFF1E3A5F);
  static const Color olympusMuted = Color(0xFF53657B);
  static const Color olympusBorder = Color(0xFFE4EDF5);

  Color get color => switch (category) {
        'Fundamentos' => const Color(0xFF16A34A),
        'Tático' => const Color(0xFF7C3AED),
        'Físico' => const Color(0xFFF59E0B),
        _ => olympusBlue,
      };

  IconData get icon => switch (category) {
        'Fundamentos' => Icons.sports_volleyball_rounded,
        'Tático' => Icons.account_tree_rounded,
        'Físico' => Icons.fitness_center_rounded,
        _ => Icons.insights_rounded,
      };

  String _formatMinutes(int minutes) {
    final hours = minutes ~/ 60;
    final rest = minutes % 60;
    if (hours == 0) return '${rest}min';
    if (rest == 0) return '${hours}h';
    return '${hours}h ${rest}min';
  }

  List<String> _positionsFromType(String type) {
    if (category == 'Fundamentos' && type.contains(':')) {
      return type
          .split('|')
          .map((group) => group.split(':').first.trim())
          .where((position) => position.isNotEmpty)
          .toSet()
          .toList();
    }
    final match = RegExp(r'^Posições \[([^\]]+)\]').firstMatch(type);
    if (match != null) {
      return match
          .group(1)!
          .split(',')
          .map((position) => position.trim())
          .where((position) => position.isNotEmpty)
          .toList();
    }
    return const ['Todos'];
  }

  Map<String, List<String>> _activitiesFromType(String type) {
    if (category == 'Fundamentos' && type.contains(':')) {
      final result = <String, List<String>>{};
      for (final group in type.split('|')) {
        final separator = group.indexOf(':');
        if (separator <= 0) continue;
        final position = group.substring(0, separator).trim();
        result[position] = group
            .substring(separator + 1)
            .split(',')
            .map((item) => item.trim())
            .where((item) => item.isNotEmpty)
            .toList();
      }
      return result;
    }
    final activity = type.contains(' • ') ? type.split(' • ').last : type;
    return {
      for (final position in _positionsFromType(type)) position: [activity],
    };
  }

  List<_PositionSummary> get _summaries {
    const order = ['Atacantes', 'Levantadores(as)', 'Líberos', 'Todos'];
    final minutes = <String, int>{};
    final activities = <String, Set<String>>{};
    final blocks = <String, int>{};

    for (final row in rows) {
      final type = (row['type'] ?? '').toString();
      final total = (row['minutes'] as num?)?.round() ?? 0;
      final blockCount = (row['blocks'] as num?)?.round() ?? 0;
      final positions = _positionsFromType(type);
      final byPosition = _activitiesFromType(type);
      if (positions.isEmpty) continue;

      final base = total ~/ positions.length;
      var remainder = total % positions.length;
      for (final position in positions) {
        final share = base + (remainder > 0 ? 1 : 0);
        if (remainder > 0) remainder--;
        minutes[position] = (minutes[position] ?? 0) + share;
        blocks[position] = (blocks[position] ?? 0) + blockCount;
        activities.putIfAbsent(position, () => <String>{}).addAll(
              byPosition[position] ?? const <String>[],
            );
      }
    }

    final positions = minutes.keys.toList()
      ..sort((a, b) {
        final ai = order.indexOf(a);
        final bi = order.indexOf(b);
        if (ai < 0 && bi < 0) return a.compareTo(b);
        if (ai < 0) return 1;
        if (bi < 0) return -1;
        return ai.compareTo(bi);
      });
    return positions
        .map(
          (position) => _PositionSummary(
            position: position,
            minutes: minutes[position] ?? 0,
            blocks: blocks[position] ?? 0,
            activities: (activities[position] ?? {}).toList()..sort(),
          ),
        )
        .toList();
  }

  Widget _background() {
    return Stack(
      children: [
        Positioned.fill(
          child: OlympusBrandBackgroundImage(
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(color: olympusBlue),
          ),
        ),
        Positioned.fill(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 3, sigmaY: 3),
            child: Container(color: const Color(0xFF071A30).withOpacity(.78)),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final summaries = _summaries;
    final total = rows.fold<int>(
      0,
      (sum, row) => sum + ((row['minutes'] as num?)?.round() ?? 0),
    );

    return Scaffold(
      backgroundColor: olympusBlue,
      appBar: AppBar(
        title: Text(category),
        backgroundColor: olympusBlue,
        foregroundColor: Colors.white,
      ),
      body: Stack(
        children: [
          Positioned.fill(child: _background()),
          ListView(
            padding: const EdgeInsets.all(14),
            children: [
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [color.withOpacity(.95), color.withOpacity(.68)],
                  ),
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: color.withOpacity(.28),
                      blurRadius: 22,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      width: 54,
                      height: 54,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(.18),
                        borderRadius: BorderRadius.circular(17),
                      ),
                      child: Icon(icon, color: Colors.white, size: 29),
                    ),
                    const SizedBox(width: 13),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            monthLabel,
                            style: TextStyle(
                              color: Colors.white.withOpacity(.80),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            _formatMinutes(total),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 27,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      '${summaries.length} posições',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              if (summaries.isEmpty)
                _EmptyCard(color: color)
              else
                ...summaries.map((summary) {
                  final progress = total == 0 ? 0.0 : summary.minutes / total;
                  return Container(
                    margin: const EdgeInsets.only(bottom: 11),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(.96),
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: color.withOpacity(.22)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                summary.position,
                                style: const TextStyle(
                                  color: olympusBlue,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                            Text(
                              _formatMinutes(summary.minutes),
                              style: TextStyle(
                                color: color,
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(99),
                          child: LinearProgressIndicator(
                            value: progress.clamp(0, 1),
                            minHeight: 8,
                            backgroundColor: olympusBorder,
                            valueColor: AlwaysStoppedAnimation(color),
                          ),
                        ),
                        const SizedBox(height: 11),
                        Wrap(
                          spacing: 7,
                          runSpacing: 7,
                          children: summary.activities
                              .map(
                                (activity) => Chip(
                                  label: Text(activity),
                                  backgroundColor: color.withOpacity(.09),
                                  side:
                                      BorderSide(color: color.withOpacity(.18)),
                                  labelStyle: const TextStyle(
                                    color: olympusBlue,
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                      ],
                    ),
                  );
                }),
            ],
          ),
        ],
      ),
    );
  }
}

class _PositionSummary {
  const _PositionSummary({
    required this.position,
    required this.minutes,
    required this.blocks,
    required this.activities,
  });

  final String position;
  final int minutes;
  final int blocks;
  final List<String> activities;
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(.96),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: color.withOpacity(.22)),
      ),
      child: const Text(
        'Ainda não há dados nesta categoria para o mês selecionado.',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: CoachTrainingCategoryDetailPage.olympusMuted,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
