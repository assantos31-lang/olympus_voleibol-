import 'package:flutter_test/flutter_test.dart';
import 'package:olympus_voleibol/utils/event_rows_paginator.dart';

void main() {
  test('busca todas as páginas e preserva o evento depois do limite de 1000',
      () async {
    const targetEventId = 'evento-treino-02-09-2026';
    final eventIds = List.generate(100, (index) => 'evento-$index');
    eventIds[99] = targetEventId;

    final sourceRows = <Map<String, dynamic>>[
      ...List.generate(
        1100,
        (index) => {
          'id': 'convocacao-${index.toString().padLeft(4, '0')}',
          'event_id': eventIds[index % 99],
          'status': 'accepted',
        },
      ),
      ...List.generate(
        17,
        (index) => {
          'id': 'zz-target-${index.toString().padLeft(2, '0')}',
          'event_id': targetEventId,
          'status': index < 11
              ? 'accepted'
              : index < 13
                  ? 'pending'
                  : 'rejected',
        },
      ),
    ]..sort((a, b) => (a['id'] as String).compareTo(b['id'] as String));

    var requests = 0;
    final rows = await fetchAllEventRows(
      eventIds: eventIds,
      batchSize: 100,
      pageSize: 1000,
      fetchPage: (batch, from, to) async {
        requests++;
        final filtered =
            sourceRows.where((row) => batch.contains(row['event_id'])).toList();
        if (from >= filtered.length) return <Map<String, dynamic>>[];
        final last = to < filtered.length ? to : filtered.length - 1;
        return filtered.sublist(from, last + 1);
      },
    );

    final targetRows =
        rows.where((row) => row['event_id'] == targetEventId).toList();
    expect(requests, 2);
    expect(rows, hasLength(1117));
    expect(targetRows, hasLength(17));
    expect(
        targetRows.where((row) => row['status'] == 'accepted'), hasLength(11));
    expect(targetRows.where((row) => row['status'] == 'pending'), hasLength(2));
    expect(
        targetRows.where((row) => row['status'] == 'rejected'), hasLength(4));
  });

  test('divide muitos eventos em lotes sem perder registros', () async {
    final eventIds = List.generate(205, (index) => 'evento-$index');
    final requestedBatches = <List<String>>[];

    final rows = await fetchAllEventRows(
      eventIds: eventIds,
      batchSize: 100,
      pageSize: 1000,
      fetchPage: (batch, from, to) async {
        requestedBatches.add(List<String>.from(batch));
        if (from > 0) return <Map<String, dynamic>>[];
        return batch.map((id) => {'id': 'row-$id', 'event_id': id}).toList();
      },
    );

    expect(requestedBatches.map((batch) => batch.length), [100, 100, 5]);
    expect(rows, hasLength(205));
    expect(rows.map((row) => row['event_id']).toSet(), eventIds.toSet());
  });
}
