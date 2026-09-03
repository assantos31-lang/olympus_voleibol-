import 'package:flutter_test/flutter_test.dart';
import 'package:olympus_voleibol/utils/monthly_ranking.dart';

void main() {
  test('aplica todos os desempates exibidos nas regras', () {
    final ranking = orderMonthlyRanking([
      {
        'id': 'd',
        'first_name': 'Daniela',
        'total_points': 8,
        'presence_count': 4,
        'first_checkins': 0,
      },
      {
        'id': 'b',
        'first_name': 'Bianca',
        'total_points': 10,
        'presence_count': 4,
        'first_checkins': 1,
      },
      {
        'id': 'a',
        'first_name': 'Amanda',
        'total_points': 10,
        'presence_count': 5,
        'first_checkins': 0,
      },
      {
        'id': 'c',
        'first_name': 'Carla',
        'total_points': 10,
        'presence_count': 4,
        'first_checkins': 2,
      },
    ]);

    expect(ranking.map((row) => row['first_name']), [
      'Amanda',
      'Carla',
      'Bianca',
      'Daniela',
    ]);
    expect(ranking.map((row) => row['ranking_position']), [1, 2, 3, 4]);
  });

  test('oito atletas com os mesmos números não aparecem todos em primeiro', () {
    final ranking = orderMonthlyRanking(
      List.generate(
        8,
        (index) => {
          'id': '$index',
          'first_name': 'Atleta ${index + 1}',
          'total_points': 0,
          'presence_count': 0,
          'first_checkins': 0,
        },
      ),
    );

    expect(
      ranking.map((row) => row['ranking_position']),
      [1, 2, 3, 4, 5, 6, 7, 8],
    );
  });
}
