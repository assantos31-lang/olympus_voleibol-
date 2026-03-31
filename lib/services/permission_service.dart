import 'package:supabase_flutter/supabase_flutter.dart';

class PermissionService {
  final SupabaseClient _supabase = Supabase.instance.client;

  /// Verifica se um usuário tem acesso a uma página específica
  /// Retorna true se tiver permissão ou se não existir registro (fail-safe)
  Future<bool> hasAccess(String userId, String pageName) async {
    try {
      final response = await _supabase
          .from('page_permissions')
          .select('can_access')
          .eq('user_id', userId)
          .eq('page_name', pageName)
          .maybeSingle();

      // Se não existir registro, permite por padrão (fail-safe)
      if (response == null) return true;

      return response['can_access'] as bool;
    } catch (e) {
      print('❌ Erro ao verificar permissão: $e');
      // Em caso de erro, permite acesso (fail-safe)
      return true;
    }
  }

  /// Atualiza ou cria uma permissão (apenas Admin)
  Future<void> updatePermission({
    required String userId,
    required String pageName,
    required bool canAccess,
  }) async {
    try {
      // Verifica se já existe
      final existing = await _supabase
          .from('page_permissions')
          .select()
          .eq('user_id', userId)
          .eq('page_name', pageName)
          .maybeSingle();

      if (existing != null) {
        // Atualiza
        await _supabase
            .from('page_permissions')
            .update({
              'can_access': canAccess,
              'updated_at': DateTime.now().toIso8601String()
            })
            .eq('user_id', userId)
            .eq('page_name', pageName);
      } else {
        // Insere
        await _supabase.from('page_permissions').insert({
          'user_id': userId,
          'page_name': pageName,
          'can_access': canAccess,
        });
      }
    } catch (e) {
      print('❌ Erro ao atualizar permissão: $e');
      rethrow;
    }
  }

  /// Busca todas as permissões de um usuário
  Future<Map<String, bool>> getUserPermissions(String userId) async {
    try {
      final response = await _supabase
          .from('page_permissions')
          .select('page_name, can_access')
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

  /// Busca todos os usuários e suas permissões para a página (apenas Admin)
  Future<List<Map<String, dynamic>>> getUsersWithPermissions(
      String pageName) async {
    try {
      // Busca todos os perfis
      final profilesResponse = await _supabase
          .from('profiles')
          .select('id, email, full_name, user_type, avatar_url');

      // Busca permissões para esta página
      final permissionsResponse = await _supabase
          .from('page_permissions')
          .select('user_id, can_access')
          .eq('page_name', pageName);

      // Cria um mapa de permissões
      final permissionsMap = <String, bool>{};
      for (var perm in permissionsResponse) {
        permissionsMap[perm['user_id']] = perm['can_access'];
      }

      // Combina perfis com permissões
      final result = <Map<String, dynamic>>[];
      for (var profile in profilesResponse) {
        final userId = profile['id'];
        final hasAccess = permissionsMap.containsKey(userId)
            ? permissionsMap[userId]!
            : true; // Se não existir, permite por padrão

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
}
