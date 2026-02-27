import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'athlete_dashboard_page.dart';
import 'coach_dashboard_page.dart';
import 'member_dashboard_page.dart'; // ← Adicionado: import do Member
import 'profiles_page.dart';

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
          .select('user_type')
          .eq('id', user.id)
          .maybeSingle();

      if (!mounted) return;

      final userType = profile?['user_type'] ?? 'member';

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
          dashboard = const MemberDashboardPage(); // ← Adicionado: case member
          break;
        case 'admin':
          dashboard = const ProfilesPage();
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
