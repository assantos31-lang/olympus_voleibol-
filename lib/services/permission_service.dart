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
          .select('id, email, full_name, user_type, avatar_url');

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
      };
    } catch (e) {
      print('❌ Erro ao buscar filtros: $e');
      return {
        'show_month_filter': true,
        'allowed_event_types': ['treino', 'amistoso', 'campeonato'],
        'show_status_filter': true,
        'allowed_convocation_statuses': ['accepted', 'rejected', 'pending'],
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
    final filters = {
      'show_month_filter': showMonthFilter,
      'allowed_event_types': allowedEventTypes,
      'show_status_filter': showStatusFilter,
      'allowed_convocation_statuses': allowedConvocationStatuses,
    };

    await updatePermission(
      userId: userId,
      pageName: 'agenda',
      canAccess: true,
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
}
