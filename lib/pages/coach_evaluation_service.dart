import 'package:supabase_flutter/supabase_flutter.dart';

class CoachEvaluationService {
  CoachEvaluationService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  static const String settingKey = 'coach_evaluation';

  Future<bool> isEvaluationEnabled() async {
    final row = await _client
        .from('app_settings')
        .select('value')
        .eq('key', settingKey)
        .maybeSingle();

    final value = row?['value'];
    if (value is Map) {
      return value['enabled'] == true;
    }

    return false;
  }

  Future<void> setEvaluationEnabled(bool enabled) async {
    await _client.from('app_settings').upsert({
      'key': settingKey,
      'value': {'enabled': enabled},
      'updated_at': DateTime.now().toIso8601String(),
    }, onConflict: 'key');
  }

  Future<List<Map<String, dynamic>>> loadEligibleTrainingsForAthlete({
    required String athleteId,
  }) async {
    final rows = await _client.from('convocations').select('''
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
''').eq('user_id', athleteId);

    final now = DateTime.now();
    final result = <Map<String, dynamic>>[];

    for (final raw in List<Map<String, dynamic>>.from(rows as List)) {
      final eventRaw = raw['events'];
      if (eventRaw is! Map) continue;

      final event = Map<String, dynamic>.from(eventRaw);
      final type = (event['event_type'] ?? '').toString().trim().toLowerCase();
      if (type != 'treino') continue;

      final eventDate =
          parseEventDateTime(event['event_date'], event['event_time']);
      if (eventDate == null) continue;

      final alreadyClosed =
          now.isAfter(eventDate.add(const Duration(minutes: 30)));
      if (!alreadyClosed) continue;

      result.add(event);
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
    final blockRows = await _client
        .from('training_plan_blocks')
        .select('coach_id')
        .eq('event_id', eventId);

    final noteRows = await _client
        .from('training_plan_notes')
        .select('coach_id')
        .eq('event_id', eventId);

    final ids = <String>{};

    for (final row in List<Map<String, dynamic>>.from(blockRows as List)) {
      final id = (row['coach_id'] ?? '').toString().trim();
      if (id.isNotEmpty) ids.add(id);
    }

    for (final row in List<Map<String, dynamic>>.from(noteRows as List)) {
      final id = (row['coach_id'] ?? '').toString().trim();
      if (id.isNotEmpty) ids.add(id);
    }

    if (ids.isEmpty) return [];

    final profiles = await _client
        .from('profiles')
        .select('id, full_name, avatar_url, user_type')
        .inFilter('id', ids.toList())
        .order('full_name', ascending: true);

    return List<Map<String, dynamic>>.from(profiles as List);
  }

  Future<void> submitEvaluation({
    required String athleteId,
    required String coachId,
    required String eventId,
    required int ratingGeneral,
    required int ratingClarity,
    required int ratingRespect,
    required int ratingTrainingQuality,
    required String positivePoint,
    required String improvementPoint,
    required String comment,
    required bool anonymous,
  }) async {
    await _client.from('coach_evaluations').insert({
      'athlete_id': athleteId,
      'coach_id': coachId,
      'event_id': eventId,
      'rating_general': ratingGeneral,
      'rating_clarity': ratingClarity,
      'rating_respect': ratingRespect,
      'rating_training_quality': ratingTrainingQuality,
      'positive_point':
          positivePoint.trim().isEmpty ? null : positivePoint.trim(),
      'improvement_point':
          improvementPoint.trim().isEmpty ? null : improvementPoint.trim(),
      'comment': comment.trim().isEmpty ? null : comment.trim(),
      'anonymous': anonymous,
    });
  }

  Future<List<Map<String, dynamic>>> loadAdminEvaluations() async {
    final rows = await _client.from('coach_evaluations').select('''
id,
athlete_id,
coach_id,
event_id,
rating_general,
rating_clarity,
rating_respect,
rating_training_quality,
positive_point,
improvement_point,
comment,
anonymous,
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
