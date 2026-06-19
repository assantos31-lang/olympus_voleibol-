// lib/services/role_service.dart

import 'package:supabase_flutter/supabase_flutter.dart';

/// Serviço responsável por gerenciar múltiplos papéis por usuário.
/// Trabalha em paralelo com o campo user_type existente (retrocompatível).
class RoleService {
  final SupabaseClient _supabase = Supabase.instance.client;

  // ─── Papéis válidos ────────────────────────────────────────────────────────

  static const List<String> validRoles = [
    'admin',
    'coach',
    'athlete',
    'member',
  ];

  static const Map<String, String> roleLabels = {
    'admin': 'Administrador',
    'coach': 'Técnico',
    'athlete': 'Atleta',
    'member': 'Membro',
  };

  String labelFor(String role) => roleLabels[role] ?? role;

  // ─── Leitura ───────────────────────────────────────────────────────────────

  /// Retorna todos os papéis ativos de um usuário.
  Future<List<String>> getUserRoles(String userId) async {
    try {
      final response = await _supabase
          .from('user_roles')
          .select('role')
          .eq('user_id', userId)
          .eq('is_active', true);

      return List<Map<String, dynamic>>.from(response)
          .map((row) => row['role'].toString())
          .toList();
    } catch (e) {
      // Fallback: lê user_type da tabela profiles (compatibilidade)
      return await _fallbackFromProfile(userId);
    }
  }

  /// Retorna todos os papéis (ativos e inativos) de um usuário.
  Future<List<Map<String, dynamic>>> getUserRolesFull(String userId) async {
    try {
      final response = await _supabase
          .from('user_roles')
          .select('id, role, is_active, created_at')
          .eq('user_id', userId)
          .order('created_at');

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      return [];
    }
  }

  /// Retorna o papel primário do usuário (mesmo campo user_type — retrocompat).
  Future<String> getPrimaryRole(String userId) async {
    try {
      final response = await _supabase
          .from('profiles')
          .select('user_type')
          .eq('id', userId)
          .maybeSingle();

      return (response?['user_type'] ?? 'member').toString();
    } catch (e) {
      return 'member';
    }
  }

  // ─── Escrita ───────────────────────────────────────────────────────────────

  /// Adiciona um papel ao usuário.
  /// Não remove papéis existentes — apenas insere o novo.
  Future<void> addRole(String userId, String role) async {
    if (!validRoles.contains(role)) {
      throw ArgumentError('Papel inválido: $role');
    }

    await _supabase.from('user_roles').upsert(
      {
        'user_id': userId,
        'role': role,
        'is_active': true,
        'updated_at': DateTime.now().toIso8601String(),
      },
      onConflict: 'user_id,role',
    );
  }

  /// Remove (desativa) um papel do usuário.
  /// Nunca remove o último papel ativo.
  Future<void> removeRole(String userId, String role) async {
    final current = await getUserRoles(userId);

    if (current.length <= 1 && current.contains(role)) {
      throw Exception(
        'Não é possível remover o único papel ativo do usuário.',
      );
    }

    await _supabase
        .from('user_roles')
        .update({
          'is_active': false,
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('user_id', userId)
        .eq('role', role);
  }

  /// Define os papéis de um usuário substituindo os anteriores.
  /// Também sincroniza o campo user_type com o papel primário informado.
  Future<void> setRoles({
    required String userId,
    required List<String> roles,
    required String primaryRole,
  }) async {
    if (roles.isEmpty) {
      throw ArgumentError('O usuário deve ter pelo menos um papel.');
    }

    for (final role in roles) {
      if (!validRoles.contains(role)) {
        throw ArgumentError('Papel inválido: $role');
      }
    }

    // 1. Desativa todos os papéis atuais
    await _supabase.from('user_roles').update({
      'is_active': false,
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('user_id', userId);

    // 2. Insere / reativa os papéis selecionados
    for (final role in roles) {
      await _supabase.from('user_roles').upsert(
        {
          'user_id': userId,
          'role': role,
          'is_active': true,
          'updated_at': DateTime.now().toIso8601String(),
        },
        onConflict: 'user_id,role',
      );
    }

    // 3. Sincroniza user_type (retrocompatibilidade)
    await _supabase.from('profiles').update({
      'user_type': primaryRole,
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', userId);
  }

  /// Verifica se um usuário possui determinado papel ativo.
  Future<bool> hasRole(String userId, String role) async {
    try {
      final response = await _supabase
          .from('user_roles')
          .select('id')
          .eq('user_id', userId)
          .eq('role', role)
          .eq('is_active', true)
          .maybeSingle();

      return response != null;
    } catch (e) {
      return false;
    }
  }

  // ─── Listagem para admin ───────────────────────────────────────────────────

  /// Retorna todos os perfis com seus papéis ativos (para tela de admin).
  Future<List<Map<String, dynamic>>> getAllProfilesWithRoles() async {
    try {
      final profiles = await _supabase
          .from('profiles')
          .select('id, full_name, email, user_type, avatar_url, is_active')
          .order('full_name');

      final rolesResponse = await _supabase
          .from('user_roles')
          .select('user_id, role')
          .eq('is_active', true);

      // Agrupa papéis por user_id
      final rolesMap = <String, List<String>>{};
      for (final row in rolesResponse) {
        final uid = row['user_id'].toString();
        rolesMap.putIfAbsent(uid, () => []).add(row['role'].toString());
      }

      return List<Map<String, dynamic>>.from(profiles).map((profile) {
        final uid = profile['id'].toString();
        return {
          ...profile,
          'roles': rolesMap[uid] ?? [profile['user_type'] ?? 'member'],
        };
      }).toList();
    } catch (e) {
      return [];
    }
  }

  // ─── Fallback ──────────────────────────────────────────────────────────────

  Future<List<String>> _fallbackFromProfile(String userId) async {
    try {
      final response = await _supabase
          .from('profiles')
          .select('user_type')
          .eq('id', userId)
          .maybeSingle();

      final type = (response?['user_type'] ?? 'member').toString();
      return [type];
    } catch (_) {
      return ['member'];
    }
  }
}
