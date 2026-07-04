import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CoachEvaluationService {
  CoachEvaluationService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  static const String settingKey = 'coach_evaluation';

  Future<List<Map<String, dynamic>>> _loadCoachProfilesByIds(
    Iterable<String> rawIds,
  ) async {
    final ids = rawIds.where((id) => id.trim().isNotEmpty).toSet().toList();
    if (ids.isEmpty) return [];

    final profilesResponse = await _client
        .from('profiles')
        .select('id, full_name, avatar_url, user_type')
        .inFilter('id', ids)
        .eq('is_active', true)
        .order('full_name');
    final profiles = List<Map<String, dynamic>>.from(profilesResponse);

    final coachIds = profiles
        .where((profile) {
          final type =
              (profile['user_type'] ?? '').toString().trim().toLowerCase();
          return const {
            'coach',
            'treinador',
            'tecnico',
            'técnico',
            'technician',
          }.contains(type);
        })
        .map((profile) => (profile['id'] ?? '').toString())
        .toSet();

    try {
      final roleRows = await _client
          .from('user_roles')
          .select('user_id, role, is_active')
          .inFilter('user_id', ids)
          .eq('role', 'coach')
          .eq('is_active', true);
      coachIds.addAll(
        List<Map<String, dynamic>>.from(roleRows)
            .map((row) => (row['user_id'] ?? '').toString())
            .where((id) => id.isNotEmpty),
      );
    } catch (_) {
      // Projetos sem user_roles continuam usando profiles.user_type.
    }

    return profiles
        .where((profile) => coachIds.contains((profile['id'] ?? '').toString()))
        .toList();
  }

  Future<void> _notifyAdminsAboutPendingEvaluation({
    required String evaluationId,
  }) async {
    try {
      final rows = await _client
          .from('profiles')
          .select('id')
          .eq('user_type', 'admin')
          .eq('is_active', true);

      final adminIds = List<Map<String, dynamic>>.from(rows)
          .map((row) => row['id']?.toString())
          .whereType<String>()
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList();

      if (adminIds.isEmpty) {
        debugPrint('Nenhum administrador encontrado para receber avaliacao.');
        return;
      }

      await _client.functions.invoke(
        'send-push-notification',
        body: {
          'userIds': adminIds,
          'title': 'Nova avaliacao pendente',
          'body':
              'Um atleta enviou uma avaliacao. Revise e aprove no aplicativo.',
          'type': 'admin_evaluation_pending',
          'recordId': evaluationId,
        },
      );
    } catch (e) {
      debugPrint('Erro ao notificar administradores sobre avaliacao: $e');
    }
  }

  Future<void> _notifyCoachAboutApprovedEvaluation({
    required String evaluationId,
    required String coachId,
  }) async {
    if (coachId.trim().isEmpty) return;

    try {
      await _client.functions.invoke(
        'send-push-notification',
        body: {
          'userId': coachId,
          'title': 'Nova avaliacao recebida',
          'body': 'Uma avaliacao foi aprovada e esta disponivel para consulta.',
          'type': 'coach_evaluation_approved',
          'recordId': evaluationId,
        },
      );
    } catch (e) {
      debugPrint('Erro ao notificar treinador sobre avaliacao: $e');
    }
  }

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
    try {
      final roleRows = await _client
          .from('user_roles')
          .select('user_id')
          .eq('role', 'coach')
          .eq('is_active', true);
      return _loadCoachProfilesByIds(
        List<Map<String, dynamic>>.from(roleRows)
            .map((row) => (row['user_id'] ?? '').toString()),
      );
    } catch (_) {
      final rows = await _client
          .from('profiles')
          .select('id, full_name, avatar_url, user_type')
          .eq('user_type', 'coach')
          .eq('is_active', true)
          .order('full_name');
      return List<Map<String, dynamic>>.from(rows);
    }
  }

  Future<List<Map<String, dynamic>>> loadMonthlyEnabledCoaches({
    String? athleteId,
  }) async {
    final ids = await loadMonthlyEnabledCoachIds();
    if (ids.isEmpty) return [];
    var allowedIds = ids.toSet();

    if (athleteId != null && athleteId.trim().isNotEmpty) {
      final athleteConvocations = await _client
          .from('convocations')
          .select('event_id')
          .eq('user_id', athleteId);
      final eventIds = List<Map<String, dynamic>>.from(athleteConvocations)
          .map((row) => (row['event_id'] ?? '').toString())
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList();
      if (eventIds.isEmpty) return [];

      final eventConvocations = await _client
          .from('convocations')
          .select('user_id')
          .inFilter('event_id', eventIds);
      final convocatedIds = List<Map<String, dynamic>>.from(eventConvocations)
          .map((row) => (row['user_id'] ?? '').toString())
          .where((id) => id.isNotEmpty)
          .toSet();
      allowedIds = allowedIds.intersection(convocatedIds);
    }

    if (allowedIds.isEmpty) return [];
    return _loadCoachProfilesByIds(allowedIds);
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
        .eq('event_role', 'athlete')
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
      // A RPC usa security definer para atravessar a RLS com segurança:
      // ela só retorna dados quando o usuário autenticado está convocado.
      try {
        final rpcRows = await _client.rpc(
          'get_event_coaches_for_athlete_evaluation',
          params: {'p_event_id': eventId},
        );
        final coaches = List<Map<String, dynamic>>.from(rpcRows as List);
        if (coaches.isNotEmpty) return coaches;
      } catch (_) {
        // Compatibilidade enquanto o SQL ainda não foi executado.
      }

      // A função exercida no evento prevalece sobre os papéis gerais.
      final convocationRows = await _client
          .from('convocations')
          .select('user_id')
          .eq('event_id', eventId)
          .eq('event_role', 'coach')
          .limit(1);

      if (convocationRows.isNotEmpty) {
        final userIds = List<Map<String, dynamic>>.from(convocationRows)
            .map((row) => row['user_id'].toString())
            .toList();

        if (userIds.isNotEmpty) {
          final eventCoaches = await _loadCoachProfilesByIds(userIds);

          // Se encontrou o treinador vinculado ao treino, retorna ele
          if (eventCoaches.isNotEmpty) {
            return List<Map<String, dynamic>>.from(eventCoaches);
          }
        }
      }

      // Eventos antigos nem sempre salvaram o treinador em convocations.
      // O coach_id do planejamento identifica com segurança quem conduziu
      // aquele treino, sem abrir acesso aos demais treinadores.
      final planningRows = await _client
          .from('training_plan_blocks')
          .select('coach_id')
          .eq('event_id', eventId);
      final planningCoachIds = List<Map<String, dynamic>>.from(planningRows)
          .map((row) => (row['coach_id'] ?? '').toString())
          .where((id) => id.isNotEmpty)
          .toSet();
      if (planningCoachIds.isNotEmpty) {
        final planningCoaches = await _loadCoachProfilesByIds(planningCoachIds);
        if (planningCoaches.isNotEmpty) return planningCoaches;
      }

      // Sem vínculo no evento, não exibe uma lista geral de treinadores.
      return <Map<String, dynamic>>[];
    } catch (e) {
      print('Erro ao carregar treinadores: $e');
      return <Map<String, dynamic>>[];
    }
  }

  Future<List<Map<String, dynamic>>> loadCompletedEvaluationsForAthlete({
    required String athleteId,
  }) async {
    final rows = await _client.from('coach_evaluations').select('''
      id,
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
      anonymous_to_coach,
      admin_review_status,
      created_at,
      coach: profiles!coach_evaluations_coach_id_fkey (
        id,
        full_name,
        avatar_url
      ),
      events!coach_evaluations_event_id_fkey (
        id,
        event_name,
        event_date,
        event_time
      )
    ''').eq('athlete_id', athleteId).order('created_at', ascending: false);

    return List<Map<String, dynamic>>.from(rows);
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
    final inserted = await _client
        .from('coach_evaluations')
        .insert({
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
        })
        .select('id')
        .single();

    await _notifyAdminsAboutPendingEvaluation(
      evaluationId: inserted['id'].toString(),
    );
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
    final inserted = await _client
        .from('coach_evaluations')
        .insert({
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
        })
        .select('id')
        .single();

    await _notifyAdminsAboutPendingEvaluation(
      evaluationId: inserted['id'].toString(),
    );
  }

  Future<void> setEvaluationVisibleToCoach({
    required String evaluationId,
    required bool visible,
  }) async {
    final evaluation = await _client
        .from('coach_evaluations')
        .select('coach_id')
        .eq('id', evaluationId)
        .maybeSingle();

    await _client.from('coach_evaluations').update({
      'visible_to_coach': visible,
      'admin_review_status': visible ? 'approved' : 'pending',
      'admin_reviewed_at': DateTime.now().toIso8601String(),
    }).eq('id', evaluationId);

    final coachId = evaluation?['coach_id']?.toString() ?? '';

    if (visible && coachId.isNotEmpty) {
      await _notifyCoachAboutApprovedEvaluation(
        evaluationId: evaluationId,
        coachId: coachId,
      );
    }
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
