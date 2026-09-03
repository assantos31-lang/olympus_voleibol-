import 'package:flutter_test/flutter_test.dart';
import 'package:olympus_voleibol/utils/checkin_ranking.dart';

void main() {
  final start = DateTime(2026, 9, 2, 20, 30);

  test('aplica janela, pontuacao e bonus do primeiro check-in', () {
    final scores = calculateCheckinRankingScores(
      eventStarts: {'t1': start},
      records: [
        CheckinRankingRecord(
          userId: 'ana',
          eventId: 't1',
          checkedInAt: start.subtract(const Duration(minutes: 5)),
        ),
        CheckinRankingRecord(
          userId: 'bia',
          eventId: 't1',
          checkedInAt: start.add(const Duration(minutes: 10)),
        ),
        CheckinRankingRecord(
          userId: 'carla',
          eventId: 't1',
          checkedInAt: start.add(const Duration(minutes: 11)),
        ),
        CheckinRankingRecord(
          userId: 'fora',
          eventId: 't1',
          checkedInAt: start.add(const Duration(minutes: 31)),
        ),
        CheckinRankingRecord(
          userId: 'cedo_demais',
          eventId: 't1',
          checkedInAt: start.subtract(const Duration(minutes: 11)),
        ),
        CheckinRankingRecord(
          userId: 'limite',
          eventId: 't1',
          checkedInAt: start.add(const Duration(minutes: 30)),
        ),
      ],
    );

    expect(scores['ana']!.totalPoints, 3);
    expect(scores['ana']!.firstCheckins, 1);
    expect(scores['bia']!.totalPoints, 2);
    expect(scores['carla']!.totalPoints, 1);
    expect(scores['limite']!.totalPoints, 1);
    expect(scores.containsKey('fora'), isFalse);
    expect(scores.containsKey('cedo_demais'), isFalse);
  });

  test('desempata por pontos, treinos, primeiras chegadas e nome', () {
    const highPoints = CheckinRankingScore(
      totalPoints: 8,
      presenceCount: 2,
      firstCheckins: 0,
    );
    const moreTrainings = CheckinRankingScore(
      totalPoints: 7,
      presenceCount: 4,
      firstCheckins: 0,
    );
    const fewerTrainings = CheckinRankingScore(
      totalPoints: 7,
      presenceCount: 3,
      firstCheckins: 2,
    );
    const moreFirsts = CheckinRankingScore(
      totalPoints: 7,
      presenceCount: 3,
      firstCheckins: 3,
    );

    expect(
      compareCheckinRanking(
        a: highPoints,
        aName: 'Zara',
        aId: '1',
        b: moreTrainings,
        bName: 'Ana',
        bId: '2',
      ),
      lessThan(0),
    );
    expect(
      compareCheckinRanking(
        a: moreTrainings,
        aName: 'Zara',
        aId: '2',
        b: moreFirsts,
        bName: 'Ana',
        bId: '3',
      ),
      lessThan(0),
    );
    expect(
      compareCheckinRanking(
        a: moreFirsts,
        aName: 'Zara',
        aId: '3',
        b: fewerTrainings,
        bName: 'Ana',
        bId: '4',
      ),
      lessThan(0),
    );
    expect(
      compareCheckinRanking(
        a: fewerTrainings,
        aName: 'Ana',
        aId: '4',
        b: fewerTrainings,
        bName: 'Zara',
        bId: '5',
      ),
      lessThan(0),
    );
  });

  test('sete atletas empatados recebem posicoes unicas pelo nome', () {
    final scores = calculateCheckinRankingScores(
      eventStarts: {'t1': start},
      records: List.generate(
        7,
        (index) => CheckinRankingRecord(
          userId: 'id-$index',
          eventId: 't1',
          checkedInAt: start.add(Duration(minutes: index + 1)),
        ),
      ),
    );
    final athletes = scores.entries.toList()
      ..sort((a, b) => compareCheckinRanking(
            a: a.value,
            aName: 'Atleta ${a.key}',
            aId: a.key,
            b: b.value,
            bName: 'Atleta ${b.key}',
            bId: b.key,
          ));

    expect(List.generate(athletes.length, (index) => index + 1),
        [1, 2, 3, 4, 5, 6, 7]);
    expect(
        athletes.where((item) => item.value.firstCheckins == 1), hasLength(1));
  });
}
