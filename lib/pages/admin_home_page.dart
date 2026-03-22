import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/birthday_person.dart';
import '../services/auth_service.dart';
import '../services/birthday_service.dart';
import 'agenda_page.dart';
import 'admin_birthdays_page.dart';
import 'admin_financial_page.dart';
import 'championships_page.dart';
import 'chat_rooms_page.dart';

class AdminHomePage extends StatelessWidget {
  const AdminHomePage({super.key});

  static const Color olympusBlue = Color(0xFF1E3A5F);
  static const Color olympusGold = Color(0xFFD4AF37);
  static const Color olympusLightBlue = Color(0xFF2C5F8D);
  static const Color futuristicDark = Color(0xFF0B1420);
  static const Color futuristicCard = Color(0xFF122235);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: futuristicDark,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF09111B),
              Color(0xFF11253A),
              Color(0xFF1E3A5F),
            ],
          ),
        ),
        child: Stack(
          children: [
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
                    margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [
                          Color(0xFF122235),
                          Color(0xFF18324D),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: olympusGold.withOpacity(0.30)),
                      boxShadow: [
                        BoxShadow(
                          color: olympusGold.withOpacity(0.08),
                          blurRadius: 18,
                          spreadRadius: 1,
                        ),
                        BoxShadow(
                          color: Colors.black.withOpacity(0.35),
                          blurRadius: 22,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Painel Administrativo',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 19,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Olympus Voleibol',
                                style: TextStyle(
                                  color: olympusGold.withOpacity(0.95),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: olympusGold.withOpacity(0.14),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: olympusGold.withOpacity(0.25),
                            ),
                          ),
                          child: IconButton(
                            padding: EdgeInsets.zero,
                            icon: const Icon(
                              Icons.logout_rounded,
                              color: Colors.white,
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
                          horizontal: 16,
                          vertical: 12,
                        ),
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
                                  padding: const EdgeInsets.fromLTRB(
                                    20,
                                    72,
                                    20,
                                    22,
                                  ),
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(
                                      colors: [
                                        Color(0xFF122235),
                                        Color(0xFF18324D),
                                      ],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    ),
                                    borderRadius: BorderRadius.circular(22),
                                    border: Border.all(
                                      color: olympusGold.withOpacity(0.35),
                                      width: 1.2,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: olympusGold.withOpacity(0.08),
                                        blurRadius: 18,
                                        spreadRadius: 1,
                                      ),
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.35),
                                        blurRadius: 22,
                                        offset: const Offset(0, 8),
                                      ),
                                    ],
                                  ),
                                  child: Column(
                                    children: [
                                      const Text(
                                        'Bem-vindo, Admin!',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          fontSize: 24,
                                          fontWeight: FontWeight.w800,
                                          color: Colors.white,
                                          height: 1.15,
                                        ),
                                      ),
                                      const SizedBox(height: 10),
                                      Text(
                                        'Gerencie o sistema Olympus Voleibol',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: Colors.white.withOpacity(0.72),
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Container(
                                  width: 118,
                                  height: 118,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    gradient: LinearGradient(
                                      colors: [
                                        olympusGold.withOpacity(0.95),
                                        const Color(0xFFFFE08A),
                                      ],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: olympusGold.withOpacity(0.20),
                                        blurRadius: 24,
                                        spreadRadius: 2,
                                      ),
                                    ],
                                  ),
                                  padding: const EdgeInsets.all(3),
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: futuristicCard,
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: Colors.white.withOpacity(0.10),
                                      ),
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
                                                color: olympusGold,
                                              );
                                            },
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 24),
                            const _BirthdaysMonthCard(),
                            const SizedBox(height: 20),
                            _buildOlympusButton(
                              context: context,
                              label: 'Gerenciar Usuários',
                              icon: Icons.groups_rounded,
                              accentColor: olympusGold,
                              isPrimary: true,
                              onTap: () {
                                Navigator.pushNamed(context, '/profiles');
                              },
                            ),
                            const SizedBox(height: 16),
                            _buildOlympusButton(
                              context: context,
                              label: 'Agenda',
                              icon: Icons.calendar_month_rounded,
                              accentColor: olympusGold,
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => const AgendaPage(),
                                  ),
                                );
                              },
                            ),
                            const SizedBox(height: 16),
                            const _ChampionshipsCard(),
                            const SizedBox(height: 16),
                            _buildOlympusButton(
                              context: context,
                              label: 'Financeiro',
                              icon: Icons.attach_money_rounded,
                              accentColor: olympusLightBlue,
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
                            const SizedBox(height: 16),
                            _buildOlympusButton(
                              context: context,
                              label: 'Chats',
                              icon: Icons.chat_bubble_outline_rounded,
                              accentColor: Colors.white,
                              isMuted: true,
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => const ChatRoomsPage(),
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

  Widget _buildOlympusButton({
    required BuildContext context,
    required String label,
    required IconData icon,
    required Color accentColor,
    required VoidCallback onTap,
    bool isPrimary = false,
    bool isMuted = false,
  }) {
    final Color baseTextColor = isMuted
        ? Colors.white.withOpacity(0.76)
        : Colors.white.withOpacity(0.92);

    return Container(
      width: double.infinity,
      height: 74,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [
            Color(0xFF132235),
            Color(0xFF0E1B2A),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: accentColor.withOpacity(isPrimary ? 0.35 : 0.22),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.28),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
          BoxShadow(
            color: accentColor.withOpacity(isPrimary ? 0.10 : 0.05),
            blurRadius: 16,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: accentColor.withOpacity(isPrimary ? 0.16 : 0.10),
                    border: Border.all(
                      color: accentColor.withOpacity(0.30),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: accentColor.withOpacity(0.18),
                        blurRadius: 14,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                  child: Icon(
                    icon,
                    color:
                        isMuted ? Colors.white.withOpacity(0.85) : accentColor,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      color: baseTextColor,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.2,
                    ),
                  ),
                ),
                Container(
                  width: 56,
                  alignment: Alignment.centerRight,
                  child: CustomPaint(
                    size: const Size(42, 26),
                    painter: _NodeLinesPainter(
                      color: isPrimary
                          ? accentColor.withOpacity(0.55)
                          : Colors.white.withOpacity(0.22),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ChampionshipsCard extends StatelessWidget {
  const _ChampionshipsCard();

  static const Color olympusGold = Color(0xFFD4AF37);

  Future<int> _loadChampionshipsCount() async {
    final supabase = Supabase.instance.client;

    final response = await supabase
        .from('events')
        .select('championship_name')
        .not('championship_name', 'is', null);

    final championships = response
        .map((item) => (item['championship_name'] ?? '').toString().trim())
        .where((name) => name.isNotEmpty)
        .toSet();

    return championships.length;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<int>(
      future: _loadChampionshipsCount(),
      builder: (context, snapshot) {
        final count = snapshot.data ?? 0;

        return Container(
          width: double.infinity,
          constraints: const BoxConstraints(minHeight: 88),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [
                Color(0xFF1A2235),
                Color(0xFF132235),
                Color(0xFF0E1B2A),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: olympusGold.withOpacity(0.35),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.28),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
              BoxShadow(
                color: olympusGold.withOpacity(0.10),
                blurRadius: 16,
                spreadRadius: 1,
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(22),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const ChampionshipsPage(),
                  ),
                );
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 14,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: [
                            olympusGold.withOpacity(0.22),
                            olympusGold.withOpacity(0.10),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        border: Border.all(
                          color: olympusGold.withOpacity(0.38),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: olympusGold.withOpacity(0.18),
                            blurRadius: 16,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.emoji_events_rounded,
                        color: olympusGold,
                        size: 25,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Campeonatos',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.2,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            snapshot.connectionState == ConnectionState.waiting
                                ? 'Carregando ligas e campeonatos...'
                                : count == 0
                                    ? 'Nenhuma liga cadastrada ainda'
                                    : '$count campeonato${count > 1 ? 's' : ''} disponível${count > 1 ? 'is' : ''}',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.68),
                              fontSize: 12.5,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 7,
                          ),
                          decoration: BoxDecoration(
                            color: olympusGold.withOpacity(0.16),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: olympusGold.withOpacity(0.30),
                            ),
                          ),
                          child: snapshot.connectionState ==
                                  ConnectionState.waiting
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      olympusGold,
                                    ),
                                  ),
                                )
                              : Text(
                                  '$count',
                                  style: const TextStyle(
                                    color: olympusGold,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                        ),
                        const SizedBox(height: 8),
                        Icon(
                          Icons.arrow_forward_ios_rounded,
                          color: Colors.white.withOpacity(0.70),
                          size: 16,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _BirthdaysMonthCard extends StatelessWidget {
  const _BirthdaysMonthCard();

  static const Color olympusBlue = Color(0xFF1E3A5F);
  static const Color olympusGold = Color(0xFFD4AF37);
  static const Color olympusLightBlue = Color(0xFF2C5F8D);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<BirthdayPerson>>(
      future: BirthdayService().getBirthdaysOfMonth(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _buildContainer(
            child: const Padding(
              padding: EdgeInsets.all(24),
              child: Center(
                child: CircularProgressIndicator(color: olympusGold),
              ),
            ),
          );
        }

        if (snapshot.hasError) {
          return _buildContainer(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                'Erro ao carregar aniversariantes.',
                style: TextStyle(color: Colors.white70),
              ),
            ),
          );
        }

        final birthdays = snapshot.data ?? [];

        return _buildContainer(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
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
                        color: olympusGold.withOpacity(0.16),
                        border: Border.all(
                          color: olympusGold.withOpacity(0.35),
                        ),
                      ),
                      child: const Icon(
                        Icons.cake_rounded,
                        color: olympusGold,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Aniversariantes do mês',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.92),
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const AdminBirthdaysPage(),
                          ),
                        );
                      },
                      style: TextButton.styleFrom(
                        foregroundColor: olympusGold,
                      ),
                      child: const Text('Ver todos'),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                if (birthdays.isEmpty)
                  Text(
                    'Nenhum aniversariante neste mês.',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.72),
                      fontSize: 14,
                    ),
                  )
                else
                  ...birthdays.take(4).map(
                        (person) => Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            color: Colors.white.withOpacity(0.05),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.08),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.celebration_rounded,
                                color: olympusLightBlue.withOpacity(0.95),
                                size: 20,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  person.fullName,
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.90),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              Text(
                                person.formattedBirthday,
                                style: const TextStyle(
                                  color: olympusGold,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildContainer({required Widget child}) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [
            Color(0xFF122235),
            Color(0xFF18324D),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: olympusGold.withOpacity(0.35),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: olympusGold.withOpacity(0.08),
            blurRadius: 18,
            spreadRadius: 1,
          ),
          BoxShadow(
            color: Colors.black.withOpacity(0.35),
            blurRadius: 22,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _FuturisticBackgroundPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final wavePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..color = const Color(0xFFD4AF37).withOpacity(0.07)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);

    final wavePaint2 = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..color = const Color(0xFF8FE8FF).withOpacity(0.06)
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
      ..color = const Color(0xFFD4AF37).withOpacity(0.05)
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
