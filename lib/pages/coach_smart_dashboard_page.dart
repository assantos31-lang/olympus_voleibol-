import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/permission_service.dart';

class CoachSmartDashboardPage extends StatefulWidget {
  const CoachSmartDashboardPage({super.key});

  @override
  State<CoachSmartDashboardPage> createState() =>
      _CoachSmartDashboardPageState();
}

class _CoachSmartDashboardPageState extends State<CoachSmartDashboardPage> {
  final SupabaseClient _supabase = Supabase.instance.client;
  final PermissionService _permissionService = PermissionService();

  static const Color olympusBlue = Color(0xFF1E3A5F);
  static const Color olympusGold = Color(0xFFD4AF37);
  static const Color olympusLightBlue = Color(0xFF2C5F8D);

  bool _loading = true;
  String? _error;
  String _periodo = 'mes';

  _TeamDashboardData _data = _TeamDashboardData.empty();

  @override
  void initState() {
    super.initState();
    _loadDashboard();
  }

  DateTime? _getPeriodoInicio() {
    final now = DateTime.now();

    switch (_periodo) {
      case 'semana':
        return DateTime(
          now.year,
          now.month,
          now.day,
        ).subtract(const Duration(days: 7));
      case 'mes':
        return DateTime(now.year, now.month, 1);
      case 'geral':
        return null;
      default:
        return DateTime(now.year, now.month, 1);
    }
  }

  DateTime? _getPeriodoAnteriorInicio(DateTime? atualInicio) {
    if (atualInicio == null) return null;

    if (_periodo == 'semana') {
      return atualInicio.subtract(const Duration(days: 7));
    }

    if (_periodo == 'mes') {
      return DateTime(atualInicio.year, atualInicio.month - 1, 1);
    }

    return null;
  }

  String _getPeriodoLabel() {
    switch (_periodo) {
      case 'semana':
        return 'Últimos 7 dias';
      case 'mes':
        return 'Mês atual';
      case 'geral':
        return 'Geral';
      default:
        return 'Mês atual';
    }
  }

  String _normalizarFundamento(dynamic value) {
    final raw = (value ?? '').toString().trim().toLowerCase();

    if (raw.contains('saque')) return 'Saque';
    if (raw.contains('recep')) return 'Recepção';
    if (raw.contains('ataque')) return 'Ataque';
    if (raw.contains('defesa')) return 'Defesa';
    if (raw.contains('bloqueio')) return 'Bloqueio';
    if (raw.contains('fis') ||
        raw.contains('fís') ||
        raw.contains('condicionamento')) {
      return 'Físico';
    }

    return raw.isEmpty ? 'Sem fundamento' : _capitalize(raw);
  }

  String _capitalize(String value) {
    if (value.isEmpty) return value;
    return '${value[0].toUpperCase()}${value.substring(1)}';
  }

  bool _isCheckinRealizado(dynamic status) {
    final raw = (status ?? '').toString().trim().toLowerCase();

    return raw == 'realizado' ||
        raw == 'ok' ||
        raw == 'success' ||
        raw == 'completed' ||
        raw == 'done' ||
        raw == 'checked_in' ||
        raw == 'checkin_realizado';
  }

  DateTime? _parseDate(dynamic value) {
    final text = (value ?? '').toString().trim();
    if (text.isEmpty) return null;

    final iso = DateTime.tryParse(text);
    if (iso != null) return iso;

    final parts = text.split('/');
    if (parts.length == 3) {
      final day = int.tryParse(parts[0]);
      final month = int.tryParse(parts[1]);
      final year = int.tryParse(parts[2]);

      if (day != null && month != null && year != null) {
        return DateTime(year, month, day);
      }
    }

    return null;
  }

  bool _isInsidePeriod(dynamic dateValue, DateTime? inicio, {DateTime? fim}) {
    final parsed = _parseDate(dateValue);
    if (parsed == null) return false;

    final local = parsed.toLocal();

    if (inicio != null && local.isBefore(inicio)) return false;
    if (fim != null && !local.isBefore(fim)) return false;

    return true;
  }

  Future<List<Map<String, dynamic>>> _safeSelect(
    String table,
    String columns,
  ) async {
    try {
      final rows = await _supabase.from(table).select(columns);
      return List<Map<String, dynamic>>.from(rows as List);
    } catch (_) {
      return [];
    }
  }

  Future<void> _loadDashboard() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final data = await _buildDashboardData();

