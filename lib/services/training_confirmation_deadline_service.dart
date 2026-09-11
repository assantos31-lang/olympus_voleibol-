import 'package:supabase_flutter/supabase_flutter.dart';

import 'organization_context_service.dart';

const String trainingConfirmationDeadlineExpiredMessage =
    'O prazo para confirmar sua presença neste treino expirou. '
    'Você não deverá comparecer ao treino.';

const List<String> confirmationDeadlineEventTypes = [
  'treino',
  'amistoso',
  'campeonato',
];

String confirmationDeadlineEventLabel(String eventType) {
  switch (eventType.trim().toLowerCase()) {
    case 'amistoso':
      return 'amistoso';
    case 'campeonato':
      return 'campeonato';
    default:
      return 'treino';
  }
}

String eventConfirmationDeadlineExpiredMessage(Map<String, dynamic> event) {
  final label = confirmationDeadlineEventLabel(
    (event['event_type'] ?? '').toString(),
  );
  return 'O prazo para confirmar sua presença neste $label expirou. '
      'Você não deverá comparecer ao $label.';
}

class TrainingConfirmationDeadlineSettings {
  const TrainingConfirmationDeadlineSettings({
    required this.enabled,
    required this.hoursBefore,
  });

  const TrainingConfirmationDeadlineSettings.disabled()
      : enabled = false,
        hoursBefore = 3;

  final bool enabled;
  final int hoursBefore;

  factory TrainingConfirmationDeadlineSettings.fromValue(dynamic value) {
    if (value is! Map) {
      return const TrainingConfirmationDeadlineSettings.disabled();
    }
    final rawHours = value['hours_before'];
    final parsedHours = rawHours is num
        ? rawHours.toInt()
        : int.tryParse(rawHours?.toString() ?? '');
    return TrainingConfirmationDeadlineSettings(
      enabled: value['enabled'] == true,
      hoursBefore: (parsedHours ?? 3).clamp(1, 168),
    );
  }

  Map<String, dynamic> toValue() => {
        'enabled': enabled,
        'hours_before': hoursBefore,
      };
}

enum TrainingConfirmationState {
  notApplicable,
  confirmed,
  canConfirm,
  deadlineExpired,
}

DateTime? trainingEventDateTime(Map<String, dynamic> event) {
  final eventStartAt = (event['event_start_at'] ?? '').toString().trim();
  final parsedStartAt = DateTime.tryParse(eventStartAt);
  if (parsedStartAt != null) return parsedStartAt.toLocal();

  final dateParts = (event['event_date'] ?? '').toString().trim().split('/');
  final timeParts = (event['event_time'] ?? '').toString().trim().split(':');
  if (dateParts.length != 3 || timeParts.length < 2) return null;

  final day = int.tryParse(dateParts[0]);
  final month = int.tryParse(dateParts[1]);
  final year = int.tryParse(dateParts[2]);
  final hour = int.tryParse(timeParts[0]);
  final minute = int.tryParse(timeParts[1]);
  if (day == null ||
      month == null ||
      year == null ||
      hour == null ||
      minute == null) {
    return null;
  }
  return DateTime(year, month, day, hour, minute);
}

DateTime? trainingConfirmationDeadline(
  Map<String, dynamic> event,
  TrainingConfirmationDeadlineSettings settings,
) {
  if (!settings.enabled ||
      !confirmationDeadlineEventTypes.contains(
        (event['event_type'] ?? '').toString().trim().toLowerCase(),
      )) {
    return null;
  }
  return trainingEventDateTime(event)?.subtract(
    Duration(hours: settings.hoursBefore),
  );
}

TrainingConfirmationState trainingConfirmationState({
  required Map<String, dynamic> event,
  required String convocationStatus,
  required TrainingConfirmationDeadlineSettings settings,
  DateTime? now,
}) {
  if (!settings.enabled ||
      !confirmationDeadlineEventTypes.contains(
        (event['event_type'] ?? '').toString().trim().toLowerCase(),
      )) {
    return TrainingConfirmationState.notApplicable;
  }
  final normalizedStatus = convocationStatus.trim().toLowerCase();
  if (normalizedStatus == 'accepted') {
    return TrainingConfirmationState.confirmed;
  }
  if (normalizedStatus != 'pending' && normalizedStatus.isNotEmpty) {
    return TrainingConfirmationState.notApplicable;
  }
  final deadline = trainingConfirmationDeadline(event, settings);
  if (deadline == null) return TrainingConfirmationState.notApplicable;
  if (!(now ?? DateTime.now()).isBefore(deadline)) {
    return TrainingConfirmationState.deadlineExpired;
  }
  return TrainingConfirmationState.canConfirm;
}

String trainingConfirmationStateLabel(TrainingConfirmationState state) {
  switch (state) {
    case TrainingConfirmationState.confirmed:
      return 'Presença confirmada';
    case TrainingConfirmationState.canConfirm:
      return 'Ainda pode confirmar';
    case TrainingConfirmationState.deadlineExpired:
      return 'Não confirmou dentro do prazo';
    case TrainingConfirmationState.notApplicable:
      return '';
  }
}

class TrainingConfirmationDeadlineService {
  TrainingConfirmationDeadlineService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  static const String settingsKey = 'training_confirmation_deadline';
  static const Map<String, String> settingsKeys = {
    'treino': settingsKey,
    'amistoso': 'friendly_confirmation_deadline',
    'campeonato': 'championship_confirmation_deadline',
  };
  final SupabaseClient _client;

  Future<TrainingConfirmationDeadlineSettings> load() async {
    final settings = await loadAll();
    return settings['treino'] ??
        const TrainingConfirmationDeadlineSettings.disabled();
  }

  Future<Map<String, TrainingConfirmationDeadlineSettings>> loadAll() async {
    await OrganizationContextService.instance.initialize();
    final organizationId = OrganizationContextService.instance.currentId;
    final rows = await _client
        .from('organization_settings')
        .select('key, value')
        .eq('organization_id', organizationId)
        .inFilter('key', settingsKeys.values.toList());
    final byKey = <String, dynamic>{
      for (final row in rows) row['key'].toString(): row['value'],
    };
    return {
      for (final entry in settingsKeys.entries)
        entry.key: TrainingConfirmationDeadlineSettings.fromValue(
          byKey[entry.value],
        ),
    };
  }

  Future<void> save(TrainingConfirmationDeadlineSettings settings) async {
    await saveForEventType('treino', settings);
  }

  Future<void> saveForEventType(
    String eventType,
    TrainingConfirmationDeadlineSettings settings,
  ) async {
    final normalizedType = eventType.trim().toLowerCase();
    final key = settingsKeys[normalizedType];
    if (key == null) {
      throw ArgumentError.value(eventType, 'eventType', 'Tipo não suportado');
    }
    await OrganizationContextService.instance.initialize();
    final organizationId = OrganizationContextService.instance.currentId;
    await _client.from('organization_settings').upsert({
      'organization_id': organizationId,
      'key': key,
      'value': settings.toValue(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
      'updated_by': _client.auth.currentUser?.id,
    });
  }
}
