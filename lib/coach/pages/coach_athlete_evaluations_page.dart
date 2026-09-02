import 'package:flutter/material.dart';
import '../../theme/olympus_theme.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/permission_service.dart';
import 'coach_athlete_evaluation_models.dart';
import 'coach_athlete_evaluations_history_page.dart';
import 'coach_complete_monthly_evaluation_page.dart';

export 'coach_athlete_evaluation_models.dart';
export 'coach_athlete_evaluations_history_page.dart';

Future<void> sendEvaluationMessageToAthlete({
  required SupabaseClient supabase,
  required String athleteId,
  required String title,
  required String body,
}) async {
  Object? lastError;

  final attempts = <Map<String, dynamic>>[
    {
      'table': 'app_messages',
      'data': {
        'recipient_id': athleteId,
        'title': title,
        'body': body,
        'message_type': 'evaluation',
        'created_at': DateTime.now().toIso8601String(),
      },
    },
    {
      'table': 'app_messages',
      'data': {
        'user_id': athleteId,
        'title': title,
        'message': body,
        'type': 'evaluation',
        'created_at': DateTime.now().toIso8601String(),
      },
    },
    {
      'table': 'user_messages',
      'data': {
        'user_id': athleteId,
        'title': title,
        'body': body,
        'created_at': DateTime.now().toIso8601String(),
      },
    },
    {
      'table': 'user_messages',
      'data': {
        'recipient_id': athleteId,
        'subject': title,
        'content': body,
        'created_at': DateTime.now().toIso8601String(),
      },
    },
  ];

  for (final attempt in attempts) {
    try {
      await supabase
          .from(attempt['table'] as String)
          .insert(Map<String, dynamic>.from(attempt['data'] as Map));
      return;
    } catch (e) {
      lastError = e;
    }
  }

  throw Exception(
    'Avaliação salva, mas não foi possível enviar para a atleta: $lastError',
  );
}

class CoachAthleteEvaluationTeamSelectPage extends StatefulWidget {
  const CoachAthleteEvaluationTeamSelectPage({super.key});

  @override
  State<CoachAthleteEvaluationTeamSelectPage> createState() =>
      _CoachAthleteEvaluationTeamSelectPageState();
}

