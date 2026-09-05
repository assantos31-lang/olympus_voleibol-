import 'package:flutter_test/flutter_test.dart';
import 'package:olympus_voleibol/utils/checkin_ranking.dart';

void main() {
  final start = DateTime(2026, 9, 5, 19);

  test('mantem a formula atual, a janela e o bonus do primeiro check-in', () {
    final scores = calculateCheckinRankingScores(
      eventStarts: {'t1': start},
      records: [
        CheckinRankingRecord(
          userId: 'normal',
          eventId: 't1',
          checkedInAt: DateTime(2026, 9, 5, 18, 55),
        ),
        CheckinRankingRecord(
          userId: 'atrasado',
          eventId: 't1',
          checkedInAt: DateTime(2026, 9, 5, 19, 15),
        ),
        CheckinRankingRecord(
          userId: 'limite',
          eventId: 't1',
          checkedInAt: DateTime(2026, 9, 5, 19, 30),
        ),
        CheckinRankingRecord(
          userId: 'fora',
          eventId: 't1',
          checkedInAt: DateTime(2026, 9, 5, 19, 31),
        ),
      ],
    );

    expect(scores['normal']!.totalPoints, 3);
    expect(scores['normal']!.firstCheckins, 1);
    expect(scores['atrasado']!.totalPoints, 1);
    expect(scores['limite']!.totalPoints, 1);
    expect(scores.containsKey('fora'), isFalse);
  });

  test('mais pontos continuam acima mesmo com check-in posterior', () {
    final laterWithMorePoints = CheckinRankingScore(
      totalPoints: 100,
      presenceCount: 1,
      firstCheckins: 0,
      earliestCheckInAt: DateTime(2026, 9, 5, 18, 10),
    );
    final earlierWithFewerPoints = CheckinRankingScore(
      totalPoints: 80,
      presenceCount: 1,
      firstCheckins: 0,
      earliestCheckInAt: DateTime(2026, 9, 5, 17, 50),
    );

    expect(
      compareCheckinRanking(
        a: laterWithMorePoints,
        aId: 'a',
        b: earlierWithFewerPoints,
        bId: 'b',
      ),
      lessThan(0),
    );
  });

  test('mesma pontuacao desempata pelo check-in mais cedo e depois pelo id', () {
    final earlier = CheckinRankingScore(
      totalPoints: 100,
      presenceCount: 1,
      firstCheckins: 0,
      earliestCheckInAt: DateTime(2026, 9, 5, 18, 5),
    );
    final later = CheckinRankingScore(
      totalPoints: 100,
      presenceCount: 99,
      firstCheckins: 99,
      earliestCheckInAt: DateTime(2026, 9, 5, 18, 10),
    );

    expect(
      compareCheckinRanking(a: earlier, aId: 'z', b: later, bId: 'a'),
      lessThan(0),
    );
    expect(
      compareCheckinRanking(a: earlier, aId: 'a', b: earlier, bId: 'b'),
      lessThan(0),
    );
  });
}
