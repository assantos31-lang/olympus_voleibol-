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
  static const Color olympusSuccess = Color(0xFF16A34A);
  static const Color olympusWarning = Color(0xFFF59E0B);
  static const Color olympusDanger = Color(0xFFDC2626);

  bool _loading = true;
  String? _error;
  String _search = '';
  String _selectedGender = '';
  String _selectedStatus = '';

  List<Map<String, dynamic>> _athletes = [];
  Map<String, _AdminAthleteStats> _athleteStats = {};

  @override
  void initState() {
    super.initState();
    _loadAthletes();
  }

  String _normalizeEvaluationText(dynamic value) {
    final raw = (value ?? '').toString().trim().toLowerCase();

    if (raw.isEmpty) return '';

    return raw
        .replaceAll('ç', 'c')
        .replaceAll('ã', 'a')
        .replaceAll('á', 'a')
        .replaceAll('à', 'a')
        .replaceAll('â', 'a')
        .replaceAll('é', 'e')
        .replaceAll('ê', 'e')
        .replaceAll('í', 'i')
        .replaceAll('ó', 'o')
        .replaceAll('ô', 'o')
        .replaceAll('õ', 'o')
        .replaceAll('ú', 'u');
  }

  String _evaluationSearchText(Map<String, dynamic> row) {
    return [
      row['tipo'],
      row['slot'],
      row['motivo'],
      row['fundamento'],
      row['observacao'],
    ]
        .map(_normalizeEvaluationText)
        .where((value) => value.isNotEmpty)
        .join(' ');
  }

  bool _isDestaqueEvaluation(Map<String, dynamic> row) {
    final tipo = _normalizeEvaluationText(row['tipo']);
    if (tipo == 'destaque' || tipo == 'destaques') return true;

    final text = _evaluationSearchText(row);
    return text.contains('destaque') ||
        text.contains('destaques') ||
        text.contains('positivo') ||
        text.contains('ponto positivo') ||
        text.contains('elogio') ||
        text.contains('forte');
  }

  bool _isAtencaoEvaluation(Map<String, dynamic> row) {
    final tipo = _normalizeEvaluationText(row['tipo']);
    if (tipo == 'atencao' || tipo == 'atencoes') return true;

    final text = _evaluationSearchText(row);
    return text.contains('atencao') ||
        text.contains('ponto de atencao') ||
        text.contains('melhorar') ||
        text.contains('correcao');
  }

  bool _isCheckinDone(dynamic value) {
    final raw = (value ?? '').toString().trim().toLowerCase();

    if (raw.isEmpty) return true;

    if (raw == 'cancelado' ||
        raw == 'canceled' ||
        raw == 'cancelled' ||
        raw == 'erro' ||
        raw == 'error' ||
        raw == 'failed' ||
        raw == 'falhou') {
      return false;
    }

    return raw == 'realizado' ||
        raw == 'realizado com sucesso' ||
        raw == 'checked_in' ||
        raw == 'checkin_realizado' ||
        raw == 'check-in realizado' ||
        raw == 'presente' ||
        raw == 'presence' ||
        raw == 'ok' ||
        raw == 'success' ||
        raw == 'completed' ||
        raw == 'done' ||
        raw == 'manual' ||
        raw == 'late' ||
        raw == 'atrasado' ||
        raw == 'checkin_atrasado';
  }

  bool _isExplicitAbsenceStatus(dynamic value) {
    final raw = (value ?? '').toString().trim().toLowerCase();

    return raw == 'ausente' ||
        raw == 'absence' ||
        raw == 'absent' ||
        raw == 'faltou' ||
        raw == 'falta' ||
        raw == 'no_show' ||
        raw == 'nao_compareceu' ||
        raw == 'não_compareceu' ||
        raw == 'nao compareceu' ||
        raw == 'não compareceu';
  }

  Future<Map<String, _AdminAthleteStats>> _loadAthletesStats(
    Iterable<String> athleteIds,
  ) async {
    final ids = athleteIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();

    if (ids.isEmpty) return {};

    final stats = <String, _AdminAthleteStats>{
      for (final id in ids) id: const _AdminAthleteStats.empty(),
    };

    try {
      final rows = await _supabase
          .from('training_evaluations')
          .select(
            'athlete_id, tipo, slot, motivo, fundamento, observacao, created_at',
          )
          .inFilter('athlete_id', ids);

      for (final row in List<Map<String, dynamic>>.from(rows as List)) {
        final athleteId = (row['athlete_id'] ?? '').toString();
        if (athleteId.isEmpty) continue;

        final current = stats[athleteId] ?? const _AdminAthleteStats.empty();

        stats[athleteId] = current.copyWith(
          destaques: current.destaques + (_isDestaqueEvaluation(row) ? 1 : 0),
          atencoes: current.atencoes + (_isAtencaoEvaluation(row) ? 1 : 0),
        );
      }
    } catch (e) {
      debugPrint('Erro ao carregar avaliações dos atletas: $e');
    }

    try {
      final rows = await _supabase
          .from('checkins')
          .select('user_id, event_id, check_in_status')
          .inFilter('user_id', ids);

      final presenceByAthlete = <String, Set<String>>{};
      final explicitAbsenceByAthlete = <String, Set<String>>{};

      for (final row in List<Map<String, dynamic>>.from(rows as List)) {
        final athleteId = (row['user_id'] ?? '').toString();
        final eventId = (row['event_id'] ?? '').toString();

        if (athleteId.isEmpty || eventId.isEmpty) continue;

        if (_isCheckinDone(row['check_in_status'])) {
          presenceByAthlete
              .putIfAbsent(athleteId, () => <String>{})
              .add(eventId);
          continue;
        }

        if (_isExplicitAbsenceStatus(row['check_in_status'])) {
          explicitAbsenceByAthlete
              .putIfAbsent(athleteId, () => <String>{})
              .add(eventId);
        }
      }

      for (final athleteId in ids) {
        final presencas = presenceByAthlete[athleteId] ?? <String>{};
        final faltas = explicitAbsenceByAthlete[athleteId] ?? <String>{};

        // Mesma regra da estatística do atleta:
        // presença por check-in válido; falta somente por ausência explícita.
        // Pendente/vencido/convocado sem check-in NÃO vira falta.
        faltas.removeAll(presencas);

        final current = stats[athleteId] ?? const _AdminAthleteStats.empty();
        stats[athleteId] = current.copyWith(
          presencas: presencas.length,
          faltas: faltas.length,
        );
      }
    } catch (e) {
      debugPrint('Erro ao carregar check-ins dos atletas: $e');
    }

    return stats;
  }

  _AdminAthleteStats _statsFor(Map<String, dynamic> athlete) {
    final athleteId = _asString(athlete['id']);
    return _athleteStats[athleteId] ?? const _AdminAthleteStats.empty();
  }

  String _athleteStatusKey(Map<String, dynamic> athlete) {
    final stats = _statsFor(athlete);
    final hasFrequency = stats.baseFrequencia > 0;
    final hasEvaluation = stats.destaques > 0 || stats.atencoes > 0;

    if (!hasFrequency && !hasEvaluation) {
      return 'sem_dados';
    }

    // Crítico fica reservado para frequência realmente baixa.
    // Ponto de atenção NÃO deve transformar o atleta em crítico.
    if (hasFrequency && stats.presenceRate < 0.60) {
      return 'critico';
    }

    // Atenção cobre: frequência abaixo da meta, falta explícita ou pontos de atenção.
    // Ex.: Douglas com ponto de atenção deve aparecer como "Atenção", não "Crítico".
    if ((hasFrequency && stats.presenceRate < 0.80) ||
        stats.faltas > 0 ||
        stats.atencoes > 0) {
      return 'atencao';
    }

    if (hasFrequency &&
        stats.presenceRate >= 0.95 &&
        stats.faltas == 0 &&
        stats.destaques > 0) {
      return 'elite';
    }

    if ((hasFrequency && stats.presenceRate >= 0.80) || stats.destaques > 0) {
      return 'bom';
    }

    return 'sem_dados';
  }

  String _athleteStatusLabel(Map<String, dynamic> athlete) {
    switch (_athleteStatusKey(athlete)) {
      case 'elite':
        return 'Elite';
      case 'bom':
        return 'Boa';
      case 'atencao':
        return 'Atenção';
      case 'critico':
        return 'Crítico';
      default:
        return 'Sem dados';
    }
  }

  Color _athleteStatusColor(Map<String, dynamic> athlete) {
    switch (_athleteStatusKey(athlete)) {
      case 'elite':
        return olympusSuccess;
      case 'bom':
        return olympusLightBlue;
      case 'atencao':
        return olympusWarning;
      case 'critico':
        return olympusDanger;
      default:
        return olympusMuted;
    }
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

      final athletes = List<Map<String, dynamic>>.from(rows as List);
      final stats = await _loadAthletesStats(
        athletes.map((athlete) => _asString(athlete['id'])),
      );

      if (!mounted) return;

      setState(() {
        _athletes = athletes;
        _athleteStats = stats;
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
      final statusKey = _athleteStatusKey(athlete);
      final statusLabel = _athleteStatusLabel(athlete).toLowerCase();
      final normalizedStatusLabel = statusLabel
          .replaceAll('ç', 'c')
          .replaceAll('ã', 'a')
          .replaceAll('í', 'i');

      if (_selectedStatus.isNotEmpty && statusKey != _selectedStatus) {
        return false;
      }

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
          level.contains(query) ||
          statusLabel.contains(query) ||
          normalizedStatusLabel.contains(query);
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
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Status do atleta',
              style: TextStyle(
                color: olympusMuted.withOpacity(0.90),
                fontSize: 12,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(height: 7),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _filterChip(
                  label: 'Todos',
                  selected: _selectedStatus.isEmpty,
                  onTap: () => setState(() => _selectedStatus = ''),
                ),
                const SizedBox(width: 8),
                _statusFilterChip(
                  label: 'Elite',
                  value: 'elite',
                  color: olympusSuccess,
                ),
                const SizedBox(width: 8),
                _statusFilterChip(
                  label: 'Boa',
                  value: 'bom',
                  color: olympusLightBlue,
                ),
                const SizedBox(width: 8),
                _statusFilterChip(
                  label: 'Atenção',
                  value: 'atencao',
                  color: olympusWarning,
                ),
                const SizedBox(width: 8),
                _statusFilterChip(
                  label: 'Crítico',
                  value: 'critico',
                  color: olympusDanger,
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

  Widget _statusFilterChip({
    required String label,
    required String value,
    required Color color,
  }) {
    final selected = _selectedStatus == value;

    return ChoiceChip(
      label: Text(label),
      selected: selected,
      showCheckmark: false,
      selectedColor: color.withOpacity(0.18),
      backgroundColor: olympusBg,
      labelStyle: TextStyle(
        color: selected ? color : olympusMuted,
        fontWeight: FontWeight.w900,
      ),
      side: BorderSide(
        color: selected ? color : olympusBorder,
      ),
      onSelected: (_) =>
          setState(() => _selectedStatus = selected ? '' : value),
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
    final stats = _statsFor(athlete);
    final statusColor = _athleteStatusColor(athlete);
    final statusLabel = _athleteStatusLabel(athlete);

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
                  color: Color.alphaBlend(
                    statusColor.withOpacity(0.10),
                    Colors.white.withOpacity(0.94),
                  ),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(
                    color: statusColor.withOpacity(0.42),
                    width: 1.2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: statusColor.withOpacity(0.12),
                      blurRadius: 14,
                      offset: const Offset(0, 7),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: statusColor.withOpacity(0.78),
                          width: 2,
                        ),
                      ),
                      child: CircleAvatar(
                        radius: 29,
                        backgroundColor: olympusGold,
                        backgroundImage: avatarUrl.isNotEmpty
                            ? NetworkImage(avatarUrl)
                            : null,
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
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 6,
                            runSpacing: 5,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              _miniStatusBadge(
                                label: statusLabel,
                                color: statusColor,
                              ),
                              _miniInfoBadge(
                                label: stats.baseFrequencia == 0
                                    ? '--'
                                    : '${(stats.presenceRate * 100).round()}%',
                                icon: Icons.fact_check_rounded,
                                color: statusColor,
                              ),
                              _miniInfoBadge(
                                label: '${stats.destaques}',
                                icon: Icons.star_rounded,
                                color: olympusSuccess,
                              ),
                              _miniInfoBadge(
                                label: '${stats.atencoes}',
                                icon: Icons.warning_amber_rounded,
                                color: olympusWarning,
                              ),
                            ],
                          ),
                          if (level.isNotEmpty || email.isNotEmpty) ...[
                            const SizedBox(height: 5),
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
                        color: statusColor.withOpacity(0.13),
                        borderRadius: BorderRadius.circular(15),
                        border: Border.all(
                          color: statusColor.withOpacity(0.24),
                        ),
                      ),
                      child: Icon(
                        Icons.bar_chart_rounded,
                        color: statusColor,
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

  Widget _miniStatusBadge({
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.13),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.26)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  Widget _miniInfoBadge({
    required String label,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.09),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 12),
          const SizedBox(width: 3),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
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

class _AdminAthleteStats {
  const _AdminAthleteStats({
    required this.presencas,
    required this.faltas,
    required this.destaques,
    required this.atencoes,
  });

  const _AdminAthleteStats.empty()
      : presencas = 0,
        faltas = 0,
        destaques = 0,
        atencoes = 0;

  final int presencas;
  final int faltas;
  final int destaques;
  final int atencoes;

  int get baseFrequencia => presencas + faltas;

  double get presenceRate {
    if (baseFrequencia <= 0) return 0;
    return (presencas / baseFrequencia).clamp(0.0, 1.0).toDouble();
  }

  _AdminAthleteStats copyWith({
    int? presencas,
    int? faltas,
    int? destaques,
    int? atencoes,
  }) {
    return _AdminAthleteStats(
      presencas: presencas ?? this.presencas,
      faltas: faltas ?? this.faltas,
      destaques: destaques ?? this.destaques,
      atencoes: atencoes ?? this.atencoes,
    );
  }
}
