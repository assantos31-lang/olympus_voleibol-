int _asInt(dynamic value) => (value as num?)?.toInt() ?? 0;

DateTime? _asDateTime(dynamic value) {
  if (value == null) return null;
  final parsed = DateTime.tryParse(value.toString().trim());
  return parsed?.toUtc();
}

/// Ordena pela pontuacao acumulada e usa o primeiro check-in real do mes
/// somente para desempatar atletas com a mesma pontuacao.
///
/// O id e o ultimo criterio para garantir uma ordem deterministica em empate
/// absoluto. Cada atleta recebe uma posicao ordinal unica.
List<Map<String, dynamic>> orderMonthlyRanking(
  Iterable<Map<String, dynamic>> rows,
) {
  final ordered = rows.map(Map<String, dynamic>.from).toList()
    ..sort((a, b) {
      final points = _asInt(b['total_points']).compareTo(
        _asInt(a['total_points']),
      );
      if (points != 0) return points;

      final aCheckIn = _asDateTime(a['earliest_checkin_at']);
      final bCheckIn = _asDateTime(b['earliest_checkin_at']);
      if (aCheckIn != null && bCheckIn != null) {
        final checkIn = aCheckIn.compareTo(bCheckIn);
        if (checkIn != 0) return checkIn;
      } else if (aCheckIn != null) {
        return -1;
      } else if (bCheckIn != null) {
        return 1;
      }

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
