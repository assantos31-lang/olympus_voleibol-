import 'package:flutter/foundation.dart'; // ← ADICIONADO
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthService {
  final supabase = Supabase.instance.client;

  // 🔹 Login
  Future<Map<String, dynamic>> signIn(String email, String password) async {
    try {
      final response = await supabase.auth.signInWithPassword(
        email: email,
        password: password,
      );

      if (response.user == null) {
        return {'success': false, 'error': 'Usuário não encontrado'};
      }

      // Buscar dados do perfil
      final profile = await getUserProfile(response.user!.id);

      return {
        'success': true,
        'user': response.user,
        'profile': profile,
      };
    } on AuthException catch (e) {
      return {'success': false, 'error': e.message};
    } catch (e) {
      return {'success': false, 'error': 'Erro ao fazer login: $e'};
    }
  }

  // 🔹 Registro
  Future<Map<String, dynamic>> signUp(
      String email, String password, String fullName, String userType) async {
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
      return {'success': false, 'error': 'Erro ao registrar: $e'};
    }
  }

  // 🔹 Logout
  Future<void> signOut() async {
    await supabase.auth.signOut();
  }

  // 🔹 Verificar se está logado
  User? getCurrentUser() {
    return supabase.auth.currentUser;
  }

  // 🔹 Buscar perfil do usuário (NOVO)
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

  // 🔹 Stream de autenticação
  Stream<AuthState> get authStateChanges => supabase.auth.onAuthStateChange;
}
