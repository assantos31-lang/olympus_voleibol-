Map<String, dynamic> buildManualCheckinPayload({
  required String eventId,
  required String userId,
  required DateTime effectiveCheckInAt,
}) {
  return {
    'event_id': eventId,
    'user_id': userId,
    'check_in_status': 'realizado',
    'checked_in_at': effectiveCheckInAt.toUtc().toIso8601String(),
  };
}

DateTime? effectiveCheckInTime(Map<String, dynamic> row) {
  for (final field in const ['checked_in_at', 'created_at']) {
    final raw = (row[field] ?? '').toString().trim();
    final parsed = DateTime.tryParse(raw);
    if (parsed != null) return parsed.toLocal();
  }
  return null;
}

bool isCompletedCheckin(dynamic value) {
  return (value ?? '').toString().trim().toLowerCase() == 'realizado';
}

Set<String> completedCheckinUserIds(
  Iterable<Map<String, dynamic>> rows,
) {
  return rows
      .where((row) => isCompletedCheckin(row['check_in_status']))
      .map((row) => (row['user_id'] ?? '').toString())
      .where((id) => id.isNotEmpty)
      .toSet();
}
