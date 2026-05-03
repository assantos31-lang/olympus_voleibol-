import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'admin_athletes_statistics_page.dart';

class _AdminListResponsive {
  static double width(BuildContext context) =>
      MediaQuery.of(context).size.width;

  static bool isTablet(BuildContext context) =>
      width(context) >= 600 && width(context) < 1024;
  static bool isDesktop(BuildContext context) => width(context) >= 1024;

  static double horizontalMargin(BuildContext context) {
    if (isDesktop(context)) return 48;
    if (isTablet(context)) return 28;
    return 16;
  }

  static int athletesCrossAxisCount(
      BuildContext context, double availableWidth) {
    final width = availableWidth.isFinite
        ? availableWidth
        : _AdminListResponsive.width(context);
    if (width < 700) return 1;
    if (width < 1100) return 2;
    return 3;
  }
}

class AdminAthletesStatisticsListPage extends StatefulWidget {
  const AdminAthletesStatisticsListPage({super.key});

  static Route<void> route() {
    return MaterialPageRoute<void>(
      builder: (_) => const AdminAthletesStatisticsListPage(),
    );
  }

  @override
  State<AdminAthletesStatisticsListPage> createState() =>
      _AdminAthletesStatisticsListPageState();
}

class _AdminAthletesStatisticsListPageState
    extends State<AdminAthletesStatisticsListPage> {
  final SupabaseClient _supabase = Supabase.instance.client;

  static const Color olympusBlue = Color(0xFF1E3A5F);
  static const Color olympusGold = Color(0xFFD4AF37);
  static const Color olympusLightBlue = Color(0xFF2C5F8D);
  static const Color olympusBg = Color(0xFFF4F7FB);
  static const Color olympusMuted = Color(0xFF53657B);
  static const Color olympusBorder = Color(0xFFE4EDF5);
  static const Color olympusPurple = Color(0xFF7C3AED);

  bool _loading = true;
  String? _error;
  String _search = '';
  String _selectedGender = '';

  List<Map<String, dynamic>> _athletes = [];

  @override
  void initState() {
    super.initState();
    _loadAthletes();
  }

  Future<void> _loadAthletes() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final rows = await _supabase
          .from('profiles')
          .select(
            'id, full_name, email, phone, avatar_url, user_type, gender, court_position, performance_level, performance_level_rank',
          )
          .neq('user_type', 'admin')
          .order('full_name', ascending: true);

      if (!mounted) return;

      setState(() {
        _athletes = List<Map<String, dynamic>>.from(rows as List);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _error = 'Erro ao carregar atletas: $e';
        _loading = false;
      });
    }
  }

  String _asString(dynamic value) {
    return (value ?? '').toString().trim();
  }

  String _genderLabel(String gender) {
    final raw = gender.toLowerCase().trim();

    if (raw == 'f' || raw == 'female' || raw.contains('feminino')) {
      return 'Feminino';
    }

    if (raw == 'm' || raw == 'male' || raw.contains('masculino')) {
      return 'Masculino';
    }

    if (raw.isEmpty) return 'Não informado';

    return '${raw[0].toUpperCase()}${raw.substring(1)}';
  }

  String _initials(String name) {
    final parts = name
        .split(' ')
        .where((part) => part.trim().isNotEmpty)
        .map((part) => part.trim())
        .toList();

    if (parts.isEmpty) return '?';

    if (parts.length == 1) {
      return parts.first[0].toUpperCase();
    }

    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }

  List<Map<String, dynamic>> get _filteredAthletes {
    final query = _search.trim().toLowerCase();

    return _athletes.where((athlete) {
      final name = _asString(athlete['full_name']).toLowerCase();
      final email = _asString(athlete['email']).toLowerCase();
      final phone = _asString(athlete['phone']).toLowerCase();
      final position = _asString(athlete['court_position']).toLowerCase();
      final level = _asString(athlete['performance_level']).toLowerCase();
      final gender = _asString(athlete['gender']).toLowerCase();

      if (_selectedGender.isNotEmpty) {
        final selected = _selectedGender.toLowerCase();

        final genderMatch = selected == 'feminino'
            ? gender == 'f' || gender == 'female' || gender.contains('feminino')
            : gender == 'm' || gender == 'male' || gender.contains('masculino');

        if (!genderMatch) return false;
      }

      if (query.isEmpty) return true;

      return name.contains(query) ||
          email.contains(query) ||
          phone.contains(query) ||
          position.contains(query) ||
          level.contains(query);
    }).toList();
  }

  void _openStats(Map<String, dynamic> athlete) {
    final athleteId = _asString(athlete['id']);

    if (athleteId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Atleta sem ID válido.'),
        ),
      );
      return;
    }

    Navigator.push(
      context,
      AthleteStatisticsPage.route(
        athleteId: athleteId,
        adminView: true,
      ),
    );
  }

  Widget _background() {
    return Stack(
      children: [
        Positioned.fill(
          child: Image.asset(
            'assets/images/monte_olimpo_v2.png',
            fit: BoxFit.cover,
            alignment: Alignment.center,
            errorBuilder: (_, __, ___) {
              return Container(color: olympusBlue);
            },
          ),
        ),
        Positioned.fill(
          child: Container(color: Colors.black.withOpacity(0.45)),
        ),
        Positioned.fill(
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  olympusBlue.withOpacity(0.72),
                  olympusLightBlue.withOpacity(0.32),
                  Colors.black.withOpacity(0.70),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _header() {
    final total = _athletes.length;
    final filtered = _filteredAthletes.length;

    return Container(
      margin: EdgeInsets.fromLTRB(
        _AdminListResponsive.horizontalMargin(context),
        14,
        _AdminListResponsive.horizontalMargin(context),
        12,
      ),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          colors: [Color(0xFF0D223B), Color(0xFF123861), Color(0xFF235E94)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: Colors.white.withOpacity(0.18)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.24),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: olympusGold.withOpacity(0.16),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: olympusGold.withOpacity(0.42)),
            ),
            child: const Icon(
              Icons.query_stats_rounded,
              color: olympusGold,
              size: 28,
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Estatísticas dos Atletas',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 19,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$filtered de $total atleta(s)',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.78),
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _filters() {
    return Container(
      margin: EdgeInsets.fromLTRB(
        _AdminListResponsive.horizontalMargin(context),
        0,
        _AdminListResponsive.horizontalMargin(context),
        12,
      ),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.94),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withOpacity(0.52)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.12),
            blurRadius: 16,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: Column(
        children: [
          TextField(
            onChanged: (value) {
              setState(() => _search = value);
            },
            decoration: InputDecoration(
              hintText: 'Buscar atleta...',
              prefixIcon: const Icon(Icons.search_rounded),
              filled: true,
              fillColor: olympusBg,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 12,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: olympusBorder),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: olympusBorder),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: olympusBlue, width: 1.4),
              ),
            ),
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _filterChip(
                  label: 'Todos',
                  selected: _selectedGender.isEmpty,
                  onTap: () => setState(() => _selectedGender = ''),
                ),
                const SizedBox(width: 8),
                _filterChip(
                  label: 'Feminino',
                  selected: _selectedGender == 'feminino',
                  onTap: () => setState(() => _selectedGender = 'feminino'),
                ),
                const SizedBox(width: 8),
                _filterChip(
                  label: 'Masculino',
                  selected: _selectedGender == 'masculino',
                  onTap: () => setState(() => _selectedGender = 'masculino'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _filterChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      showCheckmark: false,
      selectedColor: olympusGold,
      backgroundColor: olympusBg,
      labelStyle: TextStyle(
        color: selected ? olympusBlue : olympusMuted,
        fontWeight: FontWeight.w900,
      ),
      side: BorderSide(
        color: selected ? olympusGold : olympusBorder,
      ),
      onSelected: (_) => onTap(),
    );
  }

  Widget _athleteCard(Map<String, dynamic> athlete) {
    final name = _asString(athlete['full_name']).isEmpty
        ? 'Sem nome'
        : _asString(athlete['full_name']);
    final avatarUrl = _asString(athlete['avatar_url']);
    final position = _asString(athlete['court_position']).isEmpty
        ? 'Sem posição'
        : _asString(athlete['court_position']);
    final gender = _genderLabel(_asString(athlete['gender']));
    final level = _asString(athlete['performance_level']);
    final email = _asString(athlete['email']);

    return Container(
      margin: EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => _openStats(athlete),
              child: Ink(
                padding: const EdgeInsets.all(13),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.94),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: Colors.white.withOpacity(0.54)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.12),
                      blurRadius: 14,
                      offset: const Offset(0, 7),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 29,
                      backgroundColor: olympusGold,
                      backgroundImage:
                          avatarUrl.isNotEmpty ? NetworkImage(avatarUrl) : null,
                      child: avatarUrl.isEmpty
                          ? Text(
                              _initials(name),
                              style: const TextStyle(
                                color: olympusBlue,
                                fontSize: 19,
                                fontWeight: FontWeight.w900,
                              ),
                            )
                          : null,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: olympusBlue,
                              fontSize: 15.5,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '$position • $gender',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: olympusMuted,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if (level.isNotEmpty || email.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              level.isNotEmpty ? level : email,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: olympusMuted.withOpacity(0.78),
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: olympusPurple.withOpacity(0.10),
                        borderRadius: BorderRadius.circular(15),
                        border: Border.all(
                          color: olympusPurple.withOpacity(0.18),
                        ),
                      ),
                      child: const Icon(
                        Icons.bar_chart_rounded,
                        color: olympusPurple,
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
  }

  Widget _body() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Text(
            _error!,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      );
    }

    final athletes = _filteredAthletes;

    return RefreshIndicator(
      onRefresh: _loadAthletes,
      child: ListView(
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        padding: const EdgeInsets.only(bottom: 28),
        children: [
          _header(),
          _filters(),
          if (athletes.isEmpty)
            Container(
              margin: EdgeInsets.fromLTRB(
                _AdminListResponsive.horizontalMargin(context),
                0,
                _AdminListResponsive.horizontalMargin(context),
                12,
              ),
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.94),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: Colors.white.withOpacity(0.54)),
              ),
              child: const Text(
                'Nenhum atleta encontrado para os filtros atuais.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: olympusMuted,
                  fontWeight: FontWeight.w800,
                ),
              ),
            )
          else
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: _AdminListResponsive.horizontalMargin(context),
              ),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final crossAxisCount =
                      _AdminListResponsive.athletesCrossAxisCount(
                    context,
                    constraints.maxWidth,
                  );

                  if (crossAxisCount == 1) {
                    return Column(
                      children: athletes
                          .map(
                            (athlete) => Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: _athleteCard(athlete),
                            ),
                          )
                          .toList(),
                    );
                  }

                  return GridView.builder(
                    itemCount: athletes.length,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: crossAxisCount,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      childAspectRatio: 3.3,
                    ),
                    itemBuilder: (context, index) =>
                        _athleteCard(athletes[index]),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: olympusBg,
      appBar: AppBar(
        title: const Text('Selecionar Atleta'),
        backgroundColor: olympusBlue,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Atualizar',
            onPressed: _loadAthletes,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: Stack(
        children: [
          Positioned.fill(child: _background()),
          _body(),
        ],
      ),
    );
  }
}
