import 'package:flutter_test/flutter_test.dart';
import 'package:olympus_voleibol/utils/dense_ranking.dart';

void main() {
  test('empates não pulam a próxima posição', () {
    expect(
      buildDenseRankingPositions([9, 9, 9, 8, 8, 7]),
      [1, 1, 1, 2, 2, 3],
    );
  });

  test('ranking vazio não cria posições', () {
    expect(buildDenseRankingPositions(const []), isEmpty);
  });
}
