import 'package:flutter_test/flutter_test.dart';
import 'package:olympus_voleibol/utils/monthly_ranking.dart';

Map<String, dynamic> athlete(
  String id,
  String name,
  int points,
  String checkIn,
) {
  return {
    'id': id,
    'first_name': name,
    'total_points': points,
    'earliest_checkin_at': checkIn,
  };
}

void main() {
  test('pontuacao permanece acima do horario do check-in', () {
    final ranking = orderMonthlyRanking([
      athlete('ana', 'Ana', 130, '2026-09-02T17:50:00-03:00'),
      athlete('joao', 'João', 150, '2026-09-02T18:10:00-03:00'),
    ]);

    expect(ranking.map((row) => row['first_name']), ['João', 'Ana']);
  });

  test('check-in mais cedo desempata somente a mesma pontuacao', () {
    final ranking = orderMonthlyRanking([
      athlete('joao', 'João', 100, '2026-09-02T18:10:00-03:00'),
      athlete('pedro', 'Pedro', 100, '2026-09-02T18:05:00-03:00'),
      athlete('carlos', 'Carlos', 80, '2026-09-02T18:02:00-03:00'),
      athlete('lucas', 'Lucas', 80, '2026-09-02T17:59:00-03:00'),
      athlete('marcos', 'Marcos', 60, '2026-09-02T17:50:00-03:00'),
    ]);

    expect(ranking.map((row) => row['first_name']), [
      'Pedro',
      'João',
      'Lucas',
      'Carlos',
      'Marcos',
    ]);
    expect(ranking.map((row) => row['ranking_position']), [1, 2, 3, 4, 5]);
  });

  test('ordem recebida do banco nao interfere', () {
    final input = [
      athlete('3', 'Carlos', 80, '2026-09-02T18:02:00-03:00'),
      athlete('1', 'João', 100, '2026-09-02T18:10:00-03:00'),
      athlete('5', 'Marcos', 60, '2026-09-02T17:50:00-03:00'),
      athlete('2', 'Pedro', 100, '2026-09-02T18:05:00-03:00'),
      athlete('4', 'Lucas', 80, '2026-09-02T17:59:00-03:00'),
    ];

    final forward = orderMonthlyRanking(input);
    final reversed = orderMonthlyRanking(input.reversed);

    expect(
      forward.map((row) => row['id']),
      reversed.map((row) => row['id']),
    );
  });

  test('id desempata pontuacao e timestamp identicos', () {
    final ranking = orderMonthlyRanking([
      athlete('b', 'Bianca', 100, '2026-09-02T18:05:00-03:00'),
      athlete('a', 'Amanda', 100, '2026-09-02T18:05:00-03:00'),
    ]);

    expect(ranking.map((row) => row['id']), ['a', 'b']);
    expect(ranking.map((row) => row['ranking_position']), [1, 2]);
  });

  test('timestamp completo e comparado como instante real', () {
    final ranking = orderMonthlyRanking([
      athlete('later', 'Depois', 100, '2026-09-02T21:10:00Z'),
      athlete('earlier', 'Antes', 100, '2026-09-02T18:05:00-03:00'),
    ]);

    expect(ranking.map((row) => row['id']), ['earlier', 'later']);
  });
}
