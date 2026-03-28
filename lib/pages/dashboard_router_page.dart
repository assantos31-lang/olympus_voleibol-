import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'athlete_dashboard_page.dart';
import 'coach_dashboard_page.dart';
import 'member_dashboard_page.dart';
import 'complete_profile_page.dart';
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

  Future<void> _loadDashboard() async {
    try {
      final user = supabase.auth.currentUser;
      if (user == null) {
        if (mounted) {
          Navigator.pushReplacementNamed(context, '/login');
        }
        return;
      }

      await Future.delayed(const Duration(milliseconds: 500));

      final profile = await supabase
          .from('profiles')
          .select()
          .eq('id', user.id)
          .maybeSingle();

      if (!mounted) return;

      final userType = (profile?['user_type'] ?? 'member').toString();

      final fullName = profile?['full_name'];
      final cpf = profile?['cpf'];
      final phone = profile?['phone'];

      final needsCompleteProfile = userType == 'athlete' &&
          (fullName == null ||
              fullName.toString().isEmpty ||
              cpf == null ||
              phone == null);

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
          dashboard = const MemberDashboardPage();
      }

      if (!mounted) return;

      setState(() {
        _dashboardWidget = dashboard;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Erro ao carregar dashboard: $e');
      if (!mounted) return;
      setState(() {
        _dashboardWidget = const MemberDashboardPage();
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

    return _dashboardWidget ?? const MemberDashboardPage();
  }
}
