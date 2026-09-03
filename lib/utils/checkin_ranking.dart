class CheckinRankingRecord {
  const CheckinRankingRecord({
    required this.userId,
    required this.eventId,
    required this.checkedInAt,
  });

  final String userId;
  final String eventId;
  final DateTime checkedInAt;
}

class CheckinRankingScore {
  const CheckinRankingScore({
    required this.totalPoints,
    required this.presenceCount,
    required this.firstCheckins,
  });

  final int totalPoints;
  final int presenceCount;
  final int firstCheckins;
}

bool isValidCheckinForRanking(DateTime eventStart, DateTime checkedInAt) {
  final difference = checkedInAt.difference(eventStart);
  return difference >= const Duration(minutes: -10) &&
      difference <= const Duration(minutes: 30);
}

/// Calcula a pontuacao conforme a regra exibida no aplicativo:
/// - check-in entre 10 minutos antes e 10 minutos depois: 2 pontos;
/// - check-in entre 10 e 30 minutos depois: 1 ponto;
/// - primeiro check-in valido de cada treino: 1 ponto extra.
Map<String, CheckinRankingScore> calculateCheckinRankingScores({
  required Map<String, DateTime> eventStarts,
  required Iterable<CheckinRankingRecord> records,
}) {
  final earliestByEventAndUser = <String, Map<String, DateTime>>{};

  for (final record in records) {
    final start = eventStarts[record.eventId];
    if (start == null || record.userId.isEmpty) continue;
    if (!isValidCheckinForRanking(start, record.checkedInAt)) {
      continue;
    }

    final byUser = earliestByEventAndUser.putIfAbsent(
      record.eventId,
      () => <String, DateTime>{},
    );
    final previous = byUser[record.userId];
    if (previous == null || record.checkedInAt.isBefore(previous)) {
      byUser[record.userId] = record.checkedInAt;
    }
  }

  final points = <String, int>{};
  final presences = <String, int>{};
  final firsts = <String, int>{};

  for (final event in earliestByEventAndUser.entries) {
    if (event.value.isEmpty) continue;
    final start = eventStarts[event.key]!;
    final ordered = event.value.entries.toList()
      ..sort((a, b) {
        final time = a.value.compareTo(b.value);
        return time != 0 ? time : a.key.compareTo(b.key);
      });

    for (final checkin in ordered) {
      final difference = checkin.value.difference(start);
      final basePoints = difference <= const Duration(minutes: 10) ? 2 : 1;
      points.update(checkin.key, (value) => value + basePoints,
          ifAbsent: () => basePoints);
      presences.update(checkin.key, (value) => value + 1, ifAbsent: () => 1);
    }

    final firstUserId = ordered.first.key;
    points.update(firstUserId, (value) => value + 1, ifAbsent: () => 1);
    firsts.update(firstUserId, (value) => value + 1, ifAbsent: () => 1);
  }

  return {
    for (final userId in presences.keys)
      userId: CheckinRankingScore(
        totalPoints: points[userId] ?? 0,
        presenceCount: presences[userId] ?? 0,
        firstCheckins: firsts[userId] ?? 0,
      ),
  };
}

int compareCheckinRanking({
  required CheckinRankingScore a,
  required String aName,
  required String aId,
  required CheckinRankingScore b,
  required String bName,
  required String bId,
}) {
  final points = b.totalPoints.compareTo(a.totalPoints);
  if (points != 0) return points;
  final presences = b.presenceCount.compareTo(a.presenceCount);
  if (presences != 0) return presences;
  final firsts = b.firstCheckins.compareTo(a.firstCheckins);
  if (firsts != 0) return firsts;
  final name = aName.trim().toLowerCase().compareTo(bName.trim().toLowerCase());
  return name != 0 ? name : aId.compareTo(bId);
}
