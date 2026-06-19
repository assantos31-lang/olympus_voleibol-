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
    // Corrigido: Busca ESTRITAMENTE treinadores, removendo qualquer chance de trazer 'admin'
    final rows = await _client
        .from('profiles')
        .select('id, full_name, avatar_url, user_type')
        .eq('user_type', 'coach')
        .order('full_name');
    return List<Map<String, dynamic>>.from(rows);
  }

  Future<List<Map<String, dynamic>>> loadMonthlyEnabledCoaches() async {
    final ids = await loadMonthlyEnabledCoachIds();
    if (ids.isEmpty) return [];
    final rows = await _client
        .from('profiles')
        .select('id, full_name, avatar_url, user_type')
        .inFilter('id', ids)
        .eq('user_type', 'coach') // Garantia extra para não trazer admin
        .order('full_name');
    return List<Map<String, dynamic>>.from(rows);
  }

  Future<List<Map<String, dynamic>>> loadEligibleTrainingsForAthleteByMonth({
    required String athleteId,
    required int month,
    required int year,
  }) async {
    final minimumDate = DateTime(2026, 5, 1);
    if (year < 2026 || (year == 2026 && month < 5)) {
      return [];
    }
    final checkinRows = await _client
        .from('checkins')
        .select('event_id, check_in_status, user_id')
        .eq('user_id', athleteId);
    final checkedEventIds = <String>{};
    for (final row in List<Map<String, dynamic>>.from(checkinRows)) {
      final eventId = (row['event_id'] ?? '').toString().trim();
      if (eventId.isEmpty) continue;
      final status =
          (row['check_in_status'] ?? '').toString().trim().toLowerCase();
      final negative = [
        'absent',
        'ausente',
        'faltou',
        'falta',
        'no_show',
        'cancelled',
        'canceled'
      ].contains(status);
      if (!negative) {
        checkedEventIds.add(eventId);
      }
    }
    if (checkedEventIds.isEmpty) return [];

    final convocationRows = await _client
        .from('convocations')
        .select('''
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
        ''')
        .eq('user_id', athleteId)
        .inFilter('event_id', checkedEventIds.toList());

    final now = DateTime.now();
    final result = <Map<String, dynamic>>[];

    for (final raw in List<Map<String, dynamic>>.from(convocationRows)) {
      final eventId = (raw['event_id'] ?? '').toString().trim();
      if (!checkedEventIds.contains(eventId)) continue;
      final eventRaw = raw['events'];
      if (eventRaw is! Map) continue;
      final event = Map<String, dynamic>.from(eventRaw);
      final type = (event['event_type'] ?? '').toString().trim().toLowerCase();
      if (!type.contains('trein')) continue;
      final eventDate =
          parseEventDateTime(event['event_date'], event['event_time']);
      if (eventDate == null) continue;
      final eventDay = DateTime(eventDate.year, eventDate.month, eventDate.day);
      if (eventDay.isBefore(minimumDate)) continue;
      if (eventDate.month != month || eventDate.year != year) continue;
      final alreadyClosed =
          now.isAfter(eventDate.add(const Duration(minutes: 30)));
      if (!alreadyClosed) continue;

      // Verifica se o atleta já avaliou este evento; se sim, pula
      final evaluations = await _client
          .from('coach_evaluations')
          .select('id')
          .eq('athlete_id', athleteId)
          .eq('event_id', eventId)
          .eq('evaluation_type', 'training')
          .limit(1);
      if (evaluations.isNotEmpty) continue;

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
    try {
      // 1. Tenta buscar os IDs na tabela de convocações do evento específico
      final convocationRows = await _client
          .from('convocations')
          .select('user_id')
          .eq('event_id', eventId);

      if (convocationRows.isNotEmpty) {
        final userIds = List<Map<String, dynamic>>.from(convocationRows)
            .map((row) => row['user_id'].toString())
            .toList();

        if (userIds.isNotEmpty) {
          // 2. Busca na tabela de perfis apenas os convocados que SÃO TREINADORES ('coach')
          final eventCoaches = await _client
              .from('profiles')
              .select('id, full_name, avatar_url, user_type')
              .inFilter('id', userIds)
              .eq('user_type', 'coach') // Mantém a regra de barrar admin
              .order('full_name');

          // Se encontrou o treinador vinculado ao treino, retorna ele
          if (eventCoaches.isNotEmpty) {
            return List<Map<String, dynamic>>.from(eventCoaches);
          }
        }
      }

      // 3. FALLBACK (A Correção): Se a lista ficou vazia (como na sua imagem),
      // é porque o treinador não estava na tabela 'convocations'.
      // Para o dropdown não ficar inútil/travado, buscamos a lista de todos os treinadores.
      final allCoachesRows = await _client
          .from('profiles')
          .select('id, full_name, avatar_url, user_type')
          .eq('user_type', 'coach')
          .order('full_name');

      return List<Map<String, dynamic>>.from(allCoachesRows);
    } catch (e) {
      print('Erro ao carregar treinadores: $e');
      return <Map<String, dynamic>>[];
    }
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
    final existing = await _client
        .from('coach_evaluations')
        .select('id')
        .eq('athlete_id', athleteId)
        .eq('coach_id', coachId)
        .eq('event_id', eventId)
        .eq('evaluation_type', 'training')
        .maybeSingle();
    if (existing != null) {
      throw Exception('Você já avaliou este treinador neste treino.');
    }
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
          athlete: profiles!coach_evaluations_athlete_id_fkey (
            id,
            full_name,
            avatar_url
          ),
          coach: profiles!coach_evaluations_coach_id_fkey (
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
    return List<Map<String, dynamic>>.from(rows);
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
