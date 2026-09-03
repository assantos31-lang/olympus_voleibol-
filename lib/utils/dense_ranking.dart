/// Calcula posições sem saltos para pontuações já ordenadas do maior para o
/// menor. Exemplo: 9, 9, 9, 8 resulta em 1º, 1º, 1º, 2º.
List<int> buildDenseRankingPositions(Iterable<int> scores) {
  int? previousScore;
  var position = 0;
  final positions = <int>[];

  for (final score in scores) {
    if (previousScore == null || score != previousScore) {
      position += 1;
      previousScore = score;
    }
    positions.add(position);
  }

  return positions;
}