class _CoachAthleteEvaluationTeamSelectPageState
    extends State<CoachAthleteEvaluationTeamSelectPage> {
  static const Color olympusPurple = Color(0xFF7C3AED);
  static const Color olympusBg = Color(0xFFF4F7FB);

  final PermissionService _permissionService = PermissionService();
  bool _loadingScope = true;
  String _coachTeamGender = 'all';

  @override
  void initState() {
    super.initState();
    _loadCoachScope();
  }

  Future<void> _loadCoachScope() async {
    try {
      final scope = await _permissionService.getCoachTeamGender();
      if (!mounted) return;
      setState(() {
        _coachTeamGender = scope;
        _loadingScope = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _coachTeamGender = 'all';
        _loadingScope = false;
      });
    }
  }

  bool _canOpenGender(String gender) {
    final normalized = _coachTeamGender.trim().toLowerCase();
    if (normalized == 'all' || normalized == 'ambos' || normalized.isEmpty) {
      return true;
    }
    return normalized == gender.trim().toLowerCase();
  }

  String get _scopeLabel {
    switch (_coachTeamGender.trim().toLowerCase()) {
      case 'feminino':
        return 'Time Feminino';
      case 'masculino':
        return 'Time Masculino';
      default:
        return 'Times Feminino e Masculino';
    }
  }

  void _openTeam(BuildContext context, String gender) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CoachAthleteEvaluationsPage(
          initialGenderFilter: gender,
        ),
      ),
    );
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
          child: Container(color: Colors.black.withOpacity(0.34)),
        ),
        Positioned.fill(
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  olympusBlue.withOpacity(0.88),
                  olympusLightBlue.withOpacity(0.44),
                  Colors.black.withOpacity(0.76),
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

  Widget _heroCard() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 18, 16, 18),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: LinearGradient(
          colors: [
            Color.lerp(olympusBlue, Colors.black, 0.36)!,
            Color.lerp(olympusBlue, Colors.black, 0.08)!,
            Color.lerp(olympusBlue, Colors.white, 0.18)!,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: olympusGold, width: 1.1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.30),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Avaliação de Atletas',
            style: TextStyle(
              color: Colors.white,
              fontSize: 23,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Escopo liberado para este treinador: $_scopeLabel.',
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 13,
              fontWeight: FontWeight.w700,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }

  Widget _teamButton({
    required BuildContext context,
    required String title,
    required String gender,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 14),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _openTeam(context, gender),
          borderRadius: BorderRadius.circular(24),
          child: Ink(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.96),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: color.withOpacity(0.35)),
              boxShadow: [
                BoxShadow(
                  color: color.withOpacity(0.20),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: color.withOpacity(0.15),
                  ),
                  child: Icon(icon, color: color, size: 32),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      color: olympusBlue,
                      fontSize: 19,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                Icon(
                  Icons.arrow_forward_ios_rounded,
                  color: color,
                  size: 18,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: olympusBg,
      appBar: AppBar(
        title: const Text('Avaliação de Atletas'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Theme.of(context).colorScheme.onPrimary,
      ),
      body: Stack(
        children: [
          Positioned.fill(child: _background()),
          if (_loadingScope)
            const Center(
              child: CircularProgressIndicator(color: Colors.white),
            )
          else
            ListView(
              padding: const EdgeInsets.only(bottom: 28),
              children: [
                _heroCard(),
                if (_canOpenGender('Feminino'))
                  _teamButton(
                    context: context,
                    title: 'Time Feminino',
                    gender: 'Feminino',
                    icon: Icons.female_rounded,
                    color: olympusPurple,
                  ),
                if (_canOpenGender('Masculino'))
                  _teamButton(
                    context: context,
                    title: 'Time Masculino',
                    gender: 'Masculino',
                    icon: Icons.male_rounded,
                    color: olympusBlue,
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class CoachAthleteEvaluationsPage extends StatefulWidget {
  const CoachAthleteEvaluationsPage({super.key, this.initialGenderFilter});

  final String? initialGenderFilter;

  @override
  State<CoachAthleteEvaluationsPage> createState() =>
      _CoachAthleteEvaluationsPageState();
}

class _CoachAthleteEvaluationsPageState
    extends State<CoachAthleteEvaluationsPage> {
  String _completeEvaluationFilter = 'Todas';

  final SupabaseClient _supabase = Supabase.instance.client;
  final PermissionService _permissionService = PermissionService();

  static const Color olympusPurple = Color(0xFF7C3AED);
  static const Color olympusSuccess = Color(0xFF16A34A);
  static const Color olympusWarning = Color(0xFFF59E0B);
  static const Color olympusDanger = Color(0xFFDC2626);
  static const Color olympusBorder = Color(0xFFE4EDF5);
  static const Color olympusMuted = Color(0xFF53657B);

  bool _loading = true;
  String? _error;
  String _genderFilter = 'Todos';
  DateTime _selectedMonth = DateTime(DateTime.now().year, DateTime.now().month);
  List<DateTime> _trainingMonths = [];
  final Map<String, DateTime> _trainingEventMonths = {};

  List<AthleteEvaluationStatus> _athletes = [];

  @override
  void initState() {
    super.initState();
    if (widget.initialGenderFilter != null &&
        widget.initialGenderFilter!.trim().isNotEmpty) {
      final initialGender = widget.initialGenderFilter!;
      if (initialGender == 'Feminino' || initialGender == 'Masculino') {
        _genderFilter = initialGender;
      }
    }

    if (widget.initialGenderFilter != null &&
        widget.initialGenderFilter!.trim().isNotEmpty) {}

    _carregarAtletasVisiveis();
  }

  DateTime get _monthStart =>
      DateTime(_selectedMonth.year, _selectedMonth.month, 1);

  DateTime get _monthEnd =>
      DateTime(_selectedMonth.year, _selectedMonth.month + 1, 1);

  bool get _isCurrentMonth {
    final now = DateTime.now();
    return _selectedMonth.year == now.year && _selectedMonth.month == now.month;
  }

  bool get _isLastFourDaysOfMonth {
    final now = DateTime.now();
    final lastDay = DateTime(now.year, now.month + 1, 0).day;
    return now.day >= lastDay - 3;
  }

  bool get _canCompleteMonthly => _isCurrentMonth && _isLastFourDaysOfMonth;

  int get _pendingMonthlyCount =>
      _athletes.where((a) => !a.hasMonthlyComplete).length;

  List<AthleteEvaluationStatus> get _filteredAthletes {
    Iterable<AthleteEvaluationStatus> base = _athletes;

    if (_genderFilter != 'Todos') {
      final filter = _genderFilter.toLowerCase();
      base = base.where((athlete) {
        final gender = athlete.gender.toLowerCase().trim();

        if (filter == 'feminino') {
          return gender == 'feminino' || gender == 'female' || gender == 'f';
        }

        if (filter == 'masculino') {
          return gender == 'masculino' || gender == 'male' || gender == 'm';
        }

        return true;
      });
    }

    final filtered = base.where(_matchesCompleteEvaluationFilter).toList()
      ..sort(
        (a, b) => a.athleteName
            .toLowerCase()
            .trim()
            .compareTo(b.athleteName.toLowerCase().trim()),
      );

    return filtered;
  }

  DateTime? _parseEventDate(dynamic value) {
    final raw = (value ?? '').toString().trim();
    if (raw.isEmpty) return null;
    final parts = raw.split('/');
    if (parts.length == 3) {
      return DateTime.tryParse('${parts[2]}-${parts[1]}-${parts[0]}');
    }
    return DateTime.tryParse(raw);
  }

  Future<void> _loadTrainingMonths() async {
    final user = _supabase.auth.currentUser;
    if (user == null) throw Exception('Usuário não autenticado.');

    final response = await _supabase.from('convocations').select('''
events!convocations_event_id_fkey (
  id,
  event_type,
  event_date
)
''').eq('user_id', user.id);

    final months = <String, DateTime>{};
    _trainingEventMonths.clear();
    for (final item in response) {
      final event = item['events'];
      if (event is! Map) continue;
      if ((event['event_type'] ?? '').toString().toLowerCase() != 'treino') {
        continue;
      }
      final date = _parseEventDate(event['event_date']);
      if (date == null) continue;
      final month = DateTime(date.year, date.month, 1);
      months['${month.year}-${month.month}'] = month;
      final eventId = (event['id'] ?? '').toString();
      if (eventId.isNotEmpty) _trainingEventMonths[eventId] = month;
    }

    _trainingMonths = months.values.toList()..sort((a, b) => b.compareTo(a));
    if (_trainingMonths.isNotEmpty &&
        !_trainingMonths.any((month) =>
            month.year == _selectedMonth.year &&
            month.month == _selectedMonth.month)) {
      _selectedMonth = _trainingMonths.first;
    }
  }

  List<DateTime> _monthOptions() {
    return _trainingMonths;
  }

  String _monthLabel(DateTime date) {
    const names = [
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

    return '${names[date.month - 1]}/${date.year}';
  }

  Future<void> _carregarAtletasVisiveis() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await _loadTrainingMonths();

      final currentCoach = _supabase.auth.currentUser;
      if (currentCoach == null) throw Exception('Usuário não autenticado.');

      final visibleIds =
          await _permissionService.getVisibleUserIdsForPage('avaliacoes');

      if (visibleIds.isEmpty) {
        if (!mounted) return;
        setState(() {
          _athletes = [];
          _loading = false;
        });
        return;
      }

      final profilesResponse = await _supabase
          .from('profiles')
          .select('id, full_name, avatar_url, gender, user_type')
          .inFilter('id', visibleIds)
          .eq('user_type', 'athlete')
          .eq('is_active', true)
          .order('full_name', ascending: true);

      final loadedProfiles =
          List<Map<String, dynamic>>.from(profilesResponse as List);

      final profiles = await _permissionService.filterAthletesForCurrentCoach(
        loadedProfiles,
      );

      final athleteIds = profiles
          .map((profile) => (profile['id'] ?? '').toString())
          .where((id) => id.isNotEmpty)
          .toList();

      if (athleteIds.isEmpty) {
        if (!mounted) return;
        setState(() {
          _athletes = [];
          _loading = false;
        });
        return;
      }

      final evaluationsResponse = await _supabase
          .from('training_evaluations')
          .select(
            'athlete_id, event_id, slot, tipo, fundamento, motivo, observacao, created_at, score',
          )
          .inFilter('athlete_id', athleteIds)
          .eq('coach_id', currentCoach.id)
          .order('created_at', ascending: false);

      final evaluations =
          List<Map<String, dynamic>>.from(evaluationsResponse as List);

      final evaluationsByAthlete = <String, List<Map<String, dynamic>>>{};
      for (final row in evaluations) {
        final athleteId = (row['athlete_id'] ?? '').toString();
        if (athleteId.isEmpty) continue;
        evaluationsByAthlete.putIfAbsent(athleteId, () => []);
        evaluationsByAthlete[athleteId]!.add(row);
      }

      final list = profiles.map((profile) {
        final athleteId = (profile['id'] ?? '').toString();
        final athleteEvaluations =
            evaluationsByAthlete[athleteId] ?? <Map<String, dynamic>>[];

        int destaques = 0;
        int atencoes = 0;
        int totalAvaliacoesMes = 0;
        bool hasMonthlyComplete = false;
        DateTime? lastEvaluationDate;
        final attentionFundamentCount = <String, int>{};

        for (final evaluation in athleteEvaluations) {
          final tipo = (evaluation['tipo'] ?? '').toString().toLowerCase();
          final fundamento = (evaluation['fundamento'] ?? '').toString().trim();
          final createdAt = DateTime.tryParse(
            (evaluation['created_at'] ?? '').toString(),
          )?.toLocal();
          final eventId = (evaluation['event_id'] ?? '').toString();
          final eventMonth = _trainingEventMonths[eventId];

          if (createdAt != null &&
              (lastEvaluationDate == null ||
                  createdAt.isAfter(lastEvaluationDate!))) {
            lastEvaluationDate = createdAt;
          }

          final isInSelectedMonth = eventMonth != null
              ? eventMonth.year == _selectedMonth.year &&
                  eventMonth.month == _selectedMonth.month
              : createdAt != null &&
                  !createdAt.isBefore(_monthStart) &&
                  createdAt.isBefore(_monthEnd);

          if (tipo == 'completa' && isInSelectedMonth) {
            hasMonthlyComplete = true;
          }

          if (!isInSelectedMonth) continue;

          if (tipo == 'destaque' ||
              tipo == 'atencao' ||
              tipo == 'atenção' ||
              tipo == 'rapida') {
            totalAvaliacoesMes++;
          }

          if (tipo == 'destaque') {
            destaques++;
          } else if (tipo == 'atencao' || tipo == 'atenção') {
            atencoes++;
            if (fundamento.isNotEmpty) {
              attentionFundamentCount[fundamento] =
                  (attentionFundamentCount[fundamento] ?? 0) + 1;
            }
          }
        }

        String mainFocus = 'A definir';
        if (attentionFundamentCount.isNotEmpty) {
          final sorted = attentionFundamentCount.entries.toList()
            ..sort((a, b) => b.value.compareTo(a.value));
          mainFocus = sorted.first.key;
        } else {
          final lastFundamento = athleteEvaluations
              .map((e) => (e['fundamento'] ?? '').toString().trim())
              .firstWhere((value) => value.isNotEmpty, orElse: () => '');
          if (lastFundamento.isNotEmpty) {
            mainFocus = lastFundamento;
          }
        }

        String generalEvolution = 'Sem histórico no mês';
        if (totalAvaliacoesMes > 0) {
          if (destaques > atencoes) {
            generalEvolution = 'Melhorando';
          } else if (atencoes > destaques) {
            generalEvolution = 'Precisa de atenção';
          } else {
            generalEvolution = 'Estável';
          }
        }

        return AthleteEvaluationStatus(
          athleteId: athleteId,
          athleteName: (profile['full_name'] ?? 'Atleta').toString(),
          avatarUrl: (profile['avatar_url'] ?? '').toString(),
          gender: (profile['gender'] ?? '').toString(),
          generalEvolution: generalEvolution,
          mainFocus: mainFocus,
          evaluationsSinceLastFull: totalAvaliacoesMes % 3,
          isPresent: true,
          totalEvaluations: totalAvaliacoesMes,
          destaques: destaques,
          atencoes: atencoes,
          hasMonthlyComplete: hasMonthlyComplete,
          lastEvaluationAt: lastEvaluationDate,
        );
      }).toList();

      if (!mounted) return;
      setState(() {
        _athletes = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Erro ao carregar atletas visíveis: $e';
        _loading = false;
      });
    }
  }

  Widget _buildEvaluationBackground() {
    return Stack(
      children: [
        Positioned.fill(
          child: const OlympusBrandBackgroundImage(
            fit: BoxFit.cover,
          ),
        ),
        Positioned.fill(
          child: Container(color: Colors.black.withOpacity(0.35)),
        ),
      ],
    );
  }

  Widget _buildFilters() {
    if (_trainingMonths.isEmpty) {
      return Container(
        margin: const EdgeInsets.fromLTRB(16, 14, 16, 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.96),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          children: [
            Icon(Icons.event_busy_outlined, color: olympusBlue),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Nenhum mês com treino encontrado.',
                style: TextStyle(
                  color: olympusBlue,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      );
    }
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.96),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: olympusBorder),
      ),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final screenWidth = MediaQuery.of(context).size.width;
              final fieldWidth = screenWidth < 390 ? double.infinity : 172.0;

              return SizedBox(
                width: fieldWidth,
                child: DropdownButtonFormField<DateTime>(
                  value: DateTime(_selectedMonth.year, _selectedMonth.month, 1),
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Mês',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  items: _monthOptions().map((month) {
                    return DropdownMenuItem<DateTime>(
                      value: month,
                      child: Text(
                        _monthLabel(month),
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                  }).toList(),
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() => _selectedMonth = value);
                    _carregarAtletasVisiveis();
                  },
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildMonthlyReminder() {
    if (!_isCurrentMonth ||
        !_isLastFourDaysOfMonth ||
        _pendingMonthlyCount == 0) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: olympusWarning.withOpacity(0.96),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(0.38)),
      ),
      child: Row(
        children: [
          Icon(Icons.notifications_active_outlined, color: olympusBlue),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Fechamento mensal: $_pendingMonthlyCount atleta(s) ainda sem avaliação completa.',
              style: TextStyle(
                color: olympusBlue,
                fontSize: 13,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openCompleteEvaluation(AthleteEvaluationStatus athlete) async {
    if (!_canCompleteMonthly) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Avaliação completa liberada apenas nos últimos 4 dias do mês atual.',
          ),
        ),
      );
      return;
    }

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CoachCompleteMonthlyEvaluationPage(
          athletes: [athlete],
        ),
      ),
    );

    await _carregarAtletasVisiveis();
  }

  Future<void> _viewAthleteEvaluations(AthleteEvaluationStatus athlete) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AthleteEvaluationsHistoryPage(
          athlete: athlete,
          selectedMonth: _selectedMonth,
          canEdit: true,
        ),
      ),
    );

    await _carregarAtletasVisiveis();
  }

  bool _hasCompleteMonthlyEvaluation(AthleteEvaluationStatus athlete) {
    return athlete.hasMonthlyComplete;
  }

  bool _matchesCompleteEvaluationFilter(AthleteEvaluationStatus athlete) {
    if (_completeEvaluationFilter == 'Todas') return true;
    if (_completeEvaluationFilter == 'Realizadas') {
      return _hasCompleteMonthlyEvaluation(athlete);
    }
    if (_completeEvaluationFilter == 'Pendentes') {
      return !_hasCompleteMonthlyEvaluation(athlete);
    }
    return true;
  }

  Widget _buildCompleteEvaluationFilterChip(String label) {
    final selected = _completeEvaluationFilter == label;

    final icon = label == 'Realizadas'
        ? Icons.check_circle_outline_rounded
        : label == 'Pendentes'
            ? Icons.pending_actions_rounded
            : Icons.list_alt_rounded;

    return ChoiceChip(
      avatar: Icon(
        icon,
        size: 16,
        color: selected ? Colors.white : olympusBlue,
      ),
      label: Text(label),
      selected: selected,
      showCheckmark: false,
      selectedColor: olympusBlue,
      backgroundColor: const Color(0xFFF7FAFC),
      side: BorderSide(
        color: selected ? olympusBlue : olympusBorder,
      ),
      labelStyle: TextStyle(
        color: selected ? Colors.white : olympusBlue,
        fontWeight: FontWeight.w900,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
      onSelected: (_) {
        setState(() => _completeEvaluationFilter = label);
      },
    );
  }

  Widget _buildCompleteEvaluationFilterBar() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.96),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: olympusBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.10),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.only(left: 4, bottom: 10),
            child: Text(
              'Avaliação completa',
              style: TextStyle(
                color: olympusBlue,
                fontSize: 13,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildCompleteEvaluationFilterChip('Todas'),
                const SizedBox(width: 8),
                _buildCompleteEvaluationFilterChip('Realizadas'),
                const SizedBox(width: 8),
                _buildCompleteEvaluationFilterChip('Pendentes'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredAthletes;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Avaliação de Atletas'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Theme.of(context).colorScheme.onPrimary,
        actions: [
          IconButton(
            onPressed: _carregarAtletasVisiveis,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Stack(
        children: [
          Positioned.fill(child: _buildEvaluationBackground()),
          Column(
            children: [
              _buildFilters(),
              _buildCompleteEvaluationFilterBar(),
              _buildMonthlyReminder(),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _error != null
                        ? Center(
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
                        : filtered.isEmpty
                            ? const Center(
                                child: Padding(
                                  padding: EdgeInsets.all(24),
                                  child: Text(
                                    'Nenhum atleta encontrado para o mês e status selecionados.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              )
                            : RefreshIndicator(
                                onRefresh: _carregarAtletasVisiveis,
                                child: ListView.separated(
                                  padding:
                                      const EdgeInsets.fromLTRB(16, 0, 16, 24),
                                  itemCount: filtered.length,
                                  separatorBuilder: (_, __) =>
                                      const SizedBox(height: 12),
                                  itemBuilder: (context, index) {
                                    final athlete = filtered[index];

                                    return _AthleteEvaluationCard(
                                      athlete: athlete,
                                      completeEnabled: _canCompleteMonthly &&
                                          !athlete.hasMonthlyComplete,
                                      completeStatus: athlete.hasMonthlyComplete
                                          ? 'Concluída'
                                          : _canCompleteMonthly
                                              ? 'Pendente'
                                              : 'Bloqueada',
                                      onCompleteTap: () =>
                                          _openCompleteEvaluation(athlete),
                                      onViewTap: () =>
                                          _viewAthleteEvaluations(athlete),
                                    );
                                  },
                                ),
                              ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AthleteEvaluationCard extends StatelessWidget {
  const _AthleteEvaluationCard({
    required this.athlete,
    required this.completeEnabled,
    required this.completeStatus,
    required this.onCompleteTap,
    required this.onViewTap,
  });

  final AthleteEvaluationStatus athlete;
  final bool completeEnabled;
  final String completeStatus;
  final VoidCallback onCompleteTap;
  final VoidCallback onViewTap;

  static const Color olympusPurple = Color(0xFF7C3AED);
  static const Color olympusSuccess = Color(0xFF16A34A);
  static const Color olympusWarning = Color(0xFFF59E0B);
  static const Color olympusMuted = Color(0xFF53657B);
  static const Color olympusBorder = Color(0xFFE4EDF5);

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final compact = screenWidth < 390;
    final tablet = screenWidth >= 700;

    final avatarUrl = athlete.avatarUrl.trim();
    final cardPadding = compact
        ? 14.0
        : tablet
            ? 18.0
            : 16.0;
    final avatarRadius = compact
        ? 23.0
        : tablet
            ? 28.0
            : 26.0;
    final titleSize = compact
        ? 15.0
        : tablet
            ? 18.0
            : 16.0;
    final bodySize = compact
        ? 11.5
        : tablet
            ? 13.5
            : 12.5;

    Widget avatar() {
      return CircleAvatar(
        radius: avatarRadius,
        backgroundColor: olympusBlue,
        backgroundImage: avatarUrl.isNotEmpty ? NetworkImage(avatarUrl) : null,
        child: avatarUrl.isEmpty
            ? Text(
                athlete.athleteName.isNotEmpty
                    ? athlete.athleteName.substring(0, 1)
                    : '?',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: compact ? 14 : 16,
                ),
              )
            : null,
      );
    }

    Widget statusChip() {
      final done = athlete.hasMonthlyComplete;
      return Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 8 : 10,
          vertical: compact ? 6 : 7,
        ),
        decoration: BoxDecoration(
          color: (done ? olympusSuccess : olympusWarning).withOpacity(0.12),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: (done ? olympusSuccess : olympusWarning).withOpacity(0.24),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              done ? Icons.check_circle_outline : Icons.warning_amber_rounded,
              size: compact ? 14 : 15,
              color: done ? olympusSuccess : olympusWarning,
            ),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                done ? 'Mensal concluída' : 'Mensal pendente',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: done ? olympusSuccess : olympusWarning,
                  fontSize: bodySize,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
      );
    }

    Widget buttons() {
      return Column(
        children: [
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton.icon(
              onPressed: onViewTap,
              icon: const Icon(Icons.auto_stories_outlined, size: 18),
              label: Text(
                athlete.totalEvaluations == 0
                    ? 'Ver histórico do mês'
                    : 'Ver ${athlete.totalEvaluations} avaliação(ões) do treino',
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: olympusBlue,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
                textStyle: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            height: 44,
            child: OutlinedButton.icon(
              onPressed: completeEnabled ? onCompleteTap : null,
              icon: const Icon(Icons.assignment_turned_in_outlined, size: 16),
              label: Text('Avaliação mensal • $completeStatus'),
              style: OutlinedButton.styleFrom(
                foregroundColor: olympusBlue,
                disabledForegroundColor: olympusMuted,
                side: BorderSide(
                  color: completeEnabled ? olympusGold : olympusBorder,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                textStyle: TextStyle(
                  fontSize: compact ? 11.5 : 12.5,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
        ],
      );
    }

    Widget details() {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            athlete.athleteName,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: titleSize,
              fontWeight: FontWeight.w900,
              color: const Color(0xFF17324D),
              height: 1.08,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Evolução: ${athlete.generalEvolution}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: bodySize,
              fontWeight: FontWeight.w800,
              color: const Color(0xFF53657B),
            ),
          ),
          const SizedBox(height: 3),
          Text(
            'Foco: ${athlete.mainFocus}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: bodySize,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF6A7E94),
            ),
          ),
          const SizedBox(height: 3),
          Text(
            'Treinos do mês: ${athlete.destaques} destaque(s) • ${athlete.atencoes} ponto(s) de atenção',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: bodySize,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF6A7E94),
            ),
          ),
          const SizedBox(height: 3),
          Text(
            'Última: ${athlete.lastEvaluationLabel}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: bodySize,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF6A7E94),
            ),
          ),
          const SizedBox(height: 8),
          statusChip(),
          const SizedBox(height: 12),
          buttons(),
        ],
      );
    }

    return Material(
      color: Colors.white.withOpacity(0.97),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: EdgeInsets.all(cardPadding),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFE4EDF5)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.10),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: compact
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      avatar(),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          athlete.athleteName,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: titleSize,
                            fontWeight: FontWeight.w900,
                            color: const Color(0xFF17324D),
                            height: 1.08,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Evolução: ${athlete.generalEvolution}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: bodySize,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF53657B),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'Foco: ${athlete.mainFocus}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: bodySize,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF6A7E94),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'Treinos do mês: ${athlete.destaques} destaque(s) • ${athlete.atencoes} ponto(s) de atenção',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: bodySize,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF6A7E94),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'Última: ${athlete.lastEvaluationLabel}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: bodySize,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF6A7E94),
                    ),
                  ),
                  const SizedBox(height: 8),
                  statusChip(),
                  const SizedBox(height: 12),
                  buttons(),
                ],
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  avatar(),
                  const SizedBox(width: 14),
                  Expanded(child: details()),
                ],
              ),
      ),
    );
  }
}

