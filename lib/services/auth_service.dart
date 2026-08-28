import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'push_token_service.dart';

class AuthService {
  final supabase = Supabase.instance.client;

  Future<Map<String, dynamic>> signIn(String email, String password) async {
    try {
      final response = await supabase.auth.signInWithPassword(
        email: email,
        password: password,
      );

      if (response.user == null) {
        return {'success': false, 'error': 'Usuário não encontrado'};
      }

      return {
        'success': true,
        'user': response.user,
      };
    } on AuthException catch (e) {
      return {'success': false, 'error': e.message};
    } catch (e) {
      return {'success': false, 'error': 'Erro ao fazer login'};
    }
  }

  Future<Map<String, dynamic>> signUp(
    String email,
    String password,
    String fullName,
    String userType,
  ) async {
    try {
      final response = await supabase.auth.signUp(
        email: email,
        password: password,
        data: {
          'full_name': fullName,
          'user_type': userType,
        },
      );

      if (response.user == null) {
        return {'success': false, 'error': 'Erro ao criar usuário'};
      }

      return {'success': true, 'user': response.user};
    } on AuthException catch (e) {
      return {'success': false, 'error': e.message};
    } catch (e) {
      return {'success': false, 'error': 'Erro ao registrar'};
    }
  }

  Future<Map<String, dynamic>> deleteMyAccount({
    required String confirmationEmail,
  }) async {
    try {
      final user = supabase.auth.currentUser;
      if (user == null) {
        return {'success': false, 'error': 'Usuário não autenticado'};
      }

      Session? session = supabase.auth.currentSession;

      try {
        final refreshResponse = await supabase.auth.refreshSession();
        session = refreshResponse.session ?? session;
      } catch (_) {}

      if (session == null) {
        return {
          'success': false,
          'error': 'Sessão expirada. Faça login novamente.',
        };
      }

      final response = await supabase.functions.invoke(
        'delete-user-account',
        headers: {
          'Authorization': 'Bearer ${session.accessToken}',
        },
        body: {
          'user_id': user.id,
          'confirmation_email': confirmationEmail.trim(),
        },
      );

      if (response.status != 200) {
        return {
          'success': false,
          'error': response.data?['error'] ?? 'Falha ao excluir conta',
        };
      }

      try {
        await supabase.auth.signOut(scope: SignOutScope.local);
      } catch (_) {
        // A conta já foi removida no servidor; a sessão local expira em seguida.
      }

      return {'success': true};
    } on AuthException catch (e) {
      return {'success': false, 'error': e.message};
    } catch (e) {
      return {'success': false, 'error': 'Erro ao excluir conta'};
    }
  }

  Future<void> signOut() async {
    try {
      await PushTokenService.instance.clearUserOnLogout();
    } catch (e) {
      debugPrint('Erro ao limpar vínculo do push no logout: $e');
    }

    await supabase.auth.signOut();
  }

  User? getCurrentUser() {
    return supabase.auth.currentUser;
  }

  bool isAuthenticated() {
    final session = supabase.auth.currentSession;
    final user = supabase.auth.currentUser;
    return session != null && user != null;
  }

  Future<Map<String, dynamic>?> getUserProfile(String userId) async {
    try {
      final response =
          await supabase.from('profiles').select().eq('id', userId).single();

      return response;
    } catch (e) {
      debugPrint('Erro ao buscar perfil: $e');
      return null;
    }
  }

  Stream<AuthState> get authStateChanges => supabase.auth.onAuthStateChange;
}
