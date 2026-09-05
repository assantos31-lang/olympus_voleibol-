import 'package:flutter_test/flutter_test.dart';
import 'package:olympus_voleibol/utils/checkin_ranking.dart';
import 'package:olympus_voleibol/utils/manual_checkin.dart';

void main() {
  final eventStart = DateTime(2026, 9, 5, 19);

  test('check-in normal aparece vinculado ao treino correto', () {
    final payload = buildManualCheckinPayload(
      eventId: 'treino-05-09',
      userId: 'joao',
      effectiveCheckInAt: DateTime(2026, 9, 5, 18, 55),
    );

    expect(payload['event_id'], 'treino-05-09');
    expect(
      isValidCheckinForRanking(
        eventStart,
        effectiveCheckInTime(payload)!,
      ),
      isTrue,
    );
  });

  test('check-in atrasado dentro da janela aparece e pontua', () {
    final effectiveTime = DateTime(2026, 9, 5, 19, 15);
    final scores = calculateCheckinRankingScores(
      eventStarts: {'treino': eventStart},
      records: [
        CheckinRankingRecord(
          userId: 'joao',
          eventId: 'treino',
          checkedInAt: effectiveTime,
        ),
      ],
    );

    expect(scores['joao']!.presenceCount, 1);
    expect(scores['joao']!.totalPoints, 2);
  });

  test('hora efetiva prevalece sobre o momento posterior de cadastro', () {
    final row = {
      ...buildManualCheckinPayload(
        eventId: 'treino',
        userId: 'pedro',
        effectiveCheckInAt: DateTime(2026, 9, 5, 18, 58),
      ),
      'created_at': DateTime(2026, 9, 5, 21, 30).toUtc().toIso8601String(),
    };

    final effective = effectiveCheckInTime(row)!;
    expect(effective.hour, 18);
    expect(effective.minute, 58);
    expect(isValidCheckinForRanking(eventStart, effective), isTrue);
  });

  test('lancamento no dia seguinte permanece no treino do dia anterior', () {
    final payload = buildManualCheckinPayload(
      eventId: 'treino-04-09',
      userId: 'ana',
      effectiveCheckInAt: DateTime(2026, 9, 4, 19, 5),
    );

    expect(payload['event_id'], 'treino-04-09');
    expect(effectiveCheckInTime(payload)!.day, 4);
    expect(payload, isNot(contains('created_at')));
  });

  test('payload usa checked_in_at em UTC sem sobrescrever created_at', () {
    final payload = buildManualCheckinPayload(
      eventId: 'treino',
      userId: 'atleta',
      effectiveCheckInAt: DateTime(2026, 9, 5, 18, 58),
    );

    expect(payload['checked_in_at'], endsWith('Z'));
    expect(payload['check_in_status'], 'realizado');
    expect(payload, isNot(contains('created_at')));
  });

  test('lista aberta passa a exibir o atleta quando chega o registro', () {
    final rows = <Map<String, dynamic>>[
      {'user_id': 'outro', 'check_in_status': 'pendente'},
    ];
    expect(completedCheckinUserIds(rows), isNot(contains('joao')));

    rows.add(
      buildManualCheckinPayload(
        eventId: 'treino',
        userId: 'joao',
        effectiveCheckInAt: DateTime(2026, 9, 5, 18, 58),
      ),
    );

    expect(completedCheckinUserIds(rows), contains('joao'));
  });
}