      if (!mounted) return;
      setState(() {
        _data = data;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Erro ao carregar dashboard inteligente: $e';
        _loading = false;
      });
    }
  }

  Future<_TeamDashboardData> _buildDashboardData() async {
    final periodoInicio = _getPeriodoInicio();
    final periodoAnteriorInicio = _getPeriodoAnteriorInicio(periodoInicio);

    final visibleRankingIds =
        (await _permissionService.getVisibleUserIdsForPage('ranking')).toSet();

    final visibleEvaluationIds =
        (await _permissionService.getVisibleUserIdsForPage('avaliacoes'))
            .toSet();

    final allowedAthleteIds = <String>{
      ...visibleRankingIds,
      ...visibleEvaluationIds,
    };

    if (allowedAthleteIds.isEmpty) {
      return _TeamDashboardData.empty(
        periodLabel: _getPeriodoLabel(),
        explanation:
            'Nenhum atleta está habilitado para ranking ou avaliações.',
      );
    }

    final profilesRows = await _supabase
        .from('profiles')
        .select('id, full_name, avatar_url, gender, user_type')
        .inFilter('id', allowedAthleteIds.toList())
        .eq('user_type', 'athlete')
        .order('full_name', ascending: true);

    final profiles = List<Map<String, dynamic>>.from(profilesRows as List);
    final athleteIds = profiles
        .map((e) => (e['id'] ?? '').toString())
        .where((id) => id.isNotEmpty)
        .toList();

    if (athleteIds.isEmpty) {
      return _TeamDashboardData.empty(
        periodLabel: _getPeriodoLabel(),
        explanation:
            'Nenhum perfil de atleta encontrado entre os usuários habilitados.',
      );
    }

    final evaluations = await _safeSelect(
      'training_evaluations',
      'athlete_id, tipo, score, fundamento, motivo, observacao, created_at',
    );

    final checkins = await _safeSelect(
      'checkins',
      'user_id, event_id, check_in_status, created_at',
    );

    final events = await _safeSelect(
      'events',
      'id, event_type, event_date, event_name',
    );

    final convocations = await _safeSelect(
      'convocations',
      'event_id, user_id, status',
    );

    final athleteMap = <String, _AthleteSmartMetric>{};

    for (final profile in profiles) {
      final id = (profile['id'] ?? '').toString();
      if (id.isEmpty) continue;

      athleteMap[id] = _AthleteSmartMetric(
        athleteId: id,
        name: (profile['full_name'] ?? 'Atleta').toString(),
        avatarUrl: (profile['avatar_url'] ?? '').toString(),
      );
    }

    int totalDestaques = 0;
    int totalAtencoes = 0;
    int totalAvaliacoes = 0;
    final attentionByFundament = <String, int>{};
    final scoreByDay = <DateTime, int>{};

    int currentScore = 0;
    int previousScore = 0;

    for (final row in evaluations) {
      final athleteId = (row['athlete_id'] ?? '').toString();
      final athlete = athleteMap[athleteId];
      if (athlete == null) continue;

      final createdAt = _parseDate(row['created_at']);
      final isCurrent = _isInsidePeriod(row['created_at'], periodoInicio);
      final isPrevious = periodoAnteriorInicio == null
          ? false
          : _isInsidePeriod(
              row['created_at'],
              periodoAnteriorInicio,
              fim: periodoInicio,
            );

      final tipo = (row['tipo'] ?? '').toString().trim().toLowerCase();
      final fundamento = _normalizarFundamento(row['fundamento']);

      int score = 0;
      if (tipo == 'destaque') {
        score = 2;
      } else if (tipo == 'atencao' || tipo == 'atenção') {
        score = -1;
      }

      if (isCurrent) {
        totalAvaliacoes++;
        currentScore += score;

        if (createdAt != null) {
          final day = DateTime(createdAt.year, createdAt.month, createdAt.day);
          scoreByDay[day] = (scoreByDay[day] ?? 0) + score;
        }

        athlete.score += score;
        athlete.evaluations++;
        athlete.lastEvaluation =
            _latestDate(athlete.lastEvaluation, createdAt?.toLocal());
        athlete.latestEvaluationTypes.add(tipo);

        if (tipo == 'destaque') {
          totalDestaques++;
          athlete.destaques++;
        } else if (tipo == 'atencao' || tipo == 'atenção') {
          totalAtencoes++;
          athlete.atencoes++;
          athlete.attentionFundaments[fundamento] =
              (athlete.attentionFundaments[fundamento] ?? 0) + 1;
          attentionByFundament[fundamento] =
              (attentionByFundament[fundamento] ?? 0) + 1;
        }
      } else if (isPrevious) {
        previousScore += score;
      }
    }

    final treinoEvents = events.where((event) {
      final eventType = (event['event_type'] ?? '').toString().toLowerCase();
      if (eventType != 'treino') return false;
      return _isInsidePeriod(event['event_date'], periodoInicio);
    }).toList();

    final treinoEventIds = treinoEvents
        .map((e) => (e['id'] ?? '').toString())
        .where((id) => id.isNotEmpty)
        .toSet();

    final checkedInKeys = <String>{};

    for (final row in checkins) {
      final eventId = (row['event_id'] ?? '').toString();
      final userId = (row['user_id'] ?? '').toString();

      if (!treinoEventIds.contains(eventId)) continue;
      if (!athleteMap.containsKey(userId)) continue;
      if (!_isCheckinRealizado(row['check_in_status'])) continue;

      checkedInKeys.add('$eventId|$userId');
      athleteMap[userId]!.presencas++;
      athleteMap[userId]!.score++;
    }

    int totalExpectedPresence = 0;
    int totalPresence = checkedInKeys.length;

    for (final row in convocations) {
      final eventId = (row['event_id'] ?? '').toString();
      final userId = (row['user_id'] ?? '').toString();
      final status = (row['status'] ?? '').toString().toLowerCase();

      if (!treinoEventIds.contains(eventId)) continue;
      if (!athleteMap.containsKey(userId)) continue;
      if (status != 'accepted') continue;

      totalExpectedPresence++;

      final key = '$eventId|$userId';
      if (!checkedInKeys.contains(key)) {
        athleteMap[userId]!.faltas++;
        athleteMap[userId]!.score -= 2;
      }
    }

    final now = DateTime.now();

    for (final athlete in athleteMap.values) {
      athlete.latestEvaluationTypes =
          athlete.latestEvaluationTypes.take(3).toList();

      if (athlete.latestEvaluationTypes.length >= 3 &&
          athlete.latestEvaluationTypes.every(
            (tipo) => tipo == 'atencao' || tipo == 'atenção',
          )) {
        athlete.riskReasons.add('3 pontos de atenção seguidos');
      }

      if (athlete.lastEvaluation == null) {
        athlete.riskReasons.add('Sem avaliação registrada');
      } else if (now.difference(athlete.lastEvaluation!).inDays >= 30) {
        athlete.riskReasons.add('Sem avaliação há 30 dias');
      }

      final attendanceTotal = athlete.presencas + athlete.faltas;
      if (attendanceTotal >= 3) {
        final rate = athlete.presencas / attendanceTotal;
        if (rate < 0.6) {
          athlete.riskReasons.add('Presença baixa');
        }
      }

      if (athlete.atencoes >= 3 && athlete.atencoes > athlete.destaques) {
        athlete.riskReasons.add('Muitos pontos de atenção');
      }
    }

    final athletes = athleteMap.values.toList();

    final topAthletes = athletes.where((e) {
      return e.destaques > 0 || e.score > 0 || e.presencas > 0;
    }).toList()
      ..sort((a, b) {
        final scoreCompare = b.score.compareTo(a.score);
        if (scoreCompare != 0) return scoreCompare;

        final destaqueCompare = b.destaques.compareTo(a.destaques);
        if (destaqueCompare != 0) return destaqueCompare;

        return a.name.compareTo(b.name);
      });

    final riskAthletes =
        athletes.where((e) => e.riskReasons.isNotEmpty).toList()
          ..sort((a, b) {
            final riskCompare =
                b.riskReasons.length.compareTo(a.riskReasons.length);
            if (riskCompare != 0) return riskCompare;

            final scoreCompare = a.score.compareTo(b.score);
            if (scoreCompare != 0) return scoreCompare;

            return a.name.compareTo(b.name);
          });

    final criticalFundamentEntry = attentionByFundament.entries.isEmpty
        ? null
        : (attentionByFundament.entries.toList()
              ..sort((a, b) => b.value.compareTo(a.value)))
            .first;

    final bestFundamentEntry = attentionByFundament.entries.isEmpty
        ? null
        : (attentionByFundament.entries.toList()
              ..sort((a, b) => a.value.compareTo(b.value)))
            .first;

    final presenceAverage = totalExpectedPresence == 0
        ? 0.0
        : totalPresence / totalExpectedPresence;

    final engagementScore = _calculateEngagementScore(
      presenceAverage: presenceAverage,
      totalDestaques: totalDestaques,
      totalAtencoes: totalAtencoes,
      totalAvaliacoes: totalAvaliacoes,
      athleteCount: athletes.length,
    );

    final evolutionDelta =
        periodoAnteriorInicio == null ? 0 : currentScore - previousScore;

    final evolutionLabel = periodoAnteriorInicio == null
        ? 'Sem comparação'
        : evolutionDelta > 0
            ? 'Melhorando'
            : evolutionDelta < 0
                ? 'Em queda'
                : 'Estável';

    final trendPoints = _buildTrendPoints(scoreByDay, periodoInicio);

    final insights = <_SmartInsight>[];
    final actions = <String>[];

    if (presenceAverage < 0.6 && totalExpectedPresence >= 3) {
      insights.add(
        _SmartInsight(
          icon: Icons.warning_amber_rounded,
          title: 'Presença abaixo do ideal',
          message:
              'A presença média está em ${(presenceAverage * 100).round()}%.',
          severity: _InsightSeverity.risk,
        ),
      );
      actions.add(
          'Conversar com atletas de baixa presença antes do próximo treino.');
    } else if (totalExpectedPresence > 0) {
      insights.add(
        _SmartInsight(
          icon: Icons.check_circle_outline,
          title: 'Presença sob controle',
          message:
              'A presença média está em ${(presenceAverage * 100).round()}%.',
          severity: _InsightSeverity.good,
        ),
      );
    }

    if (criticalFundamentEntry != null) {
      insights.add(
        _SmartInsight(
          icon: Icons.sports_volleyball,
          title: '${criticalFundamentEntry.key} exige atenção',
          message:
              '${criticalFundamentEntry.value} ponto(s) de atenção foram registrados nesse fundamento.',
          severity: _InsightSeverity.warning,
        ),
      );
      actions.add(
          'Priorizar ${criticalFundamentEntry.key.toLowerCase()} no próximo treino.');
    }

    if (riskAthletes.isNotEmpty) {
      insights.add(
        _SmartInsight(
          icon: Icons.health_and_safety_outlined,
          title: '${riskAthletes.length} atleta(s) em risco',
          message:
              'Há atletas com baixa presença, atenção recorrente ou sem avaliação recente.',
          severity: _InsightSeverity.risk,
        ),
      );
      actions.add('Revisar individualmente atletas classificados como risco.');
    }

    if (topAthletes.isNotEmpty) {
      insights.add(
        _SmartInsight(
          icon: Icons.emoji_events_outlined,
          title: '${topAthletes.first.name} lidera o período',
          message: 'Maior combinação de score, destaques e presença no painel.',
          severity: _InsightSeverity.good,
        ),
      );
    }

    if (_periodo != 'geral') {
      insights.add(
        _SmartInsight(
          icon: evolutionDelta >= 0
              ? Icons.trending_up_rounded
              : Icons.trending_down_rounded,
          title: 'Evolução do time: $evolutionLabel',
          message: evolutionDelta == 0
              ? 'Pontuação similar ao período anterior.'
              : 'Variação de ${evolutionDelta > 0 ? '+' : ''}$evolutionDelta ponto(s) contra o período anterior.',
          severity: evolutionDelta >= 0
              ? _InsightSeverity.good
              : _InsightSeverity.warning,
        ),
      );

      if (evolutionDelta < 0) {
        actions
            .add('Reduzir volume e focar fundamentos críticos nesta semana.');
      }
    }

    if (athletes.where((e) => e.lastEvaluation == null).isNotEmpty) {
      actions.add(
          'Avaliar atletas sem histórico para melhorar a leitura do painel.');
    }

    if (actions.isEmpty) {
      actions.add('Manter rotina de avaliações rápidas após cada treino.');
      actions.add(
          'Usar o fundamento crítico para orientar o próximo planejamento.');
    }

    return _TeamDashboardData(
      periodLabel: _getPeriodoLabel(),
      athleteCount: athletes.length,
      totalEvaluations: totalAvaliacoes,
      totalDestaques: totalDestaques,
      totalAtencoes: totalAtencoes,
      presenceAverage: presenceAverage,
      engagementScore: engagementScore,
      currentScore: currentScore,
      previousScore: previousScore,
      evolutionDelta: evolutionDelta,
      evolutionLabel: evolutionLabel,
      criticalFundament: criticalFundamentEntry?.key ?? 'Sem dados',
      criticalFundamentCount: criticalFundamentEntry?.value ?? 0,
      bestFundament: bestFundamentEntry?.key ?? 'Sem dados',
      topAthletes: topAthletes.take(5).toList(),
      riskAthletes: riskAthletes.take(6).toList(),
      insights: insights,
      actions: actions.take(5).toList(),
      attentionByFundament: attentionByFundament,
      trendPoints: trendPoints,
      explanation: null,
    );
  }

  double _calculateEngagementScore({
    required double presenceAverage,
    required int totalDestaques,
    required int totalAtencoes,
    required int totalAvaliacoes,
    required int athleteCount,
  }) {
    if (athleteCount == 0) return 0;

    final presencePart = presenceAverage * 55;
    final evaluationCoverage =
        math.min(1.0, totalAvaliacoes / math.max(1, athleteCount)) * 25;

    final positiveBalance = totalDestaques + totalAtencoes == 0
        ? 0.5
        : totalDestaques / (totalDestaques + totalAtencoes);

    final performancePart = positiveBalance * 20;

    return (presencePart + evaluationCoverage + performancePart).clamp(0, 100);
  }

  List<_TrendPoint> _buildTrendPoints(
    Map<DateTime, int> scoreByDay,
    DateTime? periodoInicio,
  ) {
    final entries = scoreByDay.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    if (entries.isEmpty) return [];

    int cumulative = 0;
    return entries.map((entry) {
      cumulative += entry.value;
      return _TrendPoint(date: entry.key, value: cumulative);
    }).toList();
  }

  DateTime? _latestDate(DateTime? a, DateTime? b) {
    if (a == null) return b;
    if (b == null) return a;
    return a.isAfter(b) ? a : b;
  }

  void _showDashboardHelp() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 22),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: SafeArea(
            top: false,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 46,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'Como interpretar este painel',
                    style: TextStyle(
                      color: olympusBlue,
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 14),
                  _helpItem(
                    icon: Icons.groups_rounded,
                    title: 'Presença média',
                    text:
                        'Mostra o percentual de check-ins realizados em relação às convocações aceitas nos treinos do período.',
                  ),
                  _helpItem(
                    icon: Icons.bolt_rounded,
                    title: 'Engajamento',
                    text:
                        'Combina presença, quantidade de avaliações e equilíbrio entre destaques e pontos de atenção.',
                  ),
                  _helpItem(
                    icon: Icons.trending_up_rounded,
                    title: 'Evolução do time',
                    text:
                        'Compara a pontuação do período atual com o período anterior. Destaque soma, atenção reduz.',
                  ),
                  _helpItem(
                    icon: Icons.emoji_events_outlined,
                    title: 'Atletas em destaque',
                    text:
                        'Lista atletas com melhor combinação de score, presença e avaliações positivas.',
                  ),
                  _helpItem(
                    icon: Icons.warning_amber_rounded,
                    title: 'Atletas em risco',
                    text:
                        'Identifica atletas com baixa presença, pontos de atenção recorrentes ou sem avaliação recente.',
                  ),
                  _helpItem(
                    icon: Icons.sports_volleyball,
                    title: 'Fundamento crítico',
                    text:
                        'Mostra o fundamento com mais pontos de atenção registrados no período.',
                  ),
                  _helpItem(
                    icon: Icons.lightbulb_outline,
                    title: 'Ações recomendadas',
                    text:
                        'Sugestões práticas geradas a partir dos dados para orientar o próximo treino.',
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _showInfo(String title, String text) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(text),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Entendi'),
          ),
        ],
      ),
    );
  }

  Widget _helpItem({
    required IconData icon,
    required String title,
    required String text,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: olympusGold, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: olympusBlue,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  text,
                  style: const TextStyle(
                    color: Color(0xFF53657B),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPremiumBackground() {
    return Stack(
      children: [
        Positioned.fill(
          child: Image.asset(
            'assets/images/monte_olimpo_v2.png',
            fit: BoxFit.cover,
          ),
        ),
        Positioned.fill(
          child: Container(
            color: Colors.black.withValues(alpha: 0.35),
          ),
        ),
      ],
    );
  }

  Widget _buildHeader() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          colors: [
            Color(0xFF0D223B),
            Color(0xFF123861),
            Color(0xFF235E94),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: Colors.white.withOpacity(0.18)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.22),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.insights_rounded, color: olympusGold, size: 30),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Smart Dashboard',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              IconButton(
                onPressed: _showDashboardHelp,
                icon: const Icon(Icons.help_outline_rounded),
                color: Colors.white,
                tooltip: 'Entenda o painel',
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Insights automáticos da equipe • ${_data.periodLabel}',
            style: TextStyle(
              color: Colors.white.withOpacity(0.86),
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _periodChip('semana', 'Semana'),
              _periodChip('mes', 'Mês'),
              _periodChip('geral', 'Geral'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _periodChip(String value, String label) {
    final selected = _periodo == value;

    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) {
        if (selected) return;
        setState(() => _periodo = value);
        _loadDashboard();
      },
      selectedColor: olympusGold,
      backgroundColor: olympusBlue.withValues(alpha: 0.30),
      disabledColor: olympusBlue.withValues(alpha: 0.18),
      side: BorderSide(
        color: selected ? olympusGold : Colors.white.withValues(alpha: 0.28),
        width: selected ? 1.4 : 1,
      ),
      labelStyle: TextStyle(
        color: selected ? olympusBlue : Colors.white,
        fontWeight: FontWeight.w900,
      ),
      showCheckmark: false,
      elevation: selected ? 2 : 0,
      pressElevation: 0,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
    );
  }

  Widget _metricCard({
    required IconData icon,
    required String title,
    required String value,
    required String subtitle,
    required Color color,
    required String explanation,
  }) {
    return Expanded(
      child: Container(
        constraints: const BoxConstraints(minHeight: 142),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.95),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withOpacity(0.70)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.14),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.13),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(icon, color: color, size: 20),
                ),
                const Spacer(),
                InkWell(
                  onTap: () => _showInfo(title, explanation),
                  borderRadius: BorderRadius.circular(99),
                  child: Padding(
                    padding: const EdgeInsets.all(3),
                    child: Icon(
                      Icons.info_outline_rounded,
                      color: Colors.grey.shade500,
                      size: 18,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              value,
              style: const TextStyle(
                color: olympusBlue,
                fontSize: 24,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              title,
              style: const TextStyle(
                color: olympusBlue,
                fontSize: 13,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF6A7E94),
                fontSize: 11,
                fontWeight: FontWeight.w600,
                height: 1.25,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricsGrid() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isSmall = constraints.maxWidth < 360;

          if (isSmall) {
            return Column(
              children: [
                _metricCard(
                  icon: Icons.groups_rounded,
                  title: 'Atletas ativos',
                  value: '${_data.athleteCount}',
                  subtitle: 'Habilitados em ranking/avaliações',
                  color: const Color(0xFF2563EB),
                  explanation: 'Total de atletas visíveis para o técnico.',
                ),
                const SizedBox(height: 10),
                _metricCard(
                  icon: Icons.fact_check_outlined,
                  title: 'Presença média',
                  value: '${(_data.presenceAverage * 100).round()}%',
                  subtitle: 'Check-ins / convocações',
                  color: const Color(0xFF16A34A),
                  explanation: 'Percentual de presenças confirmadas.',
                ),
                const SizedBox(height: 10),
                _metricCard(
                  icon: Icons.bolt_rounded,
                  title: 'Engajamento',
                  value: '${_data.engagementScore.round()}%',
                  subtitle: 'Participação geral',
                  color: const Color(0xFFF59E0B),
                  explanation: 'Score de envolvimento dos atletas.',
                ),
                const SizedBox(height: 10),
                _metricCard(
                  icon: _data.evolutionDelta >= 0
                      ? Icons.trending_up_rounded
                      : Icons.trending_down_rounded,
                  title: 'Evolução',
                  value: _data.evolutionDelta == 0
                      ? '0'
                      : '${_data.evolutionDelta > 0 ? '+' : ''}${_data.evolutionDelta}',
                  subtitle: _data.evolutionLabel,
                  color: _data.evolutionDelta >= 0
                      ? const Color(0xFF0EA5A4)
                      : const Color(0xFFDC2626),
                  explanation: 'Comparação com período anterior.',
                ),
              ],
            );
          }

          return Column(
            children: [
              Row(
                children: [
                  Expanded(
                      child: _metricCard(
                    icon: Icons.groups_rounded,
                    title: 'Atletas ativos',
                    value: '${_data.athleteCount}',
                    subtitle: 'Habilitados',
                    color: const Color(0xFF2563EB),
                    explanation: 'Total de atletas visíveis.',
                  )),
                  const SizedBox(width: 10),
                  Expanded(
                      child: _metricCard(
                    icon: Icons.fact_check_outlined,
                    title: 'Presença média',
                    value: '${(_data.presenceAverage * 100).round()}%',
                    subtitle: 'Check-ins',
                    color: const Color(0xFF16A34A),
                    explanation: 'Percentual de presença.',
                  )),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                      child: _metricCard(
                    icon: Icons.bolt_rounded,
                    title: 'Engajamento',
                    value: '${_data.engagementScore.round()}%',
                    subtitle: 'Participação',
                    color: const Color(0xFFF59E0B),
                    explanation: 'Score geral.',
                  )),
                  const SizedBox(width: 10),
                  Expanded(
                      child: _metricCard(
                    icon: _data.evolutionDelta >= 0
                        ? Icons.trending_up_rounded
                        : Icons.trending_down_rounded,
                    title: 'Evolução',
                    value: _data.evolutionDelta == 0
                        ? '0'
                        : '${_data.evolutionDelta > 0 ? '+' : ''}${_data.evolutionDelta}',
                    subtitle: _data.evolutionLabel,
                    color: _data.evolutionDelta >= 0
                        ? const Color(0xFF0EA5A4)
                        : const Color(0xFFDC2626),
                    explanation: 'Comparação com período anterior.',
                  )),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _sectionCard({
    required String title,
    required IconData icon,
    required List<Widget> children,
    Widget? trailing,
  }) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.94),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE4EDF5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.12),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: olympusGold),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: olympusBlue,
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              if (trailing != null) trailing,
            ],
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  Widget _buildInsightsSection() {
    final insights = _data.insights;

    if (insights.isEmpty) {
      return _sectionCard(
        title: 'Insights inteligentes',
        icon: Icons.lightbulb_outline,
        children: const [
          Text(
            'Ainda não há dados suficientes para gerar insights.',
            style: TextStyle(
              color: Color(0xFF53657B),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      );
    }

    return _sectionCard(
      title: 'Insights inteligentes',
      icon: Icons.lightbulb_outline,
      children: insights.map(_insightTile).toList(),
    );
  }

  Widget _insightTile(_SmartInsight insight) {
    Color color;
    switch (insight.severity) {
      case _InsightSeverity.good:
        color = const Color(0xFF16A34A);
        break;
      case _InsightSeverity.warning:
        color = const Color(0xFFF59E0B);
        break;
      case _InsightSeverity.risk:
        color = const Color(0xFFDC2626);
        break;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 9),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.18)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(insight.icon, color: color, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  insight.title,
                  style: TextStyle(
                    color: color,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  insight.message,
                  style: const TextStyle(
                    color: Color(0xFF53657B),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTrendSection() {
    return _sectionCard(
      title: 'Tendência da equipe',
      icon: Icons.show_chart_rounded,
      children: [
        SizedBox(
          height: 160,
          child: _data.trendPoints.isEmpty
              ? const Center(
                  child: Text(
                    'Sem dados de evolução no período.',
                    style: TextStyle(
                      color: Color(0xFF53657B),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                )
              : CustomPaint(
                  painter: _TrendChartPainter(
                    points: _data.trendPoints,
                    lineColor: olympusBlue,
                    fillColor: olympusGold.withOpacity(0.12),
                  ),
                  child: const SizedBox.expand(),
                ),
        ),
        const SizedBox(height: 8),
        Text(
          'Pontuação acumulada por dia no período selecionado.',
          style: TextStyle(
            color: Colors.grey.shade600,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildFundamentsSection() {
    final entries = _data.attentionByFundament.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return _sectionCard(
      title: 'Fundamentos críticos',
      icon: Icons.sports_volleyball,
      trailing: InkWell(
        onTap: () => _showInfo(
          'Fundamentos críticos',
          'Mostra os fundamentos mais marcados como ponto de atenção nas avaliações do período.',
        ),
        child: Icon(Icons.info_outline, color: Colors.grey.shade500),
      ),
      children: [
        if (entries.isEmpty)
          const Text(
            'Sem pontos de atenção por fundamento neste período.',
            style: TextStyle(
              color: Color(0xFF53657B),
              fontWeight: FontWeight.w600,
            ),
          )
        else
          ...entries.take(6).map((entry) {
            final maxValue = entries.first.value;
            final percent = maxValue == 0 ? 0.0 : entry.value / maxValue;

            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          entry.key,
                          style: const TextStyle(
                            color: olympusBlue,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      Text(
                        '${entry.value}',
                        style: const TextStyle(
                          color: Color(0xFFDC2626),
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(99),
                    child: LinearProgressIndicator(
                      value: percent,
                      minHeight: 8,
                      backgroundColor: const Color(0xFFE4EDF5),
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        Color(0xFFDC2626),
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
      ],
    );
  }

  Widget _buildAthletesSection({
    required String title,
    required IconData icon,
    required List<_AthleteSmartMetric> athletes,
    required bool risk,
  }) {
    return _sectionCard(
      title: title,
      icon: icon,
      children: [
        if (athletes.isEmpty)
          Text(
            risk
                ? 'Nenhum atleta em risco neste período.'
                : 'Nenhum destaque identificado neste período.',
            style: const TextStyle(
              color: Color(0xFF53657B),
              fontWeight: FontWeight.w600,
            ),
          )
        else
          ...athletes.take(5).map((athlete) {
            return Container(
              margin: const EdgeInsets.only(bottom: 9),
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                color: risk
                    ? Colors.red.withOpacity(0.06)
                    : olympusGold.withOpacity(0.08),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: risk
                      ? Colors.red.withOpacity(0.14)
                      : olympusGold.withOpacity(0.18),
                ),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 21,
                    backgroundColor: risk ? Colors.red : olympusBlue,
                    backgroundImage: athlete.avatarUrl.trim().isNotEmpty
                        ? NetworkImage(athlete.avatarUrl)
                        : null,
                    child: athlete.avatarUrl.trim().isEmpty
                        ? Text(
                            athlete.name.isNotEmpty
                                ? athlete.name[0].toUpperCase()
                                : '?',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                            ),
                          )
                        : null,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          athlete.name,
                          style: const TextStyle(
                            color: olympusBlue,
                            fontSize: 13,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          risk
                              ? athlete.riskReasons.take(2).join(' • ')
                              : 'Score ${athlete.score} • Destaques ${athlete.destaques} • Presenças ${athlete.presencas}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFF53657B),
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: risk
                          ? Colors.red.withOpacity(0.10)
                          : olympusBlue.withOpacity(0.10),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      risk
                          ? '${athlete.riskReasons.length}'
                          : '${athlete.score}',
                      style: TextStyle(
                        color: risk ? Colors.red : olympusBlue,
                        fontWeight: FontWeight.w900,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
      ],
    );
  }

  Widget _buildActionsSection() {
    return _sectionCard(
      title: 'Ações recomendadas',
      icon: Icons.task_alt_rounded,
      children: _data.actions.map((action) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 9),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.arrow_circle_right_rounded,
                  color: olympusGold, size: 21),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  action,
                  style: const TextStyle(
                    color: Color(0xFF53657B),
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    height: 1.3,
                  ),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Container(
        margin: const EdgeInsets.all(20),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.95),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          _data.explanation ??
              'Ainda não há dados suficientes para montar o Smart Dashboard.',
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: olympusBlue,
            fontWeight: FontWeight.w800,
            height: 1.3,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasData = _data.athleteCount > 0;

    return Scaffold(
      backgroundColor: const Color(0xFF102845),
      appBar: AppBar(
        title: const Text('Smart Dashboard'),
        backgroundColor: olympusBlue,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            onPressed: _showDashboardHelp,
            icon: const Icon(Icons.help_outline_rounded),
          ),
          IconButton(
            onPressed: _loadDashboard,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Stack(
        children: [
          Positioned.fill(child: _buildPremiumBackground()),
          if (_loading)
            const Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            )
          else if (_error != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
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
          else if (!hasData)
            _buildEmptyState()
          else
            RefreshIndicator(
              onRefresh: _loadDashboard,
              child: ListView(
                padding: const EdgeInsets.only(bottom: 28),
                children: [
                  _buildHeader(),
                  _buildMetricsGrid(),
                  _buildInsightsSection(),
                  _buildTrendSection(),
                  _buildAthletesSection(
                    title: 'Atletas em destaque',
                    icon: Icons.emoji_events_outlined,
                    athletes: _data.topAthletes,
                    risk: false,
                  ),
                  _buildAthletesSection(
                    title: 'Atletas em risco',
                    icon: Icons.warning_amber_rounded,
                    athletes: _data.riskAthletes,
                    risk: true,
                  ),
                  _buildFundamentsSection(),
                  _buildActionsSection(),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _TeamDashboardData {
  _TeamDashboardData({
    required this.periodLabel,
    required this.athleteCount,
    required this.totalEvaluations,
    required this.totalDestaques,
    required this.totalAtencoes,
    required this.presenceAverage,
    required this.engagementScore,
    required this.currentScore,
    required this.previousScore,
    required this.evolutionDelta,
    required this.evolutionLabel,
    required this.criticalFundament,
    required this.criticalFundamentCount,
    required this.bestFundament,
    required this.topAthletes,
    required this.riskAthletes,
    required this.insights,
    required this.actions,
    required this.attentionByFundament,
    required this.trendPoints,
    required this.explanation,
  });

  final String periodLabel;
  final int athleteCount;
  final int totalEvaluations;
  final int totalDestaques;
  final int totalAtencoes;
  final double presenceAverage;
  final double engagementScore;
  final int currentScore;
  final int previousScore;
  final int evolutionDelta;
  final String evolutionLabel;
  final String criticalFundament;
  final int criticalFundamentCount;
  final String bestFundament;
  final List<_AthleteSmartMetric> topAthletes;
  final List<_AthleteSmartMetric> riskAthletes;
  final List<_SmartInsight> insights;
  final List<String> actions;
  final Map<String, int> attentionByFundament;
  final List<_TrendPoint> trendPoints;
  final String? explanation;

  factory _TeamDashboardData.empty({
    String periodLabel = 'Mês atual',
    String? explanation,
  }) {
    return _TeamDashboardData(
      periodLabel: periodLabel,
      athleteCount: 0,
      totalEvaluations: 0,
      totalDestaques: 0,
      totalAtencoes: 0,
      presenceAverage: 0,
      engagementScore: 0,
      currentScore: 0,
      previousScore: 0,
      evolutionDelta: 0,
      evolutionLabel: 'Sem dados',
      criticalFundament: 'Sem dados',
      criticalFundamentCount: 0,
      bestFundament: 'Sem dados',
      topAthletes: [],
      riskAthletes: [],
      insights: [],
      actions: const [],
      attentionByFundament: {},
      trendPoints: [],
      explanation: explanation,
    );
  }
}

class _AthleteSmartMetric {
  _AthleteSmartMetric({
    required this.athleteId,
    required this.name,
    required this.avatarUrl,
  });

  final String athleteId;
  final String name;
  final String avatarUrl;

  int score = 0;
  int destaques = 0;
  int atencoes = 0;
  int evaluations = 0;
  int presencas = 0;
  int faltas = 0;
  DateTime? lastEvaluation;

  Map<String, int> attentionFundaments = {};
  List<String> riskReasons = [];
  List<String> latestEvaluationTypes = [];
}

class _SmartInsight {
  _SmartInsight({
    required this.icon,
    required this.title,
    required this.message,
    required this.severity,
  });

  final IconData icon;
  final String title;
  final String message;
  final _InsightSeverity severity;
}

enum _InsightSeverity {
  good,
  warning,
  risk,
}

class _TrendPoint {
  _TrendPoint({
    required this.date,
    required this.value,
  });

  final DateTime date;
  final int value;
}

class _TrendChartPainter extends CustomPainter {
  _TrendChartPainter({
    required this.points,
    required this.lineColor,
    required this.fillColor,
  });

  final List<_TrendPoint> points;
  final Color lineColor;
  final Color fillColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty || size.width <= 0 || size.height <= 0) return;

    final padding = const EdgeInsets.fromLTRB(28, 12, 12, 26);
    final chartWidth = size.width - padding.left - padding.right;
    final chartHeight = size.height - padding.top - padding.bottom;

    final values = points.map((e) => e.value).toList();
    final minValue = values.reduce(math.min);
    final maxValue = values.reduce(math.max);
    final range = math.max(1, maxValue - minValue);

    final axisPaint = Paint()
      ..color = const Color(0xFFE4EDF5)
      ..strokeWidth = 1;

    final gridPaint = Paint()
      ..color = const Color(0xFFE4EDF5).withOpacity(0.70)
      ..strokeWidth = 1;

    for (int i = 0; i <= 3; i++) {
      final y = padding.top + chartHeight * (i / 3);
      canvas.drawLine(
        Offset(padding.left, y),
        Offset(padding.left + chartWidth, y),
        gridPaint,
      );
    }

    canvas.drawLine(
      Offset(padding.left, padding.top),
      Offset(padding.left, padding.top + chartHeight),
      axisPaint,
    );
    canvas.drawLine(
      Offset(padding.left, padding.top + chartHeight),
      Offset(padding.left + chartWidth, padding.top + chartHeight),
      axisPaint,
    );

    final chartPoints = <Offset>[];

    for (int i = 0; i < points.length; i++) {
      final x = points.length == 1
          ? padding.left + chartWidth / 2
          : padding.left + chartWidth * (i / (points.length - 1));

      final normalized = (points[i].value - minValue) / range;
      final y = padding.top + chartHeight - (normalized * chartHeight);

      chartPoints.add(Offset(x, y));
    }

    if (chartPoints.length == 1) {
      final dotPaint = Paint()..color = lineColor;
      canvas.drawCircle(chartPoints.first, 4, dotPaint);
      return;
    }

    final linePath = Path()..moveTo(chartPoints.first.dx, chartPoints.first.dy);
    for (final point in chartPoints.skip(1)) {
      linePath.lineTo(point.dx, point.dy);
    }

    final fillPath = Path.from(linePath)
      ..lineTo(chartPoints.last.dx, padding.top + chartHeight)
      ..lineTo(chartPoints.first.dx, padding.top + chartHeight)
      ..close();

    canvas.drawPath(fillPath, Paint()..color = fillColor);

    final linePaint = Paint()
      ..color = lineColor
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    canvas.drawPath(linePath, linePaint);

    final dotPaint = Paint()..color = lineColor;
    final dotBorderPaint = Paint()..color = Colors.white;

    for (final point in chartPoints) {
      canvas.drawCircle(point, 5, dotBorderPaint);
      canvas.drawCircle(point, 3.5, dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _TrendChartPainter oldDelegate) {
    return oldDelegate.points != points ||
        oldDelegate.lineColor != lineColor ||
        oldDelegate.fillColor != fillColor;
  }
}
