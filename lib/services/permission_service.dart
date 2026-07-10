import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:convert';

class PermissionService {
  final SupabaseClient _supabase = Supabase.instance.client;

  Future<bool> hasAccess(String userId, String pageName) async {
    try {
      final response = await _supabase
          .from('page_permissions')
          .select('can_access')
          .eq('user_id', userId)
          .eq('page_name', pageName)
          .maybeSingle();

      if (response == null) return true;
      return response['can_access'] as bool;
    } catch (e) {
      print('❌ Erro ao verificar permissão: $e');
      return true;
    }
  }

  Future<void> updatePermission({
    required String userId,
    required String pageName,
    required bool canAccess,
    Map<String, dynamic>? allowedFilters,
  }) async {
    try {
      final existing = await _supabase
          .from('page_permissions')
          .select()
          .eq('user_id', userId)
          .eq('page_name', pageName)
          .maybeSingle();

      final data = {
        'user_id': userId,
        'page_name': pageName,
        'can_access': canAccess,
        if (allowedFilters != null)
          'allowed_filters': jsonEncode(allowedFilters),
        'updated_at': DateTime.now().toIso8601String(),
      };

      if (existing != null) {
        await _supabase
            .from('page_permissions')
            .update(data)
            .eq('user_id', userId)
            .eq('page_name', pageName);
      } else {
        await _supabase.from('page_permissions').insert(data);
      }
    } catch (e) {
      print('❌ Erro ao atualizar permissão: $e');
      rethrow;
    }
  }

  Future<Map<String, bool>> getUserPermissions(String userId) async {
    try {
      final response = await _supabase
          .from('page_permissions')
          .select('page_name, can_access, allowed_filters')
          .eq('user_id', userId);

      final permissions = <String, bool>{};
      for (var item in response) {
        permissions[item['page_name']] = item['can_access'];
      }
      return permissions;
    } catch (e) {
      print('❌ Erro ao buscar permissões: $e');
      return {};
    }
  }

  Future<List<Map<String, dynamic>>> getUsersWithPermissions(
      String pageName) async {
    try {
      final profilesResponse = await _supabase
          .from('profiles')
          .select('id, email, full_name, user_type, avatar_url')
          .eq('is_active', true);

      final permissionsResponse = await _supabase
          .from('page_permissions')
          .select('user_id, can_access')
          .eq('page_name', pageName);

      final permissionsMap = <String, bool>{};
      for (var perm in permissionsResponse) {
        permissionsMap[perm['user_id']] = perm['can_access'];
      }

      final result = <Map<String, dynamic>>[];
      for (var profile in profilesResponse) {
        final userId = profile['id'];
        final hasAccess =
            permissionsMap.containsKey(userId) ? permissionsMap[userId]! : true;

        result.add({
          'id': userId,
          'email': profile['email'],
          'full_name': profile['full_name'],
          'user_type': profile['user_type'],
          'avatar_url': profile['avatar_url'],
          'can_access': hasAccess,
        });
      }
      return result;
    } catch (e) {
      print('❌ Erro ao buscar usuários com permissões: $e');
      return [];
    }
  }

  List<String> _parseStringList(dynamic value, List<String> fallback) {
    try {
      if (value == null) return fallback;

      if (value is List) {
        return value.map((e) => e.toString()).toList();
      }

      if (value is String) {
        final decoded = jsonDecode(value);
        if (decoded is List) {
          return decoded.map((e) => e.toString()).toList();
        }
      }

      return fallback;
    } catch (_) {
      return fallback;
    }
  }

