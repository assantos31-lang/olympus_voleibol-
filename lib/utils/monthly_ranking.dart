int _asInt(dynamic value) => (value as num?)?.toInt() ?? 0;

/// Aplica exatamente os desempates exibidos na regra do aplicativo:
/// pontos, treinos validos, primeiras chegadas e nome.
///
/// Como o nome e o ultimo desempate, cada atleta recebe uma posicao ordinal
/// unica. Assim, atletas empatados em pontos nao ficam todos em 1º.
List<Map<String, dynamic>> orderMonthlyRanking(
  Iterable<Map<String, dynamic>> rows,
) {
  final ordered = rows.map(Map<String, dynamic>.from).toList()
    ..sort((a, b) {
      final points = _asInt(b['total_points']).compareTo(
        _asInt(a['total_points']),
      );
      if (points != 0) return points;

      final trainings = _asInt(b['presence_count']).compareTo(
        _asInt(a['presence_count']),
      );
      if (trainings != 0) return trainings;

      final firstArrivals = _asInt(b['first_checkins']).compareTo(
        _asInt(a['first_checkins']),
      );
      if (firstArrivals != 0) return firstArrivals;

      final aName = (a['first_name'] ?? a['full_name'] ?? '')
          .toString()
          .trim()
          .toLowerCase();
      final bName = (b['first_name'] ?? b['full_name'] ?? '')
          .toString()
          .trim()
          .toLowerCase();
      final name = aName.compareTo(bName);
      if (name != 0) return name;
      return (a['id'] ?? '').toString().compareTo((b['id'] ?? '').toString());
    });

  return List.generate(
    ordered.length,
    (index) => <String, dynamic>{
      ...ordered[index],
      'ranking_position': index + 1,
    },
  );
}
