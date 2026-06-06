import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../main.dart';
import 'athlete_dashboard_page.dart';
import 'complete_profile_page.dart';
import 'admin_home_page.dart';
import 'coach_dashboard_page.dart';
import 'coach_complete_profile_page.dart';

class DashboardRouterPage extends StatefulWidget {
  const DashboardRouterPage({super.key});

  @override
  State<DashboardRouterPage> createState() => _DashboardRouterPageState();
}

class _DashboardRouterPageState extends State<DashboardRouterPage> {
  final SupabaseClient supabase = Supabase.instance.client;
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

  bool _isBlank(dynamic value) {
    return value == null || value.toString().trim().isEmpty;
  }

  bool _isInactive(Map<String, dynamic>? profile) {
    if (profile == null) return false;
    return profile['is_active'] == false;
  }

  bool _needsCompleteProfile({
    required String userType,
    required Map<String, dynamic>? profile,
  }) {
    if (profile == null) return false;

    final normalizedType = userType.trim().toLowerCase();
    final isAthlete = normalizedType == 'athlete' || normalizedType == 'atleta';
    final isCoach = normalizedType == 'coach' ||
        normalizedType == 'tecnico' ||
        normalizedType == 'técnico' ||
        normalizedType == 'treinador';

    if (!isAthlete && !isCoach) return false;

    final fullName = (profile['full_name'] ?? '').toString().trim();
    final hasCompleteName = fullName
            .split(RegExp(r'\s+'))
            .where((part) => part.trim().length >= 2)
            .length >=
        2;

    if (isAthlete) {
      return !hasCompleteName ||
          _isBlank(profile['cpf']) ||
          _isBlank(profile['phone']);
    }

    return !hasCompleteName ||
        _isBlank(profile['cpf']) ||
        _isBlank(profile['phone']) ||
        _isBlank(profile['rg']) ||
        _isBlank(profile['avatar_url']) ||
        _isBlank(profile['cep']) ||
        _isBlank(profile['address_street']) ||
        _isBlank(profile['address_number']) ||
        _isBlank(profile['address_neighborhood']) ||
        _isBlank(profile['address_city']) ||
        _isBlank(profile['address_state']);
  }

  Future<void> _restrictInactiveUser() async {
    await supabase.auth.signOut();

    if (!mounted || _isRedirecting) return;

    _isRedirecting = true;

    Navigator.pushNamedAndRemoveUntil(
      context,
      '/login',
      (route) => false,
    );

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Seu acesso está inativo. Entre em contato com a administração.',
        ),
        backgroundColor: Colors.red,
      ),
    );
  }

  Future<void> _loadDashboard() async {
    try {
      Session? session = supabase.auth.currentSession;
      User? user = supabase.auth.currentUser;

      if (session == null || user == null) {
        final response = await supabase.auth.refreshSession();
        session = response.session;
        user = response.user;
      }

      if (session == null || user == null) {
        if (mounted && !_isRedirecting) {
          _isRedirecting = true;
          Navigator.pushNamedAndRemoveUntil(
            context,
            '/login',
            (route) => false,
          );
        }
        return;
      }

      final profile = await supabase
          .from('profiles')
          .select(
            'user_type, full_name, cpf, phone, rg, avatar_url, is_active, coach_team_gender, cep, address_street, address_number, address_neighborhood, address_city, address_state',
          )
          .eq('id', user.id)
          .maybeSingle();

      if (!mounted) return;

      if (_isInactive(profile)) {
        await _restrictInactiveUser();
        return;
      }

      final userType = (profile?['user_type'] ?? 'member').toString();

      if (_needsCompleteProfile(userType: userType, profile: profile)) {
        final normalizedType = userType.trim().toLowerCase();
        final isCoach = normalizedType == 'coach' ||
            normalizedType == 'tecnico' ||
            normalizedType == 'técnico' ||
            normalizedType == 'treinador';

        if (!_isRedirecting) {
          _isRedirecting = true;
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => isCoach
                  ? const CoachCompleteProfilePage()
                  : const CompleteProfilePage(),
            ),
          );
        }
        return;
      }

      Widget dashboard;
      switch (userType) {
        case 'admin':
          dashboard = const AdminHomePage();
          break;
        case 'coach':
        case 'tecnico':
        case 'técnico':
        case 'treinador':
          dashboard = const CoachDashboardPage();
          break;
        default:
          dashboard = const AthleteDashboardPage();
      }

      if (!mounted) return;

      setState(() {
        _dashboardWidget = dashboard;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _dashboardWidget = const AthleteDashboardPage();
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
