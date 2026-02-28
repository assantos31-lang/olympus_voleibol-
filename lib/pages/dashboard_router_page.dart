import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'athlete_dashboard_page.dart';
import 'coach_dashboard_page.dart';
import 'member_dashboard_page.dart';
import 'complete_profile_page.dart';
import 'profiles_page.dart';
import 'admin_home_page.dart'; // ← Alteração: import adicionado

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

  Future<void> _loadDashboard() async {
    try {
      final user = supabase.auth.currentUser;
      if (user == null) {
        if (mounted) {
          Navigator.pushReplacementNamed(context, '/login');
        }
        return;
      }

      // Aguarda um pouco para garantir que o perfil foi criado
      await Future.delayed(const Duration(milliseconds: 500));

      final profile = await supabase
          .from('profiles')
          .select()
          .eq('id', user.id)
          .maybeSingle();

      if (!mounted) return;

      final userType = profile?['user_type'] ?? 'member';

      // Verifica se é atleta e se precisa completar o cadastro
      final fullName = profile?['full_name'];
      final cpf = profile?['cpf'];
      final phone = profile?['phone'];

      final needsCompleteProfile = userType == 'athlete' &&
          (fullName == null ||
              fullName.toString().isEmpty ||
              cpf == null ||
              phone == null);

      if (needsCompleteProfile && mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => const CompleteProfilePage(),
          ),
        );
        return;
      }

      Widget dashboard;
      // Define o widget baseado no tipo
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
          dashboard =
              const AdminHomePage(); // ← Alteração: redireciona para AdminHomePage
          break;
        default:
          dashboard = const ProfilesPage();
      }

      setState(() {
        _dashboardWidget = dashboard;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('❌ Erro ao carregar dashboard: $e');
      if (mounted) {
        setState(() {
          _dashboardWidget = const ProfilesPage();
          _isLoading = false;
        });
      }
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
