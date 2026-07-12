import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class TrainingPlanReadonlySheet {
  static const Color olympusBlue = Color(0xFF1E3A5F);
  static const Color olympusGold = Color(0xFFD4AF37);
  static const Color olympusMuted = Color(0xFF53657B);

  static Future<void> show(
    BuildContext context, {
    required Map<String, dynamic> event,
    String emptyMessage = 'Nenhum planejamento vinculado a este treino.',
  }) async {
    final eventId = event['id']?.toString();
    if (eventId == null || eventId.isEmpty) return;

    final supabase = Supabase.instance.client;

    final blocksResponse = await supabase
        .from('training_plan_blocks')
        .select(
          'id, event_id, coach_id, category, type, start_time, end_time, observation, position, updated_at',
        )
        .eq('event_id', eventId)
        .order('position', ascending: true);

    dynamic notesResponse = const <dynamic>[];
    try {
      notesResponse = await supabase
          .from('training_plan_notes')
          .select('event_id, coach_id, notes, updated_at')
          .eq('event_id', eventId);
    } catch (_) {
      notesResponse = const <dynamic>[];
    }

    final blocks = List<Map<String, dynamic>>.from(blocksResponse as List);
    final notes = List<Map<String, dynamic>>.from(notesResponse as List);

    final coachIds = <String>{};
    for (final block in blocks) {
      final coachId = (block['coach_id'] ?? '').toString();
      if (coachId.isNotEmpty) coachIds.add(coachId);
    }
    for (final note in notes) {
      final coachId = (note['coach_id'] ?? '').toString();
      if (coachId.isNotEmpty) coachIds.add(coachId);
    }

    final profilesById = <String, Map<String, dynamic>>{};
    if (coachIds.isNotEmpty) {
      final profilesResponse = await supabase
          .from('profiles')
          .select('id, full_name, avatar_url')
          .inFilter('id', coachIds.toList());

      for (final profile
          in List<Map<String, dynamic>>.from(profilesResponse as List)) {
        final id = (profile['id'] ?? '').toString();
        if (id.isNotEmpty) profilesById[id] = profile;
      }
    }

    final blocksByCoach = <String, List<Map<String, dynamic>>>{};
    final notesByCoach = <String, Map<String, dynamic>>{};

    for (final block in blocks) {
      final coachId = (block['coach_id'] ?? '').toString();
      if (coachId.isEmpty) continue;
      blocksByCoach.putIfAbsent(coachId, () => []);
      blocksByCoach[coachId]!.add(block);
    }

    for (final note in notes) {
      final coachId = (note['coach_id'] ?? '').toString();
      if (coachId.isNotEmpty) notesByCoach[coachId] = note;
    }

    final allCoachIds = <String>{
      ...blocksByCoach.keys,
      ...notesByCoach.keys,
    }.toList();

    allCoachIds.sort((a, b) {
      final nameA = (profilesById[a]?['full_name'] ?? 'Técnico').toString();
      final nameB = (profilesById[b]?['full_name'] ?? 'Técnico').toString();
      return nameA.compareTo(nameB);
    });

    if (!context.mounted) return;

    if (allCoachIds.isEmpty) {
      await _showEmpty(context, event: event, emptyMessage: emptyMessage);
      return;
    }

    await _showLoaded(
      context,
      event: event,
      allCoachIds: allCoachIds,
      profilesById: profilesById,
      blocksByCoach: blocksByCoach,
      notesByCoach: notesByCoach,
    );
  }

  static Future<void> _showEmpty(
    BuildContext context, {
    required Map<String, dynamic> event,
    required String emptyMessage,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return SafeArea(
          child: Container(
            margin: const EdgeInsets.all(12),
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(26),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.18),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _handle(),
                const SizedBox(height: 16),
                _title(event),
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: olympusGold.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: olympusGold.withOpacity(0.28)),
                  ),
                  child: Text(
                    emptyMessage,
                    style: const TextStyle(
                      color: olympusBlue,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.pop(context),
                    style: FilledButton.styleFrom(
                      backgroundColor: olympusBlue,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: const Text('Fechar'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  static Future<void> _showLoaded(
    BuildContext context, {
    required Map<String, dynamic> event,
    required List<String> allCoachIds,
    required Map<String, Map<String, dynamic>> profilesById,
    required Map<String, List<Map<String, dynamic>>> blocksByCoach,
    required Map<String, Map<String, dynamic>> notesByCoach,
  }) {
    var selectedCoachId = allCoachIds.first;

    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final selectedBlocks = List<Map<String, dynamic>>.from(
              blocksByCoach[selectedCoachId] ?? const [],
            );
            final selectedProfile = profilesById[selectedCoachId];
            final coachName =
                (selectedProfile?['full_name'] ?? 'Técnico').toString();
            final notesText =
                (notesByCoach[selectedCoachId]?['notes'] ?? '').toString();
            final totalMinutes = selectedBlocks.fold<int>(
              0,
              (sum, block) => sum + _blockMinutes(block),
            );

            return SafeArea(
              child: Container(
                margin: const EdgeInsets.all(10),
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.88,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(26),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.20),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _handle(),
                    const SizedBox(height: 16),
                    _title(event),
                    const SizedBox(height: 12),
                    if (allCoachIds.length > 1) ...[
                      DropdownButtonFormField<String>(
                        value: selectedCoachId,
                        isExpanded: true,
                        decoration: InputDecoration(
                          labelText: 'Treinador',
                          prefixIcon: const Icon(
                            Icons.sports_rounded,
                            color: olympusGold,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        items: allCoachIds.map((coachId) {
                          final name =
                              (profilesById[coachId]?['full_name'] ?? 'Técnico')
                                  .toString();
                          return DropdownMenuItem<String>(
                            value: coachId,
                            child: Text(
                              name,
                              overflow: TextOverflow.ellipsis,
                            ),
                          );
                        }).toList(),
                        onChanged: (value) {
                          if (value == null) return;
                          setModalState(() => selectedCoachId = value);
                        },
                      ),
                      const SizedBox(height: 12),
                    ],
                    _coachSummary(
                      coachName: coachName,
                      blockCount: selectedBlocks.length,
                      totalMinutes: totalMinutes,
                    ),
                    if (notesText.trim().isNotEmpty) ...[
                      const SizedBox(height: 10),
                      _notes(notesText),
                    ],
                    const SizedBox(height: 14),
                    if (selectedBlocks.isEmpty)
                      const Text(
                        'Nenhum bloco cadastrado para este treinador.',
                        style: TextStyle(
                          color: olympusMuted,
                          fontWeight: FontWeight.w700,
                        ),
                      )
                    else
                      Flexible(
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: selectedBlocks.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            return _blockCard(selectedBlocks[index], index);
                          },
                        ),
                      ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () => Navigator.pop(context),
                        style: FilledButton.styleFrom(
                          backgroundColor: olympusBlue,
                          padding: const EdgeInsets.symmetric(vertical: 13),
                        ),
                        child: const Text('Fechar'),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  static Widget _handle() {
    return Center(
      child: Container(
        width: 44,
        height: 4,
        decoration: BoxDecoration(
          color: Colors.grey.shade300,
          borderRadius: BorderRadius.circular(999),
        ),
      ),
    );
  }

  static Widget _title(Map<String, dynamic> event) {
    final name = (event['event_name'] ?? 'Treino').toString();
    final date = (event['event_date'] ?? '').toString();
    final time = (event['event_time'] ?? '').toString();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Planejamento do treino',
          style: TextStyle(
            color: olympusBlue,
            fontSize: 20,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          [name, date, time]
              .where((item) => item.trim().isNotEmpty)
              .join(' • '),
          style: const TextStyle(
            color: olympusMuted,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  static Widget _coachSummary({
    required String coachName,
    required int blockCount,
    required int totalMinutes,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: olympusBlue.withOpacity(0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: olympusBlue.withOpacity(0.12)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: olympusBlue.withOpacity(0.12),
            child: Text(
              coachName.trim().isNotEmpty
                  ? coachName.trim().substring(0, 1).toUpperCase()
                  : 'T',
              style: const TextStyle(
                color: olympusBlue,
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
                  coachName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: olympusBlue,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$blockCount bloco${blockCount == 1 ? '' : 's'} • ${_formatDuration(totalMinutes)}',
                  style: const TextStyle(
                    color: olympusMuted,
                    fontSize: 12,
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

  static Widget _notes(String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: olympusGold.withOpacity(0.09),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: olympusGold.withOpacity(0.22)),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: olympusBlue,
          fontSize: 13,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  static Widget _blockCard(Map<String, dynamic> block, int index) {
    final category = (block['category'] ?? 'Bloco').toString();
    final type = (block['type'] ?? '').toString();
    final start = _normalizeTime(block['start_time']);
    final end = _normalizeTime(block['end_time']);
    final observation = (block['observation'] ?? '').toString().trim();
    final minutes = _blockMinutes(block);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE4EDF5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: olympusGold.withOpacity(0.16),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${index + 1}',
                  style: const TextStyle(
                    color: olympusBlue,
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
                      type.isEmpty ? category : type,
                      style: const TextStyle(
                        color: olympusBlue,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '$category • $start às $end • ${_formatDuration(minutes)}',
                      style: const TextStyle(
                        color: olympusMuted,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (observation.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              observation,
              style: const TextStyle(
                color: Color(0xFF334155),
                height: 1.28,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }

  static int _blockMinutes(Map<String, dynamic> block) {
    final start = _parseTime(block['start_time']);
    final end = _parseTime(block['end_time']);
    if (start == null || end == null || !end.isAfter(start)) return 0;
    return end.difference(start).inMinutes;
  }

  static DateTime? _parseTime(dynamic value) {
    final raw = (value ?? '').toString().trim();
    final parts = raw.split(':');
    if (parts.length < 2) return null;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return null;
    return DateTime(2000, 1, 1, hour, minute);
  }

  static String _normalizeTime(dynamic value) {
    final raw = (value ?? '').toString().trim();
    final parts = raw.split(':');
    if (parts.length >= 2) {
      final h = int.tryParse(parts[0]);
      final m = int.tryParse(parts[1]);
      if (h != null && m != null) {
        return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
      }
    }
    return raw.isEmpty ? '--:--' : raw;
  }

  static String _formatDuration(int minutes) {
    if (minutes <= 0) return '0min';
    final h = minutes ~/ 60;
    final m = minutes % 60;
    if (h == 0) return '${m}min';
    if (m == 0) return '${h}h';
    return '${h}h ${m}min';
  }
}