class AthleteEvaluationFormPage extends StatefulWidget {
  const AthleteEvaluationFormPage({
    super.key,
    required this.athleteName,
    required this.isCompleteMode,
    required this.currentFocus,
  });

  final String athleteName;
  final bool isCompleteMode;
  final String currentFocus;

  @override
  State<AthleteEvaluationFormPage> createState() =>
      _AthleteEvaluationFormPageState();
}

class _AthleteEvaluationFormPageState extends State<AthleteEvaluationFormPage> {

  final TextEditingController _focusController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();

  bool _sendToAthlete = false;
  String _generalEvolution = 'Melhorando';

  @override
  void initState() {
    super.initState();
    _focusController.text = widget.currentFocus;
  }

  @override
  void dispose() {
    _focusController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  void _submit() {
    if (_focusController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Informe o principal foco da atleta.')),
      );
      return;
    }

    Navigator.pop(
      context,
      EvaluationSubmissionResult(
        isComplete: false,
        generalEvolution: _generalEvolution,
        mainFocus: _focusController.text.trim(),
        sendToAthlete: _sendToAthlete,
        messageToAthlete: _notesController.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FB),
      appBar: AppBar(
        title: Text('Avaliação rápida - ${widget.athleteName}'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Theme.of(context).colorScheme.onPrimary,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          DropdownButtonFormField<String>(
            value: _generalEvolution,
            decoration: const InputDecoration(
              labelText: 'Evolução geral',
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(value: 'Melhorando', child: Text('Melhorando')),
              DropdownMenuItem(value: 'Estável', child: Text('Estável')),
              DropdownMenuItem(
                value: 'Precisa de atenção',
                child: Text('Precisa de atenção'),
              ),
            ],
            onChanged: (value) {
              if (value == null) return;
              setState(() => _generalEvolution = value);
            },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _focusController,
            decoration: const InputDecoration(
              labelText: 'Principal foco',
              hintText: 'Ex: saque, recepção, posicionamento',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE4EDF5)),
            ),
            child: SwitchListTile(
              value: _sendToAthlete,
              contentPadding: EdgeInsets.zero,
              activeColor: olympusBlue,
              secondary: Icon(
                Icons.send_outlined,
                color: olympusBlue,
              ),
              title: const Text(
                'Enviar para atleta',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
              subtitle: const Text(
                'Ao salvar, a atleta receberá a mensagem abaixo.',
              ),
              onChanged: (value) {
                setState(() => _sendToAthlete = value);
              },
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _notesController,
            maxLines: 4,
            decoration: InputDecoration(
              labelText: _sendToAthlete
                  ? 'Mensagem para atleta'
                  : 'Observação do técnico',
              hintText: _sendToAthlete
                  ? 'Escreva o feedback que será enviado para a atleta.'
                  : 'Observação interna da avaliação rápida.',
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _submit,
              icon: const Icon(Icons.save_outlined),
              label: const Text('Salvar avaliação rápida'),
              style: ElevatedButton.styleFrom(
                backgroundColor: olympusBlue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class EvaluationSubmissionResult {
  EvaluationSubmissionResult({
    required this.isComplete,
    required this.generalEvolution,
    required this.mainFocus,
    required this.sendToAthlete,
    required this.messageToAthlete,
  });

  final bool isComplete;
  final String generalEvolution;
  final String mainFocus;
  final bool sendToAthlete;
  final String messageToAthlete;
}

class FundamentEvaluationModel {
  FundamentEvaluationModel({
    required this.name,
    this.score = 3,
    this.trend = 'Estável',
  }) : notesController = TextEditingController();

  final String name;
  int score;
  String trend;
  final TextEditingController notesController;
}
