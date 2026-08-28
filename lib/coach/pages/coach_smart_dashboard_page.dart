import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import '../../theme/olympus_theme.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CoachSmartDashboardPage extends StatefulWidget {
  const CoachSmartDashboardPage({super.key});

  @override
  State<CoachSmartDashboardPage> createState() =>
      _CoachSmartDashboardPageState();
}

class _CoachSmartDashboardPageState extends State<CoachSmartDashboardPage> {
  final SupabaseClient _supabase = Supabase.instance.client;

  static const Color olympusBlue = Color(0xFF1E3A5F);
  static const Color olympusLightBlue = Color(0xFF2C5F8D);
  static const Color olympusGold = Color(0xFFD4AF37);
  static const Color olympusPurple = Color(0xFF7C3AED);
  static const Color olympusBg = Color(0xFFF4F7FB);
  static const Color olympusText = Color(0xFF17324D);
  static const Color olympusMuted = Color(0xFF53657B);
  static const Color olympusBorder = Color(0xFFE4EDF5);
  static const Color olympusSuccess = Color(0xFF16A34A);
  static const Color olympusWarning = Color(0xFFF59E0B);
  static const Color olympusDanger = Color(0xFFDC2626);

  bool _loading = true;
  String? _error;

  String _scope = 'geral';
  String _period = 'mes';

  List<Map<String, dynamic>> _profiles = [];
  List<Map<String, dynamic>> _events = [];
  List<Map<String, dynamic>> _convocations = [];
  List<Map<String, dynamic>> _checkins = [];
  List<Map<String, dynamic>> _trainingEvaluations = [];
  List<Map<String, dynamic>> _matchScouts = [];

  @override
  void initState() {
    super.initState();
    _loadDashboard();
  }

  DateTime? _periodStart() {
    final now = DateTime.now();

    switch (_period) {
      case 'semana':
        return DateTime(now.year, now.month, now.day)
            .subtract(const Duration(days: 7));
      case 'mes':
        return DateTime(now.year, now.month, 1);
      case 'geral':
        return null;
      default:
        return DateTime(now.year, now.month, 1);
    }
  }

  String get _scopeLabel {
    switch (_scope) {
      case 'treinos':
        return 'Treinos';
      case 'campeonatos':
        return 'Campeonatos';
      default:
        return 'Geral';
    }
  }

  String get _periodLabel {
    switch (_period) {
      case 'semana':
        return 'Semana';
      case 'mes':
        return 'Mês';
      case 'geral':
        return 'Geral';
      default:
        return 'Mês';
    }
  }

  Future<List<Map<String, dynamic>>> _safeSelect(
    String table,
    String columns,
  ) async {
    try {
      final rows = await _supabase.from(table).select(columns);
      return List<Map<String, dynamic>>.from(rows as List);
    } catch (e) {
      debugPrint('Smart Dashboard: tabela $table indisponível: $e');
      return <Map<String, dynamic>>[];
    }
  }

  Future<void> _loadDashboard() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final user = _supabase.auth.currentUser;
      if (user == null) {
        throw Exception('Usuário não autenticado.');
      }

      final results = await Future.wait([
        _safeSelect(
          'profiles',
          'id, full_name, avatar_url, gender, user_type, created_at',
        ),
        _safeSelect(
          'events',
          'id, event_name, event_type, event_date, event_time, championship_name, created_at',
        ),
        _safeSelect(
          'convocations',
          'id, user_id, event_id, status, created_at',
        ),
        _safeSelect(
          'checkins',
          'id, user_id, event_id, check_in_status, created_at, checked_in_at',
        ),
        _safeSelect(
          'training_evaluations',
          'id, event_id, coach_id, athlete_id, tipo, slot, fundamento, motivo, observacao, score, created_at',
        ),
        _safeSelect(
          'match_scouts',
          'id, event_id, coach_id, athlete_id, set_number, '
              'saque_ponto, saque_erro, '
              'recepcao_boa, recepcao_erro, '
              'passe_bom, passe_erro, '
              'levantamento_bom, levantamento_erro, '
              'ataque_ponto, ataque_erro, '
              'largada_bola_boa, largada_bola_erro, '
              'bloqueio_ponto, bloqueio_erro, '
              'defesa_boa, defesa_erro, '
              'observacao, created_at, updated_at',
        ),
      ]);

