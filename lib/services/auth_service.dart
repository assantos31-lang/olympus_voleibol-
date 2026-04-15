import 'dart:io' show Platform;

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthService {
  final supabase = Supabase.instance.client;

  // 🔥 CORREÇÃO: nunca quebrar login por causa de push
  Future<void> _savePushTokenForCurrentUser() async {
    if (kIsWeb) return;

    try {
      final user = supabase.auth.currentUser;
      if (user == null) {
        debugPrint('Sem usuário logado para salvar token push.');
        return;
      }

      final messaging = FirebaseMessaging.instance;

      // 🔥 iOS precisa pedir permissão antes
      await messaging.requestPermission();

      final token = await messaging.getToken();
      debugPrint('FCM TOKEN NO AUTH SERVICE: $token');

      if (token == null || token.isEmpty) {
        debugPrint('Token FCM vazio no AuthService.');
        return;
      }

      debugPrint('🔥 AUTH SERVICE CHAMOU save token 🔥');
      debugPrint('🔥 USER ID: ${user.id} 🔥');
      debugPrint('🔥 TOKEN: $token 🔥');
      debugPrint('🔥 SALVANDO TOKEN PUSH AGORA 🔥');

      await supabase.from('user_push_tokens').upsert({
        'user_id': user.id,
        'device_token': token,
        'platform': Platform.isIOS ? 'ios' : 'android',
        'updated_at': DateTime.now().toIso8601String(),
      }, onConflict: 'user_id,device_token');

      debugPrint('Token push salvo com sucesso pelo AuthService.');
    } catch (e) {
      // 🔥 NUNCA quebrar login
      debugPrint('Erro ao salvar token push (IGNORADO): $e');
    }
  }

  Future<Map<String, dynamic>> signIn(String email, String password) async {
    try {
      final response = await supabase.auth.signInWithPassword(
        email: email,
        password: password,
      );

      if (response.user == null) {
        return {'success': false, 'error': 'Usuário não encontrado'};
      }

      await _savePushTokenForCurrentUser();

      final profile = await getUserProfile(response.user!.id);

      return {
        'success': true,
        'user': response.user,
        'profile': profile,
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

  Future<Map<String, dynamic>> deleteMyAccount() async {
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
        'delete-account',
        headers: {
          'Authorization': 'Bearer ${session.accessToken}',
        },
      );

      if (response.status != 200) {
        return {
          'success': false,
          'error': response.data?['error'] ?? 'Falha ao excluir conta',
        };
      }

      await supabase.auth.signOut();

      return {'success': true};
    } on AuthException catch (e) {
      return {'success': false, 'error': e.message};
    } catch (e) {
      return {'success': false, 'error': 'Erro ao excluir conta'};
    }
  }

  Future<void> signOut() async {
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
