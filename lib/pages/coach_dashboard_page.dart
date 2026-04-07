import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'admin_competitions_page.dart';

class CoachDashboardPage extends StatefulWidget {
  const CoachDashboardPage({super.key});

  @override
  State<CoachDashboardPage> createState() => _CoachDashboardPageState();
}

class _CoachDashboardPageState extends State<CoachDashboardPage>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final supabase = Supabase.instance.client;

  bool _isLoading = true;
  bool _isBackgroundReady = false;
  int _competitionNewCount = 0;
  DateTime? _lastCompetitionsViewedAt;
  RealtimeChannel? _competitionsRealtimeChannel;

  static const Color olympusBlue = Color(0xFF1E3A5F);
  static const Color olympusGold = Color(0xFFD4AF37);
  static const Color olympusLightBlue = Color(0xFF2C5F8D);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshDashboard();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    if (!_isBackgroundReady) {
      precacheImage(
        const AssetImage('assets/images/monte_olimpo_v2.png'),
        context,
      ).whenComplete(() {
        if (mounted) {
          setState(() {
            _isBackgroundReady = true;
          });
        }
      });
    }
  }

  Future<void> _refreshDashboard() async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
    });

    await _loadCompetitionNewCount();

    if (mounted) {
      setState(() {
        _isLoading = false;
      });
      _setupRealtimeListeners();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshDashboard();
    }
  }

  Future<void> _redirectToLogin() async {
    await supabase.auth.signOut();
    if (mounted) {
      Navigator.pushNamedAndRemoveUntil(
        context,
        '/login',
        (route) => false,
      );
    }
  }

  DateTime? _getPersistedCompetitionsViewedAt() {
    final user = supabase.auth.currentUser;
    final raw = user?.userMetadata?['last_competitions_viewed_at'];
    if (raw == null) return null;
    return DateTime.tryParse(raw.toString())?.toLocal();
  }

  Future<void> _loadCompetitionNewCount() async {
    try {
      final response = await supabase
          .from('events')
          .select('id, created_at, event_type')
          .inFilter('event_type', ['campeonato', 'amistoso']);

      final referenceDate = _lastCompetitionsViewedAt ??
          _getPersistedCompetitionsViewedAt() ??
          DateTime.now().subtract(const Duration(days: 7));

      int count = 0;
      for (final row in List<Map<String, dynamic>>.from(response)) {
        final createdAt =
            DateTime.tryParse((row['created_at'] ?? '').toString())?.toLocal();
        if (createdAt != null && createdAt.isAfter(referenceDate)) {
          count++;
        }
      }

      if (mounted) {
        setState(() {
          _competitionNewCount = count;
        });
      }
    } catch (e) {
      debugPrint('Erro ao carregar novidades de competições: $e');
    }
  }

  void _setupRealtimeListeners() {
    _competitionsRealtimeChannel ??=
        supabase.channel('coach-dashboard-competitions')
          ..onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'events',
            callback: (_) {
              _loadCompetitionNewCount();
            },
          )
          ..subscribe();
  }

  void _navigateToCompetitions() {
    final viewedAt = DateTime.now();

    setState(() {
      _lastCompetitionsViewedAt = viewedAt;
      _competitionNewCount = 0;
    });

    supabase.auth.updateUser(
      UserAttributes(
        data: {
          'last_competitions_viewed_at': viewedAt.toIso8601String(),
        },
      ),
    );

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const AdminCompetitionsPage(
          canEdit: false,
        ),
      ),
    ).then((_) => _loadCompetitionNewCount());
  }

  Widget _buildPremiumDashboardBackground() {
    return Stack(
      children: [
        Positioned.fill(
          child: Image.asset(
            'assets/images/monte_olimpo_v2.png',
            fit: BoxFit.cover,
            alignment: Alignment.center,
            errorBuilder: (context, error, stackTrace) {
              return Container(color: const Color(0xFF102845));
            },
          ),
        ),
        Positioned.fill(
          child: Container(
            color: Colors.black.withOpacity(0.10),
          ),
        ),
        Positioned.fill(
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  olympusBlue.withOpacity(0.48),
                  olympusLightBlue.withOpacity(0.20),
                  Colors.black.withOpacity(0.60),
                ],
              ),
            ),
          ),
        ),
        Positioned.fill(
          child: Container(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(0, -0.62),
                radius: 1.18,
                colors: [
                  olympusGold.withOpacity(0.11),
                  Colors.transparent,
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCoachInfoCard() {
    final fullName = supabase.auth.currentUser?.userMetadata?['full_name']
        ?.toString()
        .trim();
    final firstName = (fullName != null && fullName.isNotEmpty)
        ? fullName.split(' ').first
        : 'Técnico';

    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: Colors.white.withOpacity(0.20),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.25),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
          BoxShadow(
            color: olympusGold.withOpacity(0.12),
            blurRadius: 24,
            spreadRadius: 1,
          ),
        ],
        gradient: const LinearGradient(
          colors: [
            Color(0xFF0D223B),
            Color(0xFF123861),
            Color(0xFF235E94),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Stack(
          children: [
            Positioned(
              top: -40,
              right: -30,
              child: Container(
                width: 140,
                height: 140,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withOpacity(0.08),
                ),
              ),
            ),
            Positioned(
              bottom: -50,
              left: -30,
              child: Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: olympusGold.withOpacity(0.08),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
              child: Row(
                children: [
                  Container(
                    width: 90,
                    height: 90,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(24),
                      gradient: const LinearGradient(
                        colors: [
                          Color(0xFFF0D771),
                          Color(0xFFB48A23),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: olympusGold.withOpacity(0.45),
                          blurRadius: 12,
                          spreadRadius: 1,
                        ),
                        BoxShadow(
                          color: Colors.black.withOpacity(0.18),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    padding: const EdgeInsets.all(2.6),
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(22),
                        color: const Color(0xFF113457),
                      ),
                      child: const Icon(
                        Icons.sports,
                        size: 42,
                        color: Color(0xFFFFF2B8),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Olá, $firstName!',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            height: 1.1,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Área do Técnico',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: Colors.white.withOpacity(0.88),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(22),
                            gradient: const LinearGradient(
                              colors: [
                                Color(0xFFD7E3EE),
                                Color(0xFFBFCFDD),
                              ],
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                            ),
                            border: Border.all(
                              color: const Color(0xFF90A9BF),
                              width: 1.2,
                            ),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.verified_user_outlined,
                                size: 15,
                                color: Color(0xFF42576B),
                              ),
                              SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  'Painel premium do técnico',
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF2E4053),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            color: Colors.white.withOpacity(0.06),
                            border: Border.all(
                              color: olympusGold.withOpacity(0.22),
                            ),
                          ),
                          child: Text(
                            'Gerencie competições e acompanhe as novidades do painel.',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.88),
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
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

  Widget _buildDashboardCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
    int? badgeCount,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final screenWidth = MediaQuery.of(context).size.width;
        final availableWidth =
            constraints.maxWidth.isFinite ? constraints.maxWidth : screenWidth;
        final isCompact = availableWidth < 380;
        final horizontalMargin = isCompact ? 12.0 : 16.0;
        final verticalMargin = isCompact ? 8.0 : 10.0;
        final cardRadius = isCompact ? 18.0 : 20.0;
        final cardPadding = isCompact ? 16.0 : 18.0;
        final iconBoxSize = isCompact ? 54.0 : 60.0;
        final iconSize = isCompact ? 28.0 : 32.0;
        final titleSize = isCompact ? 17.0 : 18.0;
        final subtitleSize = isCompact ? 12.0 : 13.0;
        final arrowSize = isCompact ? 16.0 : 18.0;
        final badgeTop = isCompact ? 10.0 : 12.0;
        final badgeRight = isCompact ? 10.0 : 12.0;

        return Container(
          margin: EdgeInsets.symmetric(
            horizontal: horizontalMargin,
            vertical: verticalMargin,
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(cardRadius),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(cardRadius),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.white.withOpacity(0.24),
                          Colors.white.withOpacity(0.16),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(cardRadius),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.22),
                          blurRadius: 18,
                          offset: const Offset(0, 8),
                        ),
                        BoxShadow(
                          color: color.withOpacity(0.14),
                          blurRadius: 14,
                          spreadRadius: 0.8,
                        ),
                      ],
                      border: Border.all(
                        color: Colors.white.withOpacity(0.34),
                        width: 1.25,
                      ),
                    ),
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Positioned(
                          top: -20,
                          right: -12,
                          child: Container(
                            width: isCompact ? 68 : 76,
                            height: isCompact ? 68 : 76,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white.withOpacity(0.10),
                            ),
                          ),
                        ),
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: Container(
                            height: 1,
                            color: Colors.white.withOpacity(0.10),
                          ),
                        ),
                        Padding(
                          padding: EdgeInsets.all(cardPadding),
                          child: Row(
                            children: [
                              Container(
                                width: iconBoxSize,
                                height: iconBoxSize,
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.10),
                                  borderRadius: BorderRadius.circular(
                                    isCompact ? 14 : 16,
                                  ),
                                  border: Border.all(
                                    color: Colors.white.withOpacity(0.16),
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: color.withOpacity(0.16),
                                      blurRadius: 10,
                                      spreadRadius: 0.4,
                                    ),
                                  ],
                                ),
                                child: Icon(
                                  icon,
                                  size: iconSize,
                                  color: Colors.white,
                                ),
                              ),
                              SizedBox(width: isCompact ? 12 : 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: titleSize,
                                        fontWeight: FontWeight.w800,
                                        color: Colors.white,
                                        height: 1.05,
                                      ),
                                    ),
                                    SizedBox(height: isCompact ? 5 : 6),
                                    Text(
                                      subtitle,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: subtitleSize,
                                        color: Colors.white.withOpacity(0.88),
                                        fontWeight: FontWeight.w500,
                                        height: 1.22,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              SizedBox(width: isCompact ? 10 : 12),
                              Container(
                                width: isCompact ? 30 : 34,
                                height: isCompact ? 30 : 34,
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.08),
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.white.withOpacity(0.14),
                                  ),
                                ),
                                child: Icon(
                                  Icons.arrow_forward_ios_rounded,
                                  color: Colors.white.withOpacity(0.80),
                                  size: arrowSize,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (badgeCount != null && badgeCount > 0)
                          Positioned(
                            right: badgeRight,
                            top: badgeTop,
                            child: Container(
                              constraints: BoxConstraints(
                                minWidth: isCompact ? 24 : 26,
                              ),
                              padding: EdgeInsets.symmetric(
                                horizontal: isCompact ? 7 : 9,
                                vertical: isCompact ? 4 : 5,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.red,
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(
                                  color: Colors.white,
                                  width: 1.8,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.red.withOpacity(0.38),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Text(
                                badgeCount.toString(),
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: isCompact ? 11.5 : 12.5,
                                  fontWeight: FontWeight.w800,
                                  height: 1,
                                ),
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
        );
      },
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_competitionsRealtimeChannel != null) {
      supabase.removeChannel(_competitionsRealtimeChannel!);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF102845),
      appBar: _isLoading
          ? null
          : AppBar(
              title: const Text('Área do Técnico'),
              backgroundColor: olympusBlue,
              foregroundColor: Colors.white,
              actions: [
                IconButton(
                  icon: const Icon(Icons.logout),
                  tooltip: 'Sair',
                  onPressed: _redirectToLogin,
                ),
              ],
            ),
      body: Stack(
        children: [
          Positioned.fill(
            child: _buildPremiumDashboardBackground(),
          ),
          if (_isLoading)
            const Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            )
          else
            SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  _buildCoachInfoCard(),
                  _buildDashboardCard(
                    icon: Icons.emoji_events_outlined,
                    title: 'Competições',
                    subtitle: 'Veja ligas, campeonatos e amistosos',
                    color: const Color(0xFF2C5F8D),
                    onTap: _navigateToCompetitions,
                    badgeCount:
                        _competitionNewCount > 0 ? _competitionNewCount : null,
                  ),
                  const SizedBox(height: 100),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