  Future<Map<String, dynamic>> getAgendaFilters(String userId) async {
    try {
      final response = await _supabase
          .from('page_permissions')
          .select('allowed_filters')
          .eq('user_id', userId)
          .eq('page_name', 'agenda')
          .maybeSingle();

      final fallback = {
        'show_month_filter': true,
        'allowed_event_types': ['treino', 'amistoso', 'campeonato'],
        'show_status_filter': true,
        'allowed_convocation_statuses': ['accepted', 'rejected', 'pending'],
        'ver_convocados': false,
        'exportar_dados_jogo': false,
      };

      if (response == null || response['allowed_filters'] == null) {
        return fallback;
      }

      final raw = response['allowed_filters'];
      Map<String, dynamic> filters;

      if (raw is String) {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          filters = decoded;
        } else {
          return fallback;
        }
      } else if (raw is Map) {
        filters = Map<String, dynamic>.from(raw);
      } else {
        return fallback;
      }

      return {
        'show_month_filter': filters['show_month_filter'] ?? true,
        'allowed_event_types': _parseStringList(
          filters['allowed_event_types'],
          ['treino', 'amistoso', 'campeonato'],
        ),
        'show_status_filter': filters['show_status_filter'] ?? true,
        'allowed_convocation_statuses': _parseStringList(
          filters['allowed_convocation_statuses'],
          ['accepted', 'rejected', 'pending'],
        ),
        'ver_convocados': filters['ver_convocados'] == true,
        'exportar_dados_jogo': filters['exportar_dados_jogo'] == true,
      };
    } catch (e) {
      print('❌ Erro ao buscar filtros: $e');
      return {
        'show_month_filter': true,
        'allowed_event_types': ['treino', 'amistoso', 'campeonato'],
        'show_status_filter': true,
        'allowed_convocation_statuses': ['accepted', 'rejected', 'pending'],
        'ver_convocados': false,
        'exportar_dados_jogo': false,
      };
    }
  }

  Future<void> updateAgendaFilters({
    required String userId,
    required bool showMonthFilter,
    required List<String> allowedEventTypes,
    required bool showStatusFilter,
    required List<String> allowedConvocationStatuses,
  }) async {
    final currentFilters = await getAgendaFilters(userId);
    final currentAccess = await hasAccess(userId, 'agenda');

    final filters = {
      'show_month_filter': showMonthFilter,
      'allowed_event_types': allowedEventTypes,
      'show_status_filter': showStatusFilter,
      'allowed_convocation_statuses': allowedConvocationStatuses,
      'ver_convocados': currentFilters['ver_convocados'] == true,
      'exportar_dados_jogo': currentFilters['exportar_dados_jogo'] == true,
    };

    await updatePermission(
      userId: userId,
      pageName: 'agenda',
      canAccess: currentAccess,
      allowedFilters: filters,
    );
  }

  Future<Map<String, bool>> getAgendaActionPermissions(String userId) async {
    try {
      final response = await _supabase
          .from('page_permissions')
          .select('allowed_filters')
          .eq('user_id', userId)
          .eq('page_name', 'agenda')
          .maybeSingle();

      if (response == null || response['allowed_filters'] == null) {
        return {
          'ver_convocados': false,
          'exportar_dados_jogo': false,
        };
      }

      final raw = response['allowed_filters'];
      Map<String, dynamic> filters;

      if (raw is String) {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          filters = decoded;
        } else {
          return {
            'ver_convocados': false,
            'exportar_dados_jogo': false,
          };
        }
      } else if (raw is Map) {
        filters = Map<String, dynamic>.from(raw);
      } else {
        return {
          'ver_convocados': false,
          'exportar_dados_jogo': false,
        };
      }

      return {
        'ver_convocados': filters['ver_convocados'] == true,
        'exportar_dados_jogo': filters['exportar_dados_jogo'] == true,
      };
    } catch (e) {
      print('❌ Erro ao buscar ações da agenda: $e');
      return {
        'ver_convocados': false,
        'exportar_dados_jogo': false,
      };
    }
  }

  Future<void> updateAgendaActionPermissions({
    required String userId,
    required bool verConvocados,
    required bool exportarDadosJogo,
  }) async {
    final currentFilters = await getAgendaFilters(userId);
    final currentAccess = await hasAccess(userId, 'agenda');

    final filters = {
      'show_month_filter': currentFilters['show_month_filter'] ?? true,
      'allowed_event_types': currentFilters['allowed_event_types'] ??
          ['treino', 'amistoso', 'campeonato'],
      'show_status_filter': currentFilters['show_status_filter'] ?? true,
      'allowed_convocation_statuses':
          currentFilters['allowed_convocation_statuses'] ??
              ['accepted', 'rejected', 'pending'],
      'ver_convocados': verConvocados,
      'exportar_dados_jogo': exportarDadosJogo,
    };

    await updatePermission(
      userId: userId,
      pageName: 'agenda',
      canAccess: currentAccess,
      allowedFilters: filters,
    );
  }

  Future<Map<String, dynamic>> getFinancialFilters(String userId) async {
    try {
      final response = await _supabase
          .from('page_permissions')
          .select('allowed_filters')
          .eq('user_id', userId)
          .eq('page_name', 'financeiro')
          .maybeSingle();

      final fallback = {
        'allowed_financial_types': ['monthly', 'games', 'maintenance', 'other'],
      };

      if (response == null || response['allowed_filters'] == null) {
        return fallback;
      }

      final raw = response['allowed_filters'];
      Map<String, dynamic> filters;

      if (raw is String) {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          filters = decoded;
        } else {
          return fallback;
        }
      } else if (raw is Map) {
        filters = Map<String, dynamic>.from(raw);
      } else {
        return fallback;
      }

      return {
        'allowed_financial_types': _parseStringList(
          filters['allowed_financial_types'],
          ['monthly', 'games', 'maintenance', 'other'],
        ),
      };
    } catch (e) {
      print('❌ Erro ao buscar filtros financeiros: $e');
      return {
        'allowed_financial_types': ['monthly', 'games', 'maintenance', 'other'],
      };
    }
  }

  Future<void> updateFinancialFilters({
    required String userId,
    required List<String> allowedFinancialTypes,
  }) async {
    final currentAccess = await hasAccess(userId, 'financeiro');

    final filters = {
      'allowed_financial_types': allowedFinancialTypes,
    };

    await updatePermission(
      userId: userId,
      pageName: 'financeiro',
      canAccess: currentAccess,
      allowedFilters: filters,
    );
  }

  Future<Map<String, bool>> getRankingEvaluationVisibility(
      String userId) async {
    try {
      final response = await _supabase
          .from('page_permissions')
          .select('page_name, can_access')
          .eq('user_id', userId)
          .inFilter('page_name', ['ranking', 'avaliacoes']);

      final result = {
        'show_in_ranking': false,
        'show_in_evaluations': false,
      };

      for (final item in response) {
        final pageName = (item['page_name'] ?? '').toString();
        final canAccess = item['can_access'] == true;

        if (pageName == 'ranking') {
          result['show_in_ranking'] = canAccess;
        } else if (pageName == 'avaliacoes') {
          result['show_in_evaluations'] = canAccess;
        }
      }

      return result;
    } catch (e) {
      print('❌ Erro ao buscar visibilidade de ranking/avaliações: $e');
      return {
        'show_in_ranking': false,
        'show_in_evaluations': false,
      };
    }
  }

  Future<void> updateRankingEvaluationVisibility({
    required String userId,
    required bool showInRanking,
    required bool showInEvaluations,
  }) async {
    await updatePermission(
      userId: userId,
      pageName: 'ranking',
      canAccess: showInRanking,
    );

    await updatePermission(
      userId: userId,
      pageName: 'avaliacoes',
      canAccess: showInEvaluations,
    );
  }

  Future<List<String>> getVisibleUserIdsForPage(String pageName) async {
    try {
      final response = await _supabase
          .from('page_permissions')
          .select('user_id')
          .eq('page_name', pageName)
          .eq('can_access', true);

      final visibleIds = List<Map<String, dynamic>>.from(response as List)
          .map((row) => (row['user_id'] ?? '').toString())
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList();

      if (visibleIds.isEmpty) return [];

      final shouldFilterAthletes =
          pageName == 'ranking' || pageName == 'avaliacoes';
      if (!shouldFilterAthletes) {
        return visibleIds;
      }

      final currentUserId = _supabase.auth.currentUser?.id;
      final currentProfile = currentUserId == null
          ? null
          : await _supabase
              .from('profiles')
              .select('user_type, coach_team_gender')
              .eq('id', currentUserId)
              .maybeSingle();

      final currentUserType =
          (currentProfile?['user_type'] ?? '').toString().trim().toLowerCase();
      final coachTeamGender = normalizeCoachTeamGender(
        currentProfile?['coach_team_gender'],
      );

      final profilesResponse = await _supabase
          .from('profiles')
          .select('id, user_type, gender, is_active')
          .inFilter('id', visibleIds);

      final profiles =
          List<Map<String, dynamic>>.from(profilesResponse as List);

      return profiles
          .where((profile) {
            final userType =
                (profile['user_type'] ?? '').toString().trim().toLowerCase();
            final isAthlete = userType == 'athlete' || userType == 'atleta';
            if (!isAthlete) return false;

            final isActive = profile['is_active'] != false;
            if (!isActive) return false;

            if (currentUserType == 'coach' && coachTeamGender != 'all') {
              return coachCanAccessGender(
                coachTeamGender: coachTeamGender,
                athleteGender: profile['gender'],
              );
            }

            return true;
          })
          .map((profile) => (profile['id'] ?? '').toString())
          .where((id) => id.isNotEmpty)
          .toList();
    } catch (e) {
      print('❌ Erro ao buscar usuários visíveis para $pageName: $e');
      return [];
    }
  }

  String normalizeCoachTeamGender(dynamic value) {
    final raw = (value ?? '').toString().trim().toLowerCase();
    if (raw == 'masculino' || raw == 'male' || raw == 'm') {
      return 'Masculino';
    }
    if (raw == 'feminino' || raw == 'female' || raw == 'f') {
      return 'Feminino';
    }
    return 'all';
  }

  String coachTeamGenderLabel(dynamic value) {
    switch (normalizeCoachTeamGender(value)) {
      case 'Masculino':
        return 'Masculino';
      case 'Feminino':
        return 'Feminino';
      default:
        return 'Ambos';
    }
  }

  Future<String> getCoachTeamGender({String? userId}) async {
    try {
      final targetUserId = userId ?? _supabase.auth.currentUser?.id;
      if (targetUserId == null || targetUserId.isEmpty) return 'all';

      final response = await _supabase
          .from('profiles')
          .select('user_type, coach_team_gender')
          .eq('id', targetUserId)
          .maybeSingle();

      final userType = (response?['user_type'] ?? '').toString().toLowerCase();
      if (userType != 'coach') return 'all';

      return normalizeCoachTeamGender(response?['coach_team_gender']);
    } catch (e) {
      print('❌ Erro ao buscar gênero do time do treinador: $e');
      return 'all';
    }
  }

  Future<void> updateCoachTeamGender({
    required String userId,
    required String coachTeamGender,
  }) async {
    try {
      await _supabase
          .from('profiles')
          .update({
            'coach_team_gender': normalizeCoachTeamGender(coachTeamGender),
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', userId)
          .eq('user_type', 'coach');
    } catch (e) {
      print('❌ Erro ao atualizar gênero do time do treinador: $e');
      rethrow;
    }
  }

  bool coachCanAccessGender({
    required String coachTeamGender,
    required dynamic athleteGender,
  }) {
    final normalizedCoachGender = normalizeCoachTeamGender(coachTeamGender);
    if (normalizedCoachGender == 'all') return true;
    return normalizedCoachGender.toLowerCase() ==
        (athleteGender ?? '').toString().trim().toLowerCase();
  }

  Future<List<Map<String, dynamic>>> filterAthletesForCurrentCoach(
    List<Map<String, dynamic>> athletes,
  ) async {
    final coachTeamGender = await getCoachTeamGender();
    if (coachTeamGender == 'all') return athletes;

    return athletes
        .where(
          (athlete) => coachCanAccessGender(
            coachTeamGender: coachTeamGender,
            athleteGender: athlete['gender'],
          ),
        )
        .toList();
  }
}