      if (!mounted) return;
      setState(() {
        _profiles = results[0];
        _events = results[1];
        _convocations = results[2];
        _checkins = results[3];
        _trainingEvaluations = results[4];
        _matchScouts = results[5];
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Erro ao carregar Smart Dashboard: $e';
        _loading = false;
      });
    }
  }

  DateTime? _parseDate(dynamic value) {
    final raw = (value ?? '').toString().trim();
    if (raw.isEmpty) return null;

    final parsedIso = DateTime.tryParse(raw);
    if (parsedIso != null) return parsedIso.toLocal();

    try {
      final parts = raw.split('/');
      if (parts.length == 3) {
        return DateTime(
          int.parse(parts[2]),
          int.parse(parts[1]),
          int.parse(parts[0]),
        );
      }
    } catch (_) {}

    return null;
  }

  bool _isInsidePeriod(dynamic value) {
    final start = _periodStart();
    if (start == null) return true;

    final date = _parseDate(value);
    if (date == null) return false;

    return !date.isBefore(start);
  }

  int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse((value ?? '0').toString()) ?? 0;
  }

  String _eventType(String eventId) {
    if (eventId.isEmpty) return '';

    for (final event in _events) {
      if ((event['id'] ?? '').toString() == eventId) {
        return (event['event_type'] ?? '').toString().toLowerCase().trim();
      }
    }

    return '';
  }

  bool _isTrainingEvent(String eventId) {
    return _eventType(eventId) == 'treino';
  }

  bool _isChampionshipEvent(String eventId) {
    final type = _eventType(eventId);
    return type == 'campeonato' ||
        type == 'amistoso' ||
        type == 'jogo' ||
        type == 'liga';
  }

  bool _scopeMatchesEvent(String eventId) {
    if (_scope == 'geral') return true;
    if (_scope == 'treinos') return _isTrainingEvent(eventId);
    if (_scope == 'campeonatos') return _isChampionshipEvent(eventId);
    return true;
  }

  List<Map<String, dynamic>> get _athletes {
    final list = _profiles.where((profile) {
      final userType = (profile['user_type'] ?? '').toString().toLowerCase();
      return userType == 'athlete' || userType == 'atleta';
    }).toList();

    list.sort((a, b) {
      return (a['full_name'] ?? '')
          .toString()
          .compareTo((b['full_name'] ?? '').toString());
    });

    return list;
  }

  List<Map<String, dynamic>> get _periodEvents {
    return _events.where((event) {
      final eventId = (event['id'] ?? '').toString();
      if (!_scopeMatchesEvent(eventId)) return false;

      final date =
          _parseDate(event['event_date']) ?? _parseDate(event['created_at']);

      final start = _periodStart();
      if (start == null) return true;
      if (date == null) return false;

      return !date.isBefore(start);
    }).toList();
  }

  Set<String> get _periodEventIds {
    return _periodEvents
        .map((event) => (event['id'] ?? '').toString())
        .where((id) => id.isNotEmpty)
        .toSet();
  }

  List<Map<String, dynamic>> get _periodConvocations {
    final eventIds = _periodEventIds;

    return _convocations.where((row) {
      final eventId = (row['event_id'] ?? '').toString();
      return eventIds.contains(eventId) && _scopeMatchesEvent(eventId);
    }).toList();
  }

  bool _isValidCheckin(Map<String, dynamic> row) {
    final status = (row['check_in_status'] ?? '').toString().toLowerCase();
    return status.contains('realizado') ||
        status.contains('checked') ||
        status.contains('success') ||
        status.contains('completed') ||
        status.contains('done') ||
        status.contains('ok');
  }

  List<Map<String, dynamic>> get _periodCheckins {
    final eventIds = _periodEventIds;

    return _checkins.where((row) {
      final eventId = (row['event_id'] ?? '').toString();
      if (!eventIds.contains(eventId)) return false;
      if (!_scopeMatchesEvent(eventId)) return false;

      final dateSource = row['checked_in_at'] ?? row['created_at'];
      return _isInsidePeriod(dateSource);
    }).toList();
  }

  List<Map<String, dynamic>> get _periodTrainingEvaluations {
    return _trainingEvaluations.where((row) {
      final eventId = (row['event_id'] ?? '').toString();

      if (_scope == 'campeonatos') return false;
      if (_scope == 'treinos' &&
          eventId.isNotEmpty &&
          !_isTrainingEvent(eventId)) {
        return false;
      }

      return _isInsidePeriod(row['created_at']);
    }).toList();
  }

  List<Map<String, dynamic>> get _periodMatchScouts {
    final eventIds = _periodEventIds;

    return _matchScouts.where((row) {
      final eventId = (row['event_id'] ?? '').toString();

      if (_scope == 'treinos') return false;
      if (eventId.isNotEmpty && !eventIds.contains(eventId)) return false;
      if (eventId.isNotEmpty && !_scopeMatchesEvent(eventId)) return false;

      final dateSource = row['updated_at'] ?? row['created_at'];
      return _isInsidePeriod(dateSource);
    }).toList();
  }

  int get _validCheckins {
    return _periodCheckins.where(_isValidCheckin).length;
  }

  int get _activeAthletes {
    final ids = <String>{};

    for (final row in _periodConvocations) {
      final id = (row['user_id'] ?? '').toString();
      if (id.isNotEmpty) ids.add(id);
    }

    for (final row in _periodCheckins) {
      final id = (row['user_id'] ?? '').toString();
      if (id.isNotEmpty) ids.add(id);
    }

    for (final row in _periodTrainingEvaluations) {
      final id = (row['athlete_id'] ?? '').toString();
      if (id.isNotEmpty) ids.add(id);
    }

    for (final row in _periodMatchScouts) {
      final id = (row['athlete_id'] ?? '').toString();
      if (id.isNotEmpty) ids.add(id);
    }

    return ids.isEmpty ? _athletes.length : ids.length;
  }

  int get _presencePercent {
    final convocados = _periodConvocations.length;
    if (convocados <= 0) return 0;

    return ((_validCheckins / convocados) * 100).round().clamp(0, 100);
  }

  int get _trainingScore {
    var total = 0;

    for (final row in _periodTrainingEvaluations) {
      final tipo = (row['tipo'] ?? '').toString().toLowerCase();
      final score = row['score'];

      if (score is num) {
        total += score.toInt();
      } else if (tipo == 'destaque') {
        total += 2;
      } else if (tipo == 'atencao' || tipo == 'atenção') {
        total -= 1;
      } else if (tipo == 'completa') {
        total += 1;
      }
    }

    return total;
  }

  int _positiveActionsFor(Map<String, dynamic> row) {
    return _toInt(row['saque_ponto']) +
        _toInt(row['recepcao_boa']) +
        _toInt(row['passe_bom']) +
        _toInt(row['levantamento_bom']) +
        _toInt(row['ataque_ponto']) +
        _toInt(row['largada_bola_boa']) +
        _toInt(row['bloqueio_ponto']) +
        _toInt(row['defesa_boa']);
  }

  int _errorsFor(Map<String, dynamic> row) {
    return _toInt(row['saque_erro']) +
        _toInt(row['recepcao_erro']) +
        _toInt(row['passe_erro']) +
        _toInt(row['levantamento_erro']) +
        _toInt(row['ataque_erro']) +
        _toInt(row['largada_bola_erro']) +
        _toInt(row['bloqueio_erro']) +
        _toInt(row['defesa_erro']);
  }

  int get _championshipPositiveActions {
    return _periodMatchScouts.fold<int>(
      0,
      (sum, row) => sum + _positiveActionsFor(row),
    );
  }

  int get _championshipErrors {
    return _periodMatchScouts.fold<int>(
      0,
      (sum, row) => sum + _errorsFor(row),
    );
  }

  int get _championshipEfficiency {
    final total = _championshipPositiveActions + _championshipErrors;
    if (total == 0) return 0;

    return ((_championshipPositiveActions / total) * 100).round().clamp(0, 100);
  }

  int get _engagementPercent {
    final totalSignals = _periodConvocations.length +
        _periodTrainingEvaluations.length +
        _periodMatchScouts.length;

    if (_activeAthletes <= 0) return 0;

    final base = totalSignals / math.max(1, _activeAthletes * 3);
    return (base * 100).round().clamp(0, 100);
  }

  int get _evolutionScore {
    if (_scope == 'campeonatos') {
      return ((_championshipPositiveActions / 5) - (_championshipErrors / 4))
          .round();
    }

    if (_scope == 'treinos') {
      return _trainingScore;
    }

    return (_trainingScore +
            ((_championshipPositiveActions / 5) - (_championshipErrors / 4)))
        .round();
  }

  Map<String, int> get _trainingHighlightsByFundament {
    final map = <String, int>{};

    for (final row in _periodTrainingEvaluations) {
      final tipo = (row['tipo'] ?? '').toString().toLowerCase();
      final fundamento = (row['fundamento'] ?? '').toString().trim();

      if (fundamento.isEmpty) continue;
      if (tipo == 'destaque') {
        map[fundamento] = (map[fundamento] ?? 0) + 1;
      }
    }

    return map;
  }

  Map<String, int> get _trainingAttentionByFundament {
    final map = <String, int>{};

    for (final row in _periodTrainingEvaluations) {
      final tipo = (row['tipo'] ?? '').toString().toLowerCase();
      final fundamento = (row['fundamento'] ?? '').toString().trim();

      if (fundamento.isEmpty) continue;
      if (tipo == 'atencao' || tipo == 'atenção') {
        map[fundamento] = (map[fundamento] ?? 0) + 1;
      }
    }

    return map;
  }

  Map<String, int> get _championshipPositiveByFundament {
    final map = <String, int>{
      'Saque': 0,
      'Recepção': 0,
      'Levantamento': 0,
      'Ataque': 0,
      'Bloqueio': 0,
      'Defesa': 0,
    };

    for (final row in _periodMatchScouts) {
      map['Saque'] = map['Saque']! + _toInt(row['saque_ponto']);
      map['Recepção'] = map['Recepção']! + _toInt(row['recepcao_boa']);
      map['Levantamento'] =
          map['Levantamento']! + _toInt(row['levantamento_bom']);
      map['Ataque'] = map['Ataque']! + _toInt(row['ataque_ponto']);
      map['Bloqueio'] = map['Bloqueio']! + _toInt(row['bloqueio_ponto']);
      map['Defesa'] = map['Defesa']! + _toInt(row['defesa_boa']);
    }

    map.removeWhere((_, value) => value <= 0);
    return map;
  }

  Map<String, int> get _championshipErrorsByFundament {
    final map = <String, int>{
      'Saque': 0,
      'Recepção': 0,
      'Levantamento': 0,
      'Ataque': 0,
      'Bloqueio': 0,
      'Defesa': 0,
    };

    for (final row in _periodMatchScouts) {
      map['Saque'] = map['Saque']! + _toInt(row['saque_erro']);
      map['Recepção'] = map['Recepção']! + _toInt(row['recepcao_erro']);
      map['Levantamento'] =
          map['Levantamento']! + _toInt(row['levantamento_erro']);
      map['Ataque'] = map['Ataque']! + _toInt(row['ataque_erro']);
      map['Bloqueio'] = map['Bloqueio']! + _toInt(row['bloqueio_erro']);
      map['Defesa'] = map['Defesa']! + _toInt(row['defesa_erro']);
    }

    map.removeWhere((_, value) => value <= 0);
    return map;
  }

  Map<String, int> get _athleteRiskScore {
    final map = <String, int>{};

    for (final athlete in _athletes) {
      final id = (athlete['id'] ?? '').toString();
      if (id.isNotEmpty) map[id] = 0;
    }

    final athleteCheckins = <String, int>{};
    for (final row in _periodCheckins.where(_isValidCheckin)) {
      final id = (row['user_id'] ?? '').toString();
      if (id.isEmpty) continue;
      athleteCheckins[id] = (athleteCheckins[id] ?? 0) + 1;
    }

    final athleteConvocations = <String, int>{};
    for (final row in _periodConvocations) {
      final id = (row['user_id'] ?? '').toString();
      if (id.isEmpty) continue;
      athleteConvocations[id] = (athleteConvocations[id] ?? 0) + 1;
    }

    final athleteAttention = <String, int>{};
    for (final row in _periodTrainingEvaluations) {
      final tipo = (row['tipo'] ?? '').toString().toLowerCase();
      final id = (row['athlete_id'] ?? '').toString();
      if (id.isEmpty) continue;

      if (tipo == 'atencao' || tipo == 'atenção') {
        athleteAttention[id] = (athleteAttention[id] ?? 0) + 1;
      }
    }

    final athleteErrors = <String, int>{};
    for (final row in _periodMatchScouts) {
      final id = (row['athlete_id'] ?? '').toString();
      if (id.isEmpty) continue;
      athleteErrors[id] = (athleteErrors[id] ?? 0) + _errorsFor(row);
    }

    for (final id in map.keys.toList()) {
      final convocado = athleteConvocations[id] ?? 0;
      final presente = athleteCheckins[id] ?? 0;
      final atencoes = athleteAttention[id] ?? 0;
      final erros = athleteErrors[id] ?? 0;

      var risk = 0;

      if (convocado > 0 && presente == 0) risk += 3;
      if (convocado >= 2 && presente / math.max(1, convocado) < 0.5) risk += 2;
      risk += atencoes;
      risk += (erros / 3).floor();

      map[id] = risk;
    }

    map.removeWhere((_, value) => value <= 0);
    return map;
  }

  String _athleteName(String athleteId) {
    for (final athlete in _athletes) {
      if ((athlete['id'] ?? '').toString() == athleteId) {
        return (athlete['full_name'] ?? 'Atleta').toString();
      }
    }

    return 'Atleta';
  }

  String _leaderName() {
    final scores = <String, int>{};

    for (final row in _periodTrainingEvaluations) {
      final id = (row['athlete_id'] ?? '').toString();
      if (id.isEmpty) continue;

      final tipo = (row['tipo'] ?? '').toString().toLowerCase();
      final score = row['score'];

      var value = 0;
      if (score is num) {
        value = score.toInt();
      } else if (tipo == 'destaque') {
        value = 2;
      } else if (tipo == 'atencao' || tipo == 'atenção') {
        value = -1;
      }

      scores[id] = (scores[id] ?? 0) + value;
    }

    for (final row in _periodMatchScouts) {
      final id = (row['athlete_id'] ?? '').toString();
      if (id.isEmpty) continue;

      scores[id] =
          (scores[id] ?? 0) + _positiveActionsFor(row) - _errorsFor(row);
    }

    if (scores.isEmpty) return '';

    final ordered = scores.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    if (ordered.first.value <= 0) return '';

    return _athleteName(ordered.first.key);
  }

  List<_SmartDashboardInsight> get _insights {
    final items = <_SmartDashboardInsight>[];

    if (_scope != 'campeonatos' && _trainingAttentionByFundament.isNotEmpty) {
      final attention = _trainingAttentionByFundament.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));

      items.add(
        _SmartDashboardInsight(
          icon: Icons.warning_amber_rounded,
          title: '${attention.first.key} exige atenção',
          body:
              '${attention.first.value} ponto(s) de atenção foram registrados nos treinos.',
          color: olympusWarning,
        ),
      );
    }

    if (_scope != 'treinos' && _championshipErrorsByFundament.isNotEmpty) {
      final errors = _championshipErrorsByFundament.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));

      items.add(
        _SmartDashboardInsight(
          icon: Icons.sports_volleyball_rounded,
          title: '${errors.first.key} preocupa nos campeonatos',
          body:
              '${errors.first.value} erro(s) registrados nesse fundamento nos jogos avaliados.',
          color: olympusDanger,
        ),
      );
    }

    final risk = _athleteRiskScore.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    if (risk.isNotEmpty) {
      items.add(
        _SmartDashboardInsight(
          icon: Icons.health_and_safety_outlined,
          title: '${risk.length} atleta(s) em risco',
          body:
              'Há atletas com baixa presença, atenção recorrente ou erros concentrados.',
          color: olympusDanger,
        ),
      );
    }

    if (_scope != 'treinos' && _championshipPositiveByFundament.isNotEmpty) {
      final positives = _championshipPositiveByFundament.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));

      items.add(
        _SmartDashboardInsight(
          icon: Icons.trending_up_rounded,
          title: '${positives.first.key} é força nos jogos',
          body:
              '${positives.first.value} ação(ões) positiva(s) nesse fundamento.',
          color: olympusSuccess,
        ),
      );
    }

    final leader = _leaderName();
    if (leader.isNotEmpty) {
      items.add(
        _SmartDashboardInsight(
          icon: Icons.emoji_events_outlined,
          title: '$leader lidera o período',
          body: 'Maior combinação de score, presença e desempenho no painel.',
          color: olympusSuccess,
        ),
      );
    }

    if (_presencePercent < 50 && _periodConvocations.isNotEmpty) {
      items.add(
        _SmartDashboardInsight(
          icon: Icons.event_busy_outlined,
          title: 'Presença abaixo do ideal',
          body:
              'A presença média está em $_presencePercent%. Revise convocações e disponibilidade.',
          color: olympusWarning,
        ),
      );
    }

    if (items.isEmpty) {
      items.add(
        const _SmartDashboardInsight(
          icon: Icons.check_circle_outline_rounded,
          title: 'Sem alertas críticos',
          body: 'Os dados do período não indicam riscos relevantes.',
          color: olympusSuccess,
        ),
      );
    }

    return items.take(6).toList();
  }

  Widget _background() {
    return Stack(
      children: [
        Positioned.fill(
          child: OlympusBrandBackgroundImage(
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) {
              return Container(color: const Color(0xFF102845));
            },
          ),
        ),
        Positioned.fill(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 2.2, sigmaY: 2.2),
            child: Container(color: Colors.transparent),
          ),
        ),
        Positioned.fill(
          child: Container(
            color: Colors.black.withOpacity(0.30),
          ),
        ),
        Positioned.fill(
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  olympusBlue.withOpacity(0.80),
                  olympusLightBlue.withOpacity(0.38),
                  Colors.black.withOpacity(0.68),
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

  Widget _glassCard({
    required List<Widget> children,
    EdgeInsetsGeometry? padding,
    EdgeInsetsGeometry? margin,
  }) {
    return Container(
      width: double.infinity,
      margin: margin ?? const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: Container(
            padding: padding ?? const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.94),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white.withOpacity(0.48)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.13),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: children,
            ),
          ),
        ),
      ),
    );
  }

  Widget _choiceButton({
    required String label,
    required bool selected,
    required VoidCallback onTap,
    IconData? icon,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 7),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(999),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 9),
            decoration: BoxDecoration(
              color: selected ? olympusGold : const Color(0xFF294F76),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: selected
                    ? const Color(0xFFF3D65C)
                    : Colors.white.withOpacity(0.20),
              ),
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color: olympusGold.withOpacity(0.22),
                        blurRadius: 8,
                      ),
                    ]
                  : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(
                    icon,
                    size: 15,
                    color: selected ? olympusBlue : Colors.white,
                  ),
                  const SizedBox(width: 5),
                ],
                Text(
                  label,
                  style: TextStyle(
                    color: selected ? olympusBlue : Colors.white,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _scopeSelector() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _choiceButton(
            label: 'Geral',
            icon: Icons.dashboard_rounded,
            selected: _scope == 'geral',
            onTap: () => setState(() => _scope = 'geral'),
          ),
          _choiceButton(
            label: 'Treinos',
            icon: Icons.fitness_center_rounded,
            selected: _scope == 'treinos',
            onTap: () => setState(() => _scope = 'treinos'),
          ),
          _choiceButton(
            label: 'Campeonatos',
            icon: Icons.emoji_events_rounded,
            selected: _scope == 'campeonatos',
            onTap: () => setState(() => _scope = 'campeonatos'),
          ),
        ],
      ),
    );
  }

  Widget _periodSelector() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _choiceButton(
            label: 'Semana',
            selected: _period == 'semana',
            onTap: () => setState(() => _period = 'semana'),
          ),
          _choiceButton(
            label: 'Mês',
            selected: _period == 'mes',
            onTap: () => setState(() => _period = 'mes'),
          ),
          _choiceButton(
            label: 'Geral',
            selected: _period == 'geral',
            onTap: () => setState(() => _period = 'geral'),
          ),
        ],
      ),
    );
  }

  Widget _header() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: const LinearGradient(
          colors: [
            Color(0xFF0D223B),
            Color(0xFF123861),
            Color(0xFF235E94),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: Colors.white.withOpacity(0.18), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: olympusGold.withOpacity(0.18),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
          BoxShadow(
            color: Colors.black.withOpacity(0.24),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            top: -40,
            right: -30,
            child: Container(
              width: 132,
              height: 132,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.07),
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.auto_graph_rounded,
                    color: olympusGold,
                    size: 27,
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Smart Dashboard',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 21,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Atualizar',
                    onPressed: _loadDashboard,
                    icon: const Icon(Icons.refresh_rounded),
                    color: Colors.white,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Insights inteligentes • $_scopeLabel • $_periodLabel',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.82),
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 12),
              _scopeSelector(),
              const SizedBox(height: 8),
              _periodSelector(),
            ],
          ),
        ],
      ),
    );
  }

  Widget _metricCard({
    required IconData icon,
    required String value,
    required String title,
    required String subtitle,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.94),
        borderRadius: BorderRadius.circular(19),
        border: Border.all(color: Colors.white.withOpacity(0.52)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.13),
            blurRadius: 16,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            right: -24,
            bottom: -24,
            child: Container(
              width: 66,
              height: 66,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color.withOpacity(0.07),
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(icon, color: color, size: 19),
              ),
              const SizedBox(height: 9),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: olympusBlue,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: olympusText,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: olympusMuted,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  height: 1.22,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _metricsGrid() {
    final trainingMode = _scope == 'treinos';
    final championshipMode = _scope == 'campeonatos';

    final cards = <Widget>[
      _metricCard(
        icon: Icons.groups_rounded,
        value: '$_activeAthletes',
        title: 'Atletas ativos',
        subtitle: 'Com atividade no período',
        color: const Color(0xFF2563EB),
      ),
      _metricCard(
        icon: Icons.fact_check_rounded,
        value: '$_presencePercent%',
        title: 'Presença média',
        subtitle: 'Check-ins / convocações',
        color: olympusSuccess,
      ),
      _metricCard(
        icon: trainingMode
            ? Icons.bolt_rounded
            : championshipMode
                ? Icons.sports_volleyball_rounded
                : Icons.auto_graph_rounded,
        value: championshipMode
            ? '$_championshipEfficiency%'
            : '$_engagementPercent%',
        title: championshipMode ? 'Eficiência de jogo' : 'Engajamento',
        subtitle: championshipMode
            ? 'Ações positivas / total'
            : 'Participação e avaliações',
        color: olympusWarning,
      ),
      _metricCard(
        icon: Icons.trending_up_rounded,
        value: _evolutionScore >= 0 ? '+$_evolutionScore' : '$_evolutionScore',
        title: 'Evolução',
        subtitle: _evolutionScore >= 0 ? 'Melhorando' : 'Exige atenção',
        color: _evolutionScore >= 0 ? olympusSuccess : olympusDanger,
      ),
    ];

    if (!trainingMode) {
      cards.add(
        _metricCard(
          icon: Icons.add_task_rounded,
          value: '$_championshipPositiveActions',
          title: 'Ações em jogos',
          subtitle: 'Scout de campeonatos',
          color: olympusPurple,
        ),
      );
      cards.add(
        _metricCard(
          icon: Icons.error_outline_rounded,
          value: '$_championshipErrors',
          title: 'Erros em jogos',
          subtitle: 'Fundamentos com falha',
          color: olympusDanger,
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final crossAxisCount = constraints.maxWidth >= 720 ? 3 : 2;
          final ratio = constraints.maxWidth < 390 ? 1.08 : 1.38;

          return GridView.count(
            crossAxisCount: crossAxisCount,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: ratio,
            children: cards,
          );
        },
      ),
    );
  }

  Widget _sectionTitle(String text, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: olympusGold, size: 24),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              color: olympusBlue,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ],
    );
  }

  Widget _insightsSection() {
    return _glassCard(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      children: [
        _sectionTitle('Insights inteligentes', Icons.lightbulb_outline_rounded),
        const SizedBox(height: 13),
        ..._insights.map((insight) {
          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              color: insight.color.withOpacity(0.09),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: insight.color.withOpacity(0.20)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(insight.icon, color: insight.color, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        insight.title,
                        style: TextStyle(
                          color: insight.color,
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        insight.body,
                        style: const TextStyle(
                          color: olympusMuted,
                          fontSize: 12.2,
                          fontWeight: FontWeight.w700,
                          height: 1.32,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _foundationLine({
    required String title,
    required int value,
    required String label,
    required Color color,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 9),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.07),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.16)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                color: olympusBlue,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          Text(
            '$value $label',
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _championshipBreakdownSection() {
    if (_scope == 'treinos') return const SizedBox.shrink();

    final positives = _championshipPositiveByFundament.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final errors = _championshipErrorsByFundament.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return _glassCard(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      children: [
        _sectionTitle(
          'Campeonatos por fundamento',
          Icons.emoji_events_rounded,
        ),
        const SizedBox(height: 12),
        if (positives.isEmpty && errors.isEmpty)
          const Text(
            'Sem scout de campeonato no período selecionado.',
            style: TextStyle(
              color: olympusMuted,
              fontWeight: FontWeight.w700,
            ),
          )
        else ...[
          ...positives.take(5).map(
                (entry) => _foundationLine(
                  title: entry.key,
                  value: entry.value,
                  label: 'ações',
                  color: olympusSuccess,
                ),
              ),
          ...errors.take(5).map(
                (entry) => _foundationLine(
                  title: entry.key,
                  value: entry.value,
                  label: 'erros',
                  color: olympusDanger,
                ),
              ),
        ],
      ],
    );
  }

  Widget _trainingBreakdownSection() {
    if (_scope == 'campeonatos') return const SizedBox.shrink();

    final positive = _trainingHighlightsByFundament.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final attention = _trainingAttentionByFundament.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return _glassCard(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      children: [
        _sectionTitle('Treinos por fundamento', Icons.fitness_center_rounded),
        const SizedBox(height: 12),
        if (positive.isEmpty && attention.isEmpty)
          const Text(
            'Sem avaliações de treino no período selecionado.',
            style: TextStyle(
              color: olympusMuted,
              fontWeight: FontWeight.w700,
            ),
          )
        else ...[
          ...positive.take(5).map(
                (entry) => _foundationLine(
                  title: entry.key,
                  value: entry.value,
                  label: 'destaques',
                  color: olympusSuccess,
                ),
              ),
          ...attention.take(5).map(
                (entry) => _foundationLine(
                  title: entry.key,
                  value: entry.value,
                  label: 'atenções',
                  color: olympusWarning,
                ),
              ),
        ],
      ],
    );
  }

  Widget _riskSection() {
    final risk = _athleteRiskScore.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return _glassCard(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 28),
      children: [
        _sectionTitle('Radar de atletas', Icons.health_and_safety_outlined),
        const SizedBox(height: 12),
        if (risk.isEmpty)
          const Text(
            'Nenhuma atleta em risco relevante no período.',
            style: TextStyle(
              color: olympusMuted,
              fontWeight: FontWeight.w700,
            ),
          )
        else
          ...risk.take(6).map((entry) {
            final name = _athleteName(entry.key);
            final high = entry.value >= 4;

            return Container(
              margin: const EdgeInsets.only(bottom: 9),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color:
                    (high ? olympusDanger : olympusWarning).withOpacity(0.08),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color:
                      (high ? olympusDanger : olympusWarning).withOpacity(0.18),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    high
                        ? Icons.priority_high_rounded
                        : Icons.info_outline_rounded,
                    color: high ? olympusDanger : olympusWarning,
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      name,
                      style: const TextStyle(
                        color: olympusBlue,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  Text(
                    'risco ${entry.value}',
                    style: TextStyle(
                      color: high ? olympusDanger : olympusWarning,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            );
          }),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: olympusBg,
      appBar: AppBar(
        title: const Text('Smart Dashboard'),
        backgroundColor: olympusBlue,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Atualizar',
            onPressed: _loadDashboard,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: Stack(
        children: [
          Positioned.fill(child: _background()),
          if (_loading)
            const Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            )
          else if (_error != null)
            Center(
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
            )
          else
            RefreshIndicator(
              onRefresh: _loadDashboard,
              child: ListView(
                padding: const EdgeInsets.only(bottom: 8),
                children: [
                  _header(),
                  _metricsGrid(),
                  _insightsSection(),
                  _championshipBreakdownSection(),
                  _trainingBreakdownSection(),
                  _riskSection(),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _SmartDashboardInsight {
  const _SmartDashboardInsight({
    required this.icon,
    required this.title,
    required this.body,
    required this.color,
  });

  final IconData icon;
  final String title;
  final String body;
  final Color color;
}
