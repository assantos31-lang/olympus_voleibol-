import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../main.dart';
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
  StreamSubscription<AuthState>? _authSubscription;
  bool _isLoading = true;
  bool _isRedirecting = false;
  Widget? _dashboardWidget;

  @override
  void initState() {
    super.initState();

    _authSubscription = supabase.auth.onAuthStateChange.listen((event) {
      if (!mounted || _isRedirecting) return;

      if (event.event == AuthChangeEvent.signedOut) {
        _isRedirecting = true;
        Navigator.pushNamedAndRemoveUntil(
          context,
          '/login',
          (route) => false,
        );
      }
    });

    _loadDashboard();
  }

  Future<void> _loadDashboard() async {
    try {
      Session? session = supabase.auth.currentSession;
      User? user = supabase.auth.currentUser;

      if (session == null || user == null) {
        await Future.delayed(const Duration(milliseconds: 1200));
        session = supabase.auth.currentSession;
        user = supabase.auth.currentUser;
      }

      if (session == null || user == null) {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _dashboardWidget = null;
          });
        }
        return;
      }

      final profile = await supabase
          .from('profiles')
          .select('user_type, full_name, cpf, phone')
          .eq('id', user.id)
          .maybeSingle()
          .timeout(const Duration(seconds: 10));

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
        if (!_isRedirecting) {
          _isRedirecting = true;
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => const CompleteProfilePage(),
            ),
          );
        }
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
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const PremiumLoadingScreen(
        text: 'Carregando dashboard...',
      );
    }

    if (_dashboardWidget == null) {
      return const LoginPageFallback();
    }

    return _dashboardWidget!;
  }
}

class LoginPageFallback extends StatelessWidget {
  const LoginPageFallback({super.key});

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Navigator.pushNamedAndRemoveUntil(
        context,
        '/login',
        (route) => false,
      );
    });

    return const PremiumLoadingScreen(
      text: 'Redirecionando...',
    );
  }
}
