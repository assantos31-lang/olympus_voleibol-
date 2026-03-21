import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'athlete_dashboard_page.dart';
import 'coach_dashboard_page.dart';
import 'member_dashboard_page.dart';
import 'complete_profile_page.dart';
import 'profiles_page.dart';
import 'admin_home_page.dart';

class DashboardRouterPage extends StatefulWidget {
  const DashboardRouterPage({super.key});

  @override
  State<DashboardRouterPage> createState() => _DashboardRouterPageState();
}

class _DashboardRouterPageState extends State<DashboardRouterPage> {
  final supabase = Supabase.instance.client;
  bool _isLoading = true;
  Widget? _dashboardWidget;

  @override
  void initState() {
    super.initState();
    _loadDashboard();
  }

  Future<User?> _getCurrentUserWithRetry() async {
    User? user = supabase.auth.currentUser;

    // Pequena tolerância para evitar race condition logo após o login
    for (int i = 0; i < 10 && user == null; i++) {
      await Future.delayed(const Duration(milliseconds: 200));
      user = supabase.auth.currentUser;
    }

    return user;
  }

  Future<Map<String, dynamic>?> _getProfileWithRetry(String userId) async {
    Map<String, dynamic>? profile;

    // Tenta algumas vezes caso o perfil ainda esteja sendo criado/sincronizado
    for (int i = 0; i < 6; i++) {
      profile = await supabase
          .from('profiles')
          .select()
          .eq('id', userId)
          .maybeSingle();

      if (profile != null) {
        return profile;
      }

      await Future.delayed(const Duration(milliseconds: 300));
    }

    return null;
  }

  Future<void> _loadDashboard() async {
    try {
      final user = await _getCurrentUserWithRetry();

      if (user == null) {
        if (!mounted) return;
        Navigator.pushReplacementNamed(context, '/login');
        return;
      }

      final profile = await _getProfileWithRetry(user.id);

      if (!mounted) return;

      final userType = profile?['user_type'] ?? 'member';

      final fullName = profile?['full_name'];
      final cpf = profile?['cpf'];
      final phone = profile?['phone'];

      final needsCompleteProfile = userType == 'athlete' &&
          (fullName == null ||
              fullName.toString().trim().isEmpty ||
              cpf == null ||
              cpf.toString().trim().isEmpty ||
              phone == null ||
              phone.toString().trim().isEmpty);

      if (needsCompleteProfile) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => const CompleteProfilePage(),
          ),
        );
        return;
      }

      Widget dashboard;

      switch (userType) {
        case 'athlete':
          dashboard = const AthleteDashboardPage();
          break;
        case 'coach':
          dashboard = const CoachDashboardPage();
          break;
        case 'member':
          dashboard = const MemberDashboardPage();
          break;
        case 'admin':
          dashboard = const AdminHomePage();
          break;
        default:
          dashboard = const ProfilesPage();
      }

      if (!mounted) return;

      setState(() {
        _dashboardWidget = dashboard;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('❌ Erro ao carregar dashboard: $e');

      if (!mounted) return;

      setState(() {
        _dashboardWidget = const ProfilesPage();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Carregando dashboard...'),
            ],
          ),
        ),
      );
    }

    return _dashboardWidget ?? const ProfilesPage();
  }
}
