// lib/pages/dashboard_router_page.dart

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../main.dart';
import '../services/role_service.dart';
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
  final RoleService _roleService = RoleService();

  StreamSubscription<AuthState>? _authSubscription;

  bool _isLoading = true;
  bool _isRedirecting = false;
  Widget? _dashboardWidget;

  // Papéis disponíveis para o usuário logado
  List<String> _availableRoles = [];
  String _activeRole = '';

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

  // ─── Helpers (mantidos idênticos ao original) ───────────────────────────────

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

  // ─── Roteamento por papel ───────────────────────────────────────────────────

  Widget _widgetForRole(String role) {
    switch (role) {
      case 'admin':
        return const AdminHomePage();
      case 'coach':
      case 'tecnico':
      case 'técnico':
      case 'treinador':
        return const CoachDashboardPage();
      default:
        return const AthleteDashboardPage();
    }
  }

  // ─── Carregamento principal ─────────────────────────────────────────────────

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
            'user_type, full_name, cpf, phone, rg, avatar_url, is_active, '
            'coach_team_gender, cep, address_street, address_number, '
            'address_neighborhood, address_city, address_state',
          )
          .eq('id', user.id)
          .maybeSingle();

      if (!mounted) return;

      // Usuário inativo → bloqueia (lógica original intacta)
      if (_isInactive(profile)) {
        await _restrictInactiveUser();
        return;
      }

      final userType = (profile?['user_type'] ?? 'member').toString();

      // Completar cadastro obrigatório (lógica original intacta)
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

      // ── NOVO: carrega múltiplos papéis ──────────────────────────────────────
      final roles = await _roleService.getUserRoles(user.id);

      // Garante ao menos um papel (fallback para user_type original)
      final effectiveRoles = roles.isNotEmpty ? roles : [userType];

      // Papel ativo inicial = papel primário (user_type)
      final initialRole =
          effectiveRoles.contains(userType) ? userType : effectiveRoles.first;

      if (!mounted) return;

      setState(() {
        _availableRoles = effectiveRoles;
        _activeRole = initialRole;
        _dashboardWidget = _widgetForRole(initialRole);
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _availableRoles = ['athlete'];
        _activeRole = 'athlete';
        _dashboardWidget = const AthleteDashboardPage();
        _isLoading = false;
      });
    }
  }

  // ─── Troca de papel em runtime ──────────────────────────────────────────────

  void _switchRole(String role) {
    if (role == _activeRole) return;

    setState(() {
      _activeRole = role;
      _dashboardWidget = _widgetForRole(role);
    });
  }

  void _showRoleSwitcher() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Trocar perfil',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF1E3A5F),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Você possui ${_availableRoles.length} perfil(is) disponível(is).',
                  style: const TextStyle(fontSize: 13, color: Colors.grey),
                ),
                const SizedBox(height: 16),
                ..._availableRoles.map((role) {
                  final isActive = role == _activeRole;
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      backgroundColor: isActive
                          ? const Color(0xFFD4AF37)
                          : Colors.grey.shade200,
                      child: Icon(
                        _iconForRole(role),
                        color: isActive ? const Color(0xFF1E3A5F) : Colors.grey,
                        size: 20,
                      ),
                    ),
                    title: Text(
                      RoleService.roleLabels[role] ?? role,
                      style: TextStyle(
                        fontWeight:
                            isActive ? FontWeight.w800 : FontWeight.w500,
                        color:
                            isActive ? const Color(0xFF1E3A5F) : Colors.black87,
                      ),
                    ),
                    trailing: isActive
                        ? const Icon(
                            Icons.check_circle,
                            color: Color(0xFFD4AF37),
                          )
                        : null,
                    onTap: () {
                      Navigator.pop(context);
                      _switchRole(role);
                    },
                  );
                }),
              ],
            ),
          ),
        );
      },
    );
  }

  IconData _iconForRole(String role) {
    switch (role) {
      case 'admin':
        return Icons.admin_panel_settings;
      case 'coach':
        return Icons.sports;
      case 'athlete':
        return Icons.sports_volleyball;
      default:
        return Icons.person;
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
      return const PremiumLoadingScreen(text: 'Carregando dashboard...');
    }

    if (_dashboardWidget == null) {
      return const LoginPageFallback();
    }

    // Só exibe o FAB de troca de papel se o usuário tiver mais de um papel
    if (_availableRoles.length <= 1) {
      return _dashboardWidget!;
    }

    return Stack(
      children: [
        _dashboardWidget!,
        Positioned(
          bottom: 24,
          right: 16,
          child: FloatingActionButton.extended(
            heroTag: 'role_switcher',
            onPressed: _showRoleSwitcher,
            backgroundColor: const Color(0xFFD4AF37),
            foregroundColor: const Color(0xFF1E3A5F),
            icon: const Icon(Icons.swap_horiz_rounded),
            label: Text(
              RoleService.roleLabels[_activeRole] ?? _activeRole,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Fallback (idêntico ao original) ───────────────────────────────────────────

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

    return const PremiumLoadingScreen(text: 'Redirecionando...');
  }
}
