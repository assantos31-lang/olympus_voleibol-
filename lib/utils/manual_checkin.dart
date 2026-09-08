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

DateTime manualCheckinInitialDateTime(
  Map<String, dynamic> event, {
  DateTime? fallback,
}) {
  final eventStartAt = (event['event_start_at'] ?? '').toString().trim();
  final parsedEventStartAt = DateTime.tryParse(eventStartAt);
  if (parsedEventStartAt != null) return parsedEventStartAt.toLocal();

  final dateParts = (event['event_date'] ?? '').toString().trim().split('/');
  final timeParts = (event['event_time'] ?? '').toString().trim().split(':');
  if (dateParts.length == 3 && timeParts.length >= 2) {
    final day = int.tryParse(dateParts[0]);
    final month = int.tryParse(dateParts[1]);
    final year = int.tryParse(dateParts[2]);
    final hour = int.tryParse(timeParts[0]);
    final minute = int.tryParse(timeParts[1]);

    if (day != null &&
        month != null &&
        year != null &&
        hour != null &&
        minute != null) {
      return DateTime(year, month, day, hour, minute);
    }
  }

  return fallback ?? DateTime.now();
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
