import 'package:supabase_flutter/supabase_flutter.dart';

class CoachEvaluationService {
  CoachEvaluationService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  static const String settingKey = 'coach_evaluation';

  Future<Map<String, dynamic>> loadEvaluationSettings() async {
    final row = await _client
        .from('app_settings')
        .select('value')
        .eq('key', settingKey)
        .maybeSingle();

    final value = row?['value'];
    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }

    return <String, dynamic>{};
  }

  Future<bool> isMonthlyEvaluationEnabled() async {
    final value = await loadEvaluationSettings();
    return value['monthly_enabled'] == true || value['enabled'] == true;
  }

  Future<List<String>> loadMonthlyEnabledCoachIds() async {
    final value = await loadEvaluationSettings();
    final raw = value['monthly_enabled_coach_ids'];

    if (raw is List) {
      return raw
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .toList();
    }

    return <String>[];
  }

  Future<void> setMonthlyEvaluationEnabled(bool enabled) async {
    final current = await loadEvaluationSettings();
    final currentIds = current['monthly_enabled_coach_ids'];

    await _client.from('app_settings').upsert(
      {
        'key': settingKey,
        'value': {
          ...current,
          'enabled': enabled,
          'monthly_enabled': enabled,
          'monthly_enabled_coach_ids':
              currentIds is List ? currentIds : <String>[],
        },
        'updated_at': DateTime.now().toIso8601String(),
      },
      onConflict: 'key',
    );
  }

  Future<void> setMonthlyEnabledCoachIds(List<String> coachIds) async {
    final current = await loadEvaluationSettings();

    await _client.from('app_settings').upsert(
      {
        'key': settingKey,
        'value': {
          ...current,
          'monthly_enabled_coach_ids': coachIds,
        },
        'updated_at': DateTime.now().toIso8601String(),
      },
      onConflict: 'key',
    );
  }

  Future<List<Map<String, dynamic>>> loadCoaches() async {
    final rows = await _client
        .from('profiles')
        .select('id, full_name, avatar_url, user_type')
        .eq('user_type', 'coach')
        .order('full_name', ascending: true);

    return List<Map<String, dynamic>>.from(rows as List);
  }

  Future<List<Map<String, dynamic>>> loadMonthlyEnabledCoaches() async {
    final ids = await loadMonthlyEnabledCoachIds();
    if (ids.isEmpty) return <Map<String, dynamic>>[];

    final rows = await _client
        .from('profiles')
        .select('id, full_name, avatar_url, user_type')
        .inFilter('id', ids)
        .order('full_name', ascending: true);

    return List<Map<String, dynamic>>.from(rows as List);
  }

  Future<List<Map<String, dynamic>>> loadEligibleTrainingsForAthleteByMonth({
    required String athleteId,
    required int month,
    required int year,
  }) async {
    final minimumDate = DateTime(2026, 5, 1);

    if (year < 2026 || (year == 2026 && month < 5)) {
      return <Map<String, dynamic>>[];
    }

    // 1) busca SOMENTE eventos em que o atleta realmente fez check-in.
    // Não depende de relacionamento FK entre tabelas.
    final checkinRows = await _client
        .from('checkins')
        .select('event_id, check_in_status, user_id')
        .eq('user_id', athleteId);

    final checkedEventIds = <String>{};

    for (final row in List<Map<String, dynamic>>.from(checkinRows as List)) {
      final eventId = (row['event_id'] ?? '').toString().trim();
      if (eventId.isEmpty) continue;

      final status =
          (row['check_in_status'] ?? '').toString().trim().toLowerCase();

      final negative = status == 'absent' ||
          status == 'ausente' ||
          status == 'faltou' ||
          status == 'falta' ||
          status == 'no_show' ||
          status == 'cancelled' ||
          status == 'canceled';

      if (!negative) {
        checkedEventIds.add(eventId);
      }
    }

    if (checkedEventIds.isEmpty) return <Map<String, dynamic>>[];

    // 2) garante que o atleta também foi convocado para esses eventos.
    final convocationRows = await _client.from('convocations').select('''
id,
event_id,
status,
events!convocations_event_id_fkey (
id,
event_name,
event_type,
event_date,
event_time,
gender,
city,
state
)
''').eq('user_id', athleteId).inFilter('event_id', checkedEventIds.toList());

    final now = DateTime.now();
    final result = <Map<String, dynamic>>[];

    for (final raw
        in List<Map<String, dynamic>>.from(convocationRows as List)) {
      final eventId = (raw['event_id'] ?? '').toString().trim();
      if (!checkedEventIds.contains(eventId)) continue;

      final eventRaw = raw['events'];
      if (eventRaw is! Map) continue;

      final event = Map<String, dynamic>.from(eventRaw);
      final type = (event['event_type'] ?? '').toString().trim().toLowerCase();
      if (type != 'treino') continue;

      final eventDate =
          parseEventDateTime(event['event_date'], event['event_time']);
      if (eventDate == null) continue;

      final eventDay = DateTime(eventDate.year, eventDate.month, eventDate.day);
      if (eventDay.isBefore(minimumDate)) continue;

      if (eventDate.month != month || eventDate.year != year) continue;

      final alreadyClosed =
          now.isAfter(eventDate.add(const Duration(minutes: 30)));
      if (!alreadyClosed) continue;

      result.add({
        ...event,
        'convocation_id': raw['id'],
        'convocation_status': raw['status'],
      });
    }

    result.sort((a, b) {
      final ad = parseEventDateTime(a['event_date'], a['event_time']) ??
          DateTime.fromMillisecondsSinceEpoch(0);
      final bd = parseEventDateTime(b['event_date'], b['event_time']) ??
          DateTime.fromMillisecondsSinceEpoch(0);
      return bd.compareTo(ad);
    });

    return result;
  }

  Future<List<Map<String, dynamic>>> loadCoachesForTraining({
    required String eventId,
  }) async {
    final ids = <String>{};

    try {
      final blockRows = await _client
          .from('training_plan_blocks')
          .select('coach_id')
          .eq('event_id', eventId);

      for (final row in List<Map<String, dynamic>>.from(blockRows as List)) {
        final id = (row['coach_id'] ?? '').toString().trim();
        if (id.isNotEmpty) ids.add(id);
      }
    } catch (_) {}

    try {
      final noteRows = await _client
          .from('training_plan_notes')
          .select('coach_id')
          .eq('event_id', eventId);

      for (final row in List<Map<String, dynamic>>.from(noteRows as List)) {
        final id = (row['coach_id'] ?? '').toString().trim();
        if (id.isNotEmpty) ids.add(id);
      }
    } catch (_) {}

    if (ids.isEmpty) {
      return loadCoaches();
    }

    final rows = await _client
        .from('profiles')
        .select('id, full_name, avatar_url, user_type')
        .inFilter('id', ids.toList())
        .order('full_name', ascending: true);

    return List<Map<String, dynamic>>.from(rows as List);
  }

  Future<void> submitTrainingEvaluation({
    required String athleteId,
    required String coachId,
    required String eventId,
    required int referenceMonth,
    required int referenceYear,
    required int ratingGeneral,
    required int ratingClarity,
    required int ratingRespect,
    required int ratingTrainingQuality,
    required String positivePoint,
    required String improvementPoint,
    required String comment,
    required bool anonymousToCoach,
  }) async {
    await _client.from('coach_evaluations').insert({
      'athlete_id': athleteId,
      'coach_id': coachId,
      'event_id': eventId,
      'evaluation_type': 'training',
      'reference_month': referenceMonth,
      'reference_year': referenceYear,
      'rating_general': ratingGeneral,
      'rating_clarity': ratingClarity,
      'rating_respect': ratingRespect,
      'rating_training_quality': ratingTrainingQuality,
      'positive_point':
          positivePoint.trim().isEmpty ? null : positivePoint.trim(),
      'improvement_point':
          improvementPoint.trim().isEmpty ? null : improvementPoint.trim(),
      'comment': comment.trim().isEmpty ? null : comment.trim(),
      'anonymous': anonymousToCoach,
      'anonymous_to_coach': anonymousToCoach,
      'visible_to_coach': false,
      'admin_review_status': 'pending',
    });
  }

  Future<void> submitMonthlyEvaluation({
    required String athleteId,
    required String coachId,
    required int referenceMonth,
    required int referenceYear,
    required int ratingGeneral,
    required int ratingClarity,
    required int ratingRespect,
    required int ratingTrainingQuality,
    required int ratingMotivation,
    required int ratingOrganization,
    required int ratingEvolution,
    required int ratingCommunication,
    required String positivePoint,
    required String improvementPoint,
    required String communicationComment,
    required String suggestion,
    required bool anonymousToCoach,
  }) async {
    await _client.from('coach_evaluations').insert({
      'athlete_id': athleteId,
      'coach_id': coachId,
      'event_id': null,
      'evaluation_type': 'monthly',
      'reference_month': referenceMonth,
      'reference_year': referenceYear,
      'rating_general': ratingGeneral,
      'rating_clarity': ratingClarity,
      'rating_respect': ratingRespect,
      'rating_training_quality': ratingTrainingQuality,
      'rating_motivation': ratingMotivation,
      'rating_organization': ratingOrganization,
      'rating_evolution': ratingEvolution,
      'rating_communication': ratingCommunication,
      'positive_point':
          positivePoint.trim().isEmpty ? null : positivePoint.trim(),
      'improvement_point':
          improvementPoint.trim().isEmpty ? null : improvementPoint.trim(),
      'communication_comment': communicationComment.trim().isEmpty
          ? null
          : communicationComment.trim(),
      'suggestion': suggestion.trim().isEmpty ? null : suggestion.trim(),
      'comment': suggestion.trim().isEmpty ? null : suggestion.trim(),
      'anonymous': anonymousToCoach,
      'anonymous_to_coach': anonymousToCoach,
      'visible_to_coach': false,
      'admin_review_status': 'pending',
    });
  }

  Future<void> setEvaluationVisibleToCoach({
    required String evaluationId,
    required bool visible,
  }) async {
    await _client.from('coach_evaluations').update({
      'visible_to_coach': visible,
      'admin_review_status': visible ? 'approved' : 'pending',
      'admin_reviewed_at': DateTime.now().toIso8601String(),
    }).eq('id', evaluationId);
  }

  Future<List<Map<String, dynamic>>> loadAdminEvaluations() async {
    final rows = await _client.from('coach_evaluations').select('''
id,
athlete_id,
coach_id,
event_id,
evaluation_type,
reference_month,
reference_year,
rating_general,
rating_clarity,
rating_respect,
rating_training_quality,
rating_motivation,
rating_organization,
rating_evolution,
rating_communication,
positive_point,
improvement_point,
communication_comment,
suggestion,
comment,
anonymous,
anonymous_to_coach,
visible_to_coach,
admin_review_status,
created_at,
athlete:profiles!coach_evaluations_athlete_id_fkey (
id,
full_name,
avatar_url
),
coach:profiles!coach_evaluations_coach_id_fkey (
id,
full_name,
avatar_url
),
events!coach_evaluations_event_id_fkey (
id,
event_name,
event_date,
event_time,
city,
state
)
''').order('created_at', ascending: false);

    return List<Map<String, dynamic>>.from(rows as List);
  }

  static DateTime? parseEventDateTime(dynamic dateValue, dynamic timeValue) {
    final rawDate = (dateValue ?? '').toString().trim();
    final rawTime = (timeValue ?? '').toString().trim();

    if (rawDate.isEmpty) return null;

    try {
      if (rawDate.contains('/')) {
        final d = rawDate.split('/');
        final t = rawTime.isEmpty ? ['0', '0'] : rawTime.split(':');

        if (d.length == 3 && t.length >= 2) {
          return DateTime(
            int.parse(d[2]),
            int.parse(d[1]),
            int.parse(d[0]),
            int.parse(t[0]),
            int.parse(t[1]),
          );
        }
      }

      final parsed = DateTime.tryParse(rawDate);
      if (parsed == null) return null;

      if (rawTime.isEmpty) return parsed.toLocal();

      final t = rawTime.split(':');
      if (t.length >= 2) {
        return DateTime(
          parsed.year,
          parsed.month,
          parsed.day,
          int.parse(t[0]),
          int.parse(t[1]),
        );
      }

      return parsed.toLocal();
    } catch (_) {
      return null;
    }
  }
}
