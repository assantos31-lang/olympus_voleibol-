import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/auth_service.dart';
import 'agenda_page.dart';
import 'admin_financial_page.dart';
import 'admin_messages_page.dart';
import 'admin_birthdays_page.dart';
import 'admin_competitions_page.dart';
import 'admin_notifications_page.dart';

class AdminHomePage extends StatefulWidget {
  const AdminHomePage({super.key});

  @override
  State<AdminHomePage> createState() => _AdminHomePageState();
}

class _AdminHomePageState extends State<AdminHomePage> {
  final supabase = Supabase.instance.client;

  List<Map<String, dynamic>> monthBirthdays = [];
  bool isLoadingBirthdays = true;
  bool _showAllMonthBirthdays = false;
  int unreadNotificationsCount = 0;
  RealtimeChannel? _adminNotificationsChannel;

  @override
  void initState() {
    super.initState();
    _fetchMonthBirthdays();
    _fetchUnreadNotificationsCount();
    _listenForAdminNotifications();
  }

  @override
  void dispose() {
    if (_adminNotificationsChannel != null) {
      supabase.removeChannel(_adminNotificationsChannel!);
    }
    super.dispose();
  }

  Future<void> _fetchUnreadNotificationsCount() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    try {
      final response = await supabase
          .from('admin_notifications')
          .select('id')
          .eq('admin_id', user.id)
          .eq('is_read', false);

      if (mounted) {
        setState(() {
          unreadNotificationsCount = (response as List).length;
        });
      }
    } catch (e) {
      debugPrint('Erro ao buscar notificações não lidas: $e');
    }
  }

  void _listenForAdminNotifications() {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    _adminNotificationsChannel = supabase
        .channel('admin_home_notifications_${user.id}')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'admin_notifications',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'admin_id',
            value: user.id,
          ),
          callback: (_) => _fetchUnreadNotificationsCount(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'admin_notifications',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'admin_id',
            value: user.id,
          ),
          callback: (_) => _fetchUnreadNotificationsCount(),
        )
        .subscribe();
  }

  Future<void> _fetchMonthBirthdays() async {
    try {
      final now = DateTime.now();

      final response = await supabase
          .from('profiles')
          .select('full_name, birth_date, court_position')
          .not('birth_date', 'is', null);

      final allUsers = List<Map<String, dynamic>>.from(response);

      final filtered = allUsers.where((user) {
        final rawBirthDate = user['birth_date'];
        if (rawBirthDate == null || rawBirthDate.toString().trim().isEmpty) {
          return false;
        }

        final birthDate = DateTime.tryParse(rawBirthDate.toString());
        if (birthDate == null) return false;

        return birthDate.month == now.month;
      }).map((user) {
        final birthDate = DateTime.parse(user['birth_date'].toString());
        return {
          ...user,
          'birth': birthDate,
        };
      }).toList();

      filtered.sort((a, b) {
        final aBirth = a['birth'] as DateTime;
        final bBirth = b['birth'] as DateTime;
        return aBirth.day.compareTo(bBirth.day);
      });

      if (mounted) {
        setState(() {
          monthBirthdays = filtered;
          isLoadingBirthdays = false;
        });
      }
    } catch (e) {
      debugPrint('Erro ao buscar aniversariantes do mês: $e');
      if (mounted) {
        setState(() {
          isLoadingBirthdays = false;
        });
      }
    }
  }

  String _formatBirthDate(DateTime date) {
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    return '$day/$month';
  }

  String _formatPosition(dynamic value) {
    if (value == null || value.toString().trim().isEmpty) {
      return 'Sem posição';
    }
    return value.toString();
  }

  String _currentMonthLabel() {
    const months = [
      '',
      'Janeiro',
      'Fevereiro',
      'Março',
      'Abril',
      'Maio',
      'Junho',
      'Julho',
      'Agosto',
      'Setembro',
      'Outubro',
      'Novembro',
      'Dezembro',
    ];
    return months[DateTime.now().month];
  }

  Widget _buildMonthBirthdaysCard(BuildContext context) {
    const goldenColor = Color(0xFFE4C050);
    const cyanColor = Color(0xFF8FE8FF);

    final today = DateTime.now();
    final visibleBirthdays = _showAllMonthBirthdays
        ? monthBirthdays
        : monthBirthdays.take(5).toList();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: Colors.white.withOpacity(0.16),
          width: 1.2,
        ),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withOpacity(0.14),
            Colors.white.withOpacity(0.07),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: goldenColor.withOpacity(0.08),
            blurRadius: 18,
            spreadRadius: 1,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: goldenColor.withOpacity(0.14),
                      border: Border.all(
                        color: goldenColor.withOpacity(0.35),
                      ),
                    ),
                    child: const Icon(
                      Icons.cake_outlined,
                      color: Color(0xFFE4C050),
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Aniversariantes do mês',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.92),
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${_currentMonthLabel()} • ${monthBirthdays.length} ${monthBirthdays.length == 1 ? "aniversariante" : "aniversariantes"}',
                          style: TextStyle(
                            color: cyanColor.withOpacity(0.92),
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const AdminBirthdaysPage(),
                        ),
                      );
                    },
                    child: const Text('Ver todos'),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              if (isLoadingBirthdays)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 18),
                    child: SizedBox(
                      width: 26,
                      height: 26,
                      child: CircularProgressIndicator(strokeWidth: 2.4),
                    ),
                  ),
                )
              else if (monthBirthdays.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Text(
                    'Nenhum aniversariante neste mês.',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.72),
                      fontSize: 14,
                    ),
                  ),
                )
              else ...[
                AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeInOut,
                  constraints: BoxConstraints(
                    maxHeight: _showAllMonthBirthdays ? 330 : 260,
                  ),
                  child: Scrollbar(
                    thumbVisibility: _showAllMonthBirthdays,
                    radius: const Radius.circular(999),
                    child: ListView.builder(
                      shrinkWrap: true,
                      padding: EdgeInsets.zero,
                      physics: _showAllMonthBirthdays
                          ? const BouncingScrollPhysics()
                          : const NeverScrollableScrollPhysics(),
                      itemCount: visibleBirthdays.length,
                      itemBuilder: (context, index) {
                        final user = visibleBirthdays[index];
                        final birthDate = user['birth'] as DateTime;
                        final fullName =
                            (user['full_name'] ?? 'Sem nome').toString();
                        final position =
                            _formatPosition(user['court_position']);
                        final isToday = birthDate.day == today.day &&
                            birthDate.month == today.month;

                        return Container(
                          width: double.infinity,
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 11,
                          ),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            color: isToday
                                ? goldenColor.withOpacity(0.18)
                                : Colors.white.withOpacity(0.06),
                            border: Border.all(
                              color: isToday
                                  ? goldenColor.withOpacity(0.65)
                                  : Colors.white.withOpacity(0.08),
                              width: isToday ? 1.4 : 1,
                            ),
                            boxShadow: isToday
                                ? [
                                    BoxShadow(
                                      color: goldenColor.withOpacity(0.22),
                                      blurRadius: 14,
                                      spreadRadius: 0.5,
                                    ),
                                  ]
                                : null,
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 34,
                                height: 34,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: isToday
                                      ? goldenColor.withOpacity(0.24)
                                      : cyanColor.withOpacity(0.10),
                                  border: Border.all(
                                    color: isToday
                                        ? goldenColor.withOpacity(0.65)
                                        : cyanColor.withOpacity(0.22),
                                  ),
                                ),
                                child: Icon(
                                  isToday
                                      ? Icons.celebration_rounded
                                      : Icons.cake_outlined,
                                  color: isToday ? goldenColor : cyanColor,
                                  size: 18,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            fullName,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              color: Colors.white
                                                  .withOpacity(0.92),
                                              fontSize: 14,
                                              fontWeight: isToday
                                                  ? FontWeight.w800
                                                  : FontWeight.w600,
                                              height: 1.2,
                                            ),
                                          ),
                                        ),
                                        if (isToday) ...[
                                          const SizedBox(width: 8),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 3,
                                            ),
                                            decoration: BoxDecoration(
                                              borderRadius:
                                                  BorderRadius.circular(999),
                                              color:
                                                  goldenColor.withOpacity(0.22),
                                              border: Border.all(
                                                color: goldenColor
                                                    .withOpacity(0.55),
                                              ),
                                            ),
                                            child: const Text(
                                              'Hoje 🎉',
                                              style: TextStyle(
                                                color: Color(0xFFE4C050),
                                                fontSize: 10.5,
                                                fontWeight: FontWeight.w800,
                                                height: 1,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '${_formatBirthDate(birthDate)} • $position',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: isToday
                                            ? goldenColor.withOpacity(0.95)
                                            : Colors.white.withOpacity(0.68),
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w500,
                                        height: 1.2,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ),
                if (monthBirthdays.length > 5) ...[
                  const SizedBox(height: 4),
                  SizedBox(
                    width: double.infinity,
                    child: TextButton.icon(
                      onPressed: () {
                        setState(() {
                          _showAllMonthBirthdays = !_showAllMonthBirthdays;
                        });
                      },
                      icon: Icon(
                        _showAllMonthBirthdays
                            ? Icons.keyboard_arrow_up_rounded
                            : Icons.keyboard_arrow_down_rounded,
                        color: goldenColor,
                      ),
                      label: Text(
                        _showAllMonthBirthdays
                            ? 'Ver menos'
                            : 'Ver mais ${monthBirthdays.length - 5}',
                        style: const TextStyle(
                          color: goldenColor,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const goldenColor = Color(0xFFE4C050);
    const cyanColor = Color(0xFF8FE8FF);

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF0C2340),
              Color(0xFF123A63),
              Color(0xFF071A30),
            ],
          ),
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: Image.asset(
                'assets/images/monte_olimpo_v2.png',
                fit: BoxFit.cover,
                alignment: Alignment.center,
                errorBuilder: (context, error, stackTrace) {
                  return const SizedBox.shrink();
                },
              ),
            ),
            Positioned.fill(
              child: Container(
                color: Colors.black.withOpacity(0.35),
              ),
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _FuturisticBackgroundPainter(),
                ),
              ),
            ),
            SafeArea(
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Painel Administrativo',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.85),
                            fontSize: 17,
                            fontWeight: FontWeight.w500,
                            letterSpacing: 0.2,
                          ),
                        ),
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.06),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.10),
                            ),
                          ),
                          child: IconButton(
                            padding: EdgeInsets.zero,
                            icon: Icon(
                              Icons.logout_rounded,
                              color: Colors.white.withOpacity(0.85),
                              size: 22,
                            ),
                            onPressed: () async {
                              final authService = AuthService();
                              await authService.signOut();
                              if (context.mounted) {
                                Navigator.pushNamedAndRemoveUntil(
                                  context,
                                  '/login',
                                  (route) => false,
                                );
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Center(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 22, vertical: 12),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Stack(
                              clipBehavior: Clip.none,
                              alignment: Alignment.topCenter,
                              children: [
                                Container(
                                  width: double.infinity,
                                  margin: const EdgeInsets.only(top: 54),
                                  padding:
                                      const EdgeInsets.fromLTRB(20, 72, 20, 22),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(18),
                                    border: Border.all(
                                      color: Colors.white.withOpacity(0.16),
                                      width: 1.2,
                                    ),
                                    gradient: LinearGradient(
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                      colors: [
                                        Colors.white.withOpacity(0.18),
                                        Colors.white.withOpacity(0.08),
                                      ],
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: cyanColor.withOpacity(0.10),
                                        blurRadius: 24,
                                        spreadRadius: 1,
                                      ),
                                    ],
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(18),
                                    child: BackdropFilter(
                                      filter: ImageFilter.blur(
                                          sigmaX: 14, sigmaY: 14),
                                      child: Column(
                                        children: [
                                          Text(
                                            'Bem-vindo, Admin!',
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                              fontSize: 23,
                                              fontWeight: FontWeight.w500,
                                              color: Colors.white
                                                  .withOpacity(0.92),
                                              height: 1.15,
                                            ),
                                          ),
                                          const SizedBox(height: 10),
                                          Text(
                                            'Gerencie o sistema Olympus Voleibol',
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                              fontSize: 14,
                                              color: Colors.white
                                                  .withOpacity(0.68),
                                              fontWeight: FontWeight.w400,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                                Container(
                                  width: 118,
                                  height: 118,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    gradient: LinearGradient(
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                      colors: [
                                        const Color(0xFF42556F)
                                            .withOpacity(0.95),
                                        const Color(0xFF31445D)
                                            .withOpacity(0.88),
                                      ],
                                    ),
                                    border: Border.all(
                                      color: goldenColor.withOpacity(0.35),
                                      width: 2,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: goldenColor.withOpacity(0.20),
                                        blurRadius: 24,
                                        spreadRadius: 2,
                                      ),
                                    ],
                                  ),
                                  child: Center(
                                    child: ClipOval(
                                      child: Padding(
                                        padding: const EdgeInsets.all(4),
                                        child: Image.asset(
                                          'assets/images/olympus_logo.png',
                                          width: 108,
                                          height: 108,
                                          fit: BoxFit.contain,
                                          errorBuilder:
                                              (context, error, stackTrace) {
                                            return const Icon(
                                              Icons
                                                  .admin_panel_settings_rounded,
                                              size: 54,
                                              color: Color(0xFFE4C050),
                                            );
                                          },
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 22),
                            _buildMonthBirthdaysCard(context),
                            const SizedBox(height: 26),
                            _buildFuturisticButton(
                              context: context,
                              label: 'Notificações',
                              icon: Icons.notifications_active_outlined,
                              accentColor: const Color(0xFFFFD166),
                              badgeCount: unreadNotificationsCount,
                              onTap: () async {
                                await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) =>
                                        const AdminNotificationsPage(),
                                  ),
                                );
                                _fetchUnreadNotificationsCount();
                              },
                            ),
                            const SizedBox(height: 18),
                            _buildFuturisticButton(
                              context: context,
                              label: 'Agenda',
                              icon: Icons.calendar_month_rounded,
                              accentColor: cyanColor,
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => const AgendaPage(),
                                  ),
                                );
                              },
                            ),
                            const SizedBox(height: 18),
                            _buildFuturisticButton(
                              context: context,
                              label: 'Aniversariantes',
                              icon: Icons.cake_outlined,
                              accentColor: Colors.pinkAccent,
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) =>
                                        const AdminBirthdaysPage(),
                                  ),
                                );
                              },
                            ),
                            const SizedBox(height: 18),
                            _buildFuturisticButton(
                              context: context,
                              label: 'Competições',
                              icon: Icons.emoji_events_outlined,
                              accentColor: const Color(0xFF7CE7FF),
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) =>
                                        const AdminCompetitionsPage(
                                      canEdit: true,
                                    ),
                                  ),
                                );
                              },
                            ),
                            const SizedBox(height: 18),
                            _buildFuturisticButton(
                              context: context,
                              label: 'Financeiro',
                              icon: Icons.attach_money_rounded,
                              accentColor: cyanColor,
                              badgeCount: unreadNotificationsCount,
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) =>
                                        const AdminFinancialPage(),
                                  ),
                                );
                              },
                            ),
                            const SizedBox(height: 18),
                            _buildFuturisticButton(
                              context: context,
                              label: 'Gerenciar Usuários',
                              icon: Icons.groups_rounded,
                              accentColor: goldenColor,
                              isPrimary: true,
                              onTap: () {
                                Navigator.pushNamed(context, '/profiles');
                              },
                            ),
                            const SizedBox(height: 18),
                            _buildFuturisticButton(
                              context: context,
                              label: 'Mensagens',
                              icon: Icons.mark_chat_unread_outlined,
                              accentColor: const Color(0xFFFFD166),
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) =>
                                        const AdminMessagesPage(),
                                  ),
                                );
                              },
                            ),
                            const SizedBox(height: 12),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFuturisticButton({
    required BuildContext context,
    required String label,
    required IconData icon,
    required Color accentColor,
    required VoidCallback onTap,
    bool isPrimary = false,
    bool isMuted = false,
    int badgeCount = 0,
  }) {
    final Color baseTextColor = isMuted
        ? Colors.white.withOpacity(0.70)
        : Colors.white.withOpacity(0.88);

    return SizedBox(
      width: double.infinity,
      height: 66,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(
            left: 10,
            child: Container(
              width: 10,
              height: 42,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: accentColor.withOpacity(isPrimary ? 0.85 : 0.55),
                    blurRadius: 14,
                    spreadRadius: 1,
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            right: 10,
            child: Container(
              width: 10,
              height: 42,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: accentColor.withOpacity(isPrimary ? 0.85 : 0.45),
                    blurRadius: 14,
                    spreadRadius: 1,
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            top: 2,
            child: Container(
              width: 84,
              height: 4,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: accentColor.withOpacity(0.55),
                    blurRadius: 10,
                    spreadRadius: 0.5,
                  ),
                ],
              ),
            ),
          ),
          if (badgeCount > 0)
            Positioned(
              top: 0,
              right: 18,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.redAccent,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white, width: 1.4),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.redAccent.withOpacity(0.45),
                      blurRadius: 10,
                      spreadRadius: 1,
                    ),
                  ],
                ),
                child: Text(
                  badgeCount > 99 ? '99+' : badgeCount.toString(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: onTap,
                  child: Ink(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: accentColor.withOpacity(isPrimary ? 0.45 : 0.22),
                        width: 1.2,
                      ),
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: isPrimary
                            ? [
                                accentColor.withOpacity(0.28),
                                accentColor.withOpacity(0.12),
                              ]
                            : isMuted
                                ? [
                                    Colors.white.withOpacity(0.24),
                                    Colors.white.withOpacity(0.14),
                                  ]
                                : [
                                    Colors.white.withOpacity(0.12),
                                    Colors.white.withOpacity(0.06),
                                  ],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color:
                              accentColor.withOpacity(isPrimary ? 0.20 : 0.10),
                          blurRadius: 18,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                      child: Row(
                        children: [
                          Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: accentColor
                                  .withOpacity(isPrimary ? 0.16 : 0.10),
                              border: Border.all(
                                color: accentColor.withOpacity(0.30),
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: accentColor.withOpacity(0.35),
                                  blurRadius: 14,
                                  spreadRadius: 1,
                                ),
                              ],
                            ),
                            child: Icon(
                              icon,
                              color: isMuted
                                  ? Colors.white.withOpacity(0.82)
                                  : accentColor,
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 18),
                          Expanded(
                            child: Text(
                              label,
                              style: TextStyle(
                                color: baseTextColor,
                                fontSize: 17,
                                fontWeight: FontWeight.w400,
                                letterSpacing: 0.2,
                              ),
                            ),
                          ),
                          if (isPrimary)
                            Container(
                              width: 56,
                              alignment: Alignment.centerRight,
                              child: CustomPaint(
                                size: const Size(42, 26),
                                painter: _NodeLinesPainter(
                                  color: accentColor.withOpacity(0.55),
                                ),
                              ),
                            )
                          else
                            Container(
                              width: 56,
                              alignment: Alignment.centerRight,
                              child: CustomPaint(
                                size: const Size(42, 26),
                                painter: _NodeLinesPainter(
                                  color: Colors.white.withOpacity(0.22),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FuturisticBackgroundPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final wavePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..color = const Color(0xFFB7F1FF).withOpacity(0.08)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);

    final wavePaint2 = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..color = const Color(0xFFD8FBFF).withOpacity(0.06)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);

    final path1 = Path();
    path1.moveTo(0, size.height * 0.18);
    path1.cubicTo(
      size.width * 0.20,
      size.height * 0.10,
      size.width * 0.35,
      size.height * 0.28,
      size.width * 0.52,
      size.height * 0.18,
    );
    path1.cubicTo(
      size.width * 0.68,
      size.height * 0.08,
      size.width * 0.82,
      size.height * 0.23,
      size.width,
      size.height * 0.15,
    );
    canvas.drawPath(path1, wavePaint);

    final path2 = Path();
    path2.moveTo(0, size.height * 0.80);
    path2.cubicTo(
      size.width * 0.18,
      size.height * 0.70,
      size.width * 0.36,
      size.height * 0.90,
      size.width * 0.56,
      size.height * 0.80,
    );
    path2.cubicTo(
      size.width * 0.74,
      size.height * 0.72,
      size.width * 0.86,
      size.height * 0.86,
      size.width,
      size.height * 0.78,
    );
    canvas.drawPath(path2, wavePaint2);

    final nodePaint = Paint()
      ..color = const Color(0xFFE8FCFF).withOpacity(0.12)
      ..style = PaintingStyle.fill;

    final linePaint = Paint()
      ..color = const Color(0xFFC7F6FF).withOpacity(0.10)
      ..strokeWidth = 1;

    final points = <Offset>[
      Offset(size.width * 0.72, size.height * 0.34),
      Offset(size.width * 0.82, size.height * 0.38),
      Offset(size.width * 0.90, size.height * 0.33),
      Offset(size.width * 0.76, size.height * 0.44),
      Offset(size.width * 0.88, size.height * 0.47),
      Offset(size.width * 0.69, size.height * 0.52),
      Offset(size.width * 0.83, size.height * 0.56),
      Offset(size.width * 0.93, size.height * 0.52),
      Offset(size.width * 0.73, size.height * 0.64),
      Offset(size.width * 0.86, size.height * 0.67),
    ];

    for (int i = 0; i < points.length - 1; i++) {
      canvas.drawLine(points[i], points[i + 1], linePaint);
    }
    canvas.drawLine(points[0], points[3], linePaint);
    canvas.drawLine(points[1], points[4], linePaint);
    canvas.drawLine(points[3], points[5], linePaint);
    canvas.drawLine(points[4], points[6], linePaint);
    canvas.drawLine(points[6], points[8], linePaint);
    canvas.drawLine(points[7], points[9], linePaint);

    for (final point in points) {
      canvas.drawCircle(point, 1.8, nodePaint);
    }

    final glowPaint = Paint()
      ..color = const Color(0xFFA4F0FF).withOpacity(0.07)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 26);

    canvas.drawCircle(
      Offset(size.width * 0.20, size.height * 0.25),
      70,
      glowPaint,
    );
    canvas.drawCircle(
      Offset(size.width * 0.78, size.height * 0.55),
      90,
      glowPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _NodeLinesPainter extends CustomPainter {
  final Color color;

  _NodeLinesPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = color
      ..strokeWidth = 1;

    final dotPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final points = <Offset>[
      Offset(size.width * 0.15, size.height * 0.70),
      Offset(size.width * 0.38, size.height * 0.30),
      Offset(size.width * 0.62, size.height * 0.55),
      Offset(size.width * 0.84, size.height * 0.22),
      Offset(size.width * 0.90, size.height * 0.78),
    ];

    canvas.drawLine(points[0], points[1], linePaint);
    canvas.drawLine(points[1], points[2], linePaint);
    canvas.drawLine(points[2], points[3], linePaint);
    canvas.drawLine(points[2], points[4], linePaint);

    for (final point in points) {
      canvas.drawCircle(point, 1.6, dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _NodeLinesPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}
