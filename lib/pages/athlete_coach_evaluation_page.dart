import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/coach_evaluation_service.dart';
import 'athlete_coach_evaluation_history_page.dart';

enum _CoachEvaluationMode {
  menu,
  training,
  monthly,
}

class AthleteCoachEvaluationPage extends StatefulWidget {
  const AthleteCoachEvaluationPage({super.key});

  static Route<void> route() {
    return MaterialPageRoute<void>(
      builder: (_) => const AthleteCoachEvaluationPage(),
    );
  }

  @override
  State<AthleteCoachEvaluationPage> createState() =>
      _AthleteCoachEvaluationPageState();
}

class _AthleteCoachEvaluationPageState
    extends State<AthleteCoachEvaluationPage> {
  static const Color olympusBlue = Color(0xFF1E3A5F);
  static const Color olympusGold = Color(0xFFD4AF37);
  static const Color olympusBg = Color(0xFFF4F7FB);
  static const Color olympusMuted = Color(0xFF53657B);
  static const Color olympusBorder = Color(0xFFE4EDF5);
  static const Color olympusDanger = Color(0xFFDC2626);
  static const Color olympusSuccess = Color(0xFF16A34A);
  static const Color olympusPurple = Color(0xFF6C4AB6);

  final CoachEvaluationService _service = CoachEvaluationService();

  final TextEditingController _positiveController = TextEditingController();
  final TextEditingController _improvementController = TextEditingController();
  final TextEditingController _commentController = TextEditingController();

  final TextEditingController _monthlyPositiveController =
      TextEditingController();
  final TextEditingController _monthlyImprovementController =
      TextEditingController();
  final TextEditingController _monthlyCommunicationController =
      TextEditingController();
  final TextEditingController _monthlySuggestionController =
      TextEditingController();

  bool _loading = true;
  bool _saving = false;
  bool _monthlyEnabled = false;
  bool _anonymous = false;
  bool _monthlyAnonymous = false;
  String? _error;

  _CoachEvaluationMode _mode = _CoachEvaluationMode.menu;

  List<Map<String, dynamic>> _events = [];
  List<Map<String, dynamic>> _coaches = [];
  List<Map<String, dynamic>> _monthlyCoaches = [];

  String _selectedEventId = '';
  String _selectedCoachId = '';
  String _selectedMonthlyCoachId = '';

  int _selectedMonth = DateTime.now().month;
  int _selectedYear = DateTime.now().year;

  int _ratingGeneral = 5;
  int _ratingClarity = 5;
  int _ratingRespect = 5;
  int _ratingTrainingQuality = 5;

  int _monthlyGeneral = 5;
  int _monthlyClarity = 5;
  int _monthlyRespect = 5;
  int _monthlyTrainingQuality = 5;
  int _monthlyMotivation = 5;
  int _monthlyOrganization = 5;
  int _monthlyEvolution = 5;
  int _monthlyCommunication = 5;

  @override
  void initState() {
    super.initState();
    _loadInitial();
  }

  @override
  void dispose() {
    _positiveController.dispose();
    _improvementController.dispose();
    _commentController.dispose();
    _monthlyPositiveController.dispose();
    _monthlyImprovementController.dispose();
    _monthlyCommunicationController.dispose();
    _monthlySuggestionController.dispose();
    super.dispose();
  }

  String _asString(dynamic value) => (value ?? '').toString().trim();

  Future<void> _loadInitial() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) throw Exception('Usuário não autenticado.');

      final monthlyEnabled = await _service.isMonthlyEvaluationEnabled();

      final events = await _service.loadEligibleTrainingsForAthleteByMonth(
        athleteId: user.id,
        month: _selectedMonth,
        year: _selectedYear,
      );

      final monthlyCoaches = await _service.loadMonthlyEnabledCoaches(
        athleteId: user.id,
      );

      if (!mounted) return;
      setState(() {
        _monthlyEnabled = monthlyEnabled;
        _events = events;
        _monthlyCoaches = monthlyCoaches;
        _selectedMonthlyCoachId = monthlyCoaches.isNotEmpty
            ? _asString(monthlyCoaches.first['id'])
            : '';
        _loading = false;
      });

      if (events.isNotEmpty) {
        await _selectEvent(_asString(events.first['id']));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Erro ao carregar avaliação: $e';
        _loading = false;
      });
    }
  }

  Future<void> _loadTrainingsForSelectedMonth() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    setState(() {
      _loading = true;
      _error = null;
      _selectedEventId = '';
      _selectedCoachId = '';
      _coaches = [];
    });

    try {
      final events = await _service.loadEligibleTrainingsForAthleteByMonth(
        athleteId: user.id,
        month: _selectedMonth,
        year: _selectedYear,
      );

      if (!mounted) return;
      setState(() {
        _events = events;
        _loading = false;
      });

      if (events.isNotEmpty) {
        await _selectEvent(_asString(events.first['id']));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Erro ao carregar treinos do mês: $e';
        _loading = false;
      });
    }
  }

  Future<void> _selectEvent(String eventId) async {
    setState(() {
      _selectedEventId = eventId;
      _selectedCoachId = '';
      _coaches = [];
    });

    if (eventId.isEmpty) return;

    try {
      final coaches = await _service.loadCoachesForTraining(eventId: eventId);

      if (!mounted) return;

      setState(() {
        _coaches = coaches;
        _selectedCoachId =
            coaches.isNotEmpty ? _asString(coaches.first['id']) : '';
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _error = 'Erro ao carregar treinadores: $e';
      });
    }
  }

  Future<void> _submitTrainingEvaluation() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    if (_selectedEventId.isEmpty || _selectedCoachId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecione o treino e o treinador.')),
      );
      return;
    }

    setState(() => _saving = true);

    try {
      await _service.submitTrainingEvaluation(
        athleteId: user.id,
        coachId: _selectedCoachId,
        eventId: _selectedEventId,
        referenceMonth: _selectedMonth,
        referenceYear: _selectedYear,
        ratingGeneral: _ratingGeneral,
        ratingClarity: _ratingClarity,
        ratingRespect: _ratingRespect,
        ratingTrainingQuality: _ratingTrainingQuality,
        positivePoint: _positiveController.text,
        improvementPoint: _improvementController.text,
        comment: _commentController.text,
        anonymousToCoach: _anonymous,
      );

      if (!mounted) return;

      _positiveController.clear();
      _improvementController.clear();
      _commentController.clear();

      setState(() {
        _ratingGeneral = 5;
        _ratingClarity = 5;
        _ratingRespect = 5;
        _ratingTrainingQuality = 5;
        _anonymous = false;
        _saving = false;
      });

      await _loadTrainingsForSelectedMonth();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Avaliação do treino enviada com sucesso.'),
          backgroundColor: olympusSuccess,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao enviar avaliação: $e'),
          backgroundColor: olympusDanger,
        ),
      );
    }
  }

  Future<void> _submitMonthlyEvaluation() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    if (!_monthlyEnabled) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text('A avaliação mensal ainda não foi liberada pelo admin.'),
        ),
      );
      return;
    }

    if (_selectedMonthlyCoachId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecione o treinador.')),
      );
      return;
    }

    setState(() => _saving = true);

    try {
      await _service.submitMonthlyEvaluation(
        athleteId: user.id,
        coachId: _selectedMonthlyCoachId,
        referenceMonth: _selectedMonth,
        referenceYear: _selectedYear,
        ratingGeneral: _monthlyGeneral,
        ratingClarity: _monthlyClarity,
        ratingRespect: _monthlyRespect,
        ratingTrainingQuality: _monthlyTrainingQuality,
        ratingMotivation: _monthlyMotivation,
        ratingOrganization: _monthlyOrganization,
        ratingEvolution: _monthlyEvolution,
        ratingCommunication: _monthlyCommunication,
        positivePoint: _monthlyPositiveController.text,
        improvementPoint: _monthlyImprovementController.text,
        communicationComment: _monthlyCommunicationController.text,
        suggestion: _monthlySuggestionController.text,
        anonymousToCoach: _monthlyAnonymous,
      );

      if (!mounted) return;

      _monthlyPositiveController.clear();
      _monthlyImprovementController.clear();
      _monthlyCommunicationController.clear();
      _monthlySuggestionController.clear();

      setState(() {
        _monthlyGeneral = 5;
        _monthlyClarity = 5;
        _monthlyRespect = 5;
        _monthlyTrainingQuality = 5;
        _monthlyMotivation = 5;
        _monthlyOrganization = 5;
        _monthlyEvolution = 5;
        _monthlyCommunication = 5;
        _monthlyAnonymous = false;
        _saving = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Avaliação mensal enviada com sucesso.'),
          backgroundColor: olympusSuccess,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao enviar avaliação mensal: $e'),
          backgroundColor: olympusDanger,
        ),
      );
    }
  }

  String _eventLabel(Map<String, dynamic> event) {
    final name = _asString(event['event_name']).isEmpty
        ? 'Treino'
        : _asString(event['event_name']);
    final date = _asString(event['event_date']);
    final time = _asString(event['event_time']);
    if (date.isEmpty && time.isEmpty) return name;
    if (time.isEmpty) return '$name • $date';
    return '$name • $date às $time';
  }

  String _monthName(int month) {
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
    return months[month];
  }

  List<DropdownMenuItem<String>> _monthItems() {
    final now = DateTime.now();
    final minimum = DateTime(2026, 5, 1);
    final current = DateTime(now.year, now.month, 1);

    final items = <DropdownMenuItem<String>>[];

    if (current.isBefore(minimum)) {
      const value = '2026-05';
      items.add(
        const DropdownMenuItem<String>(
          value: value,
          child: Text('Maio / 2026'),
        ),
      );
      return items;
    }

    var cursor = current;
    while (!cursor.isBefore(minimum)) {
      final value = '${cursor.year}-${cursor.month.toString().padLeft(2, '0')}';
      items.add(
        DropdownMenuItem<String>(
          value: value,
          child: Text('${_monthName(cursor.month)} / ${cursor.year}'),
        ),
      );
      cursor = DateTime(cursor.year, cursor.month - 1, 1);
    }

    return items;
  }

  String get _selectedMonthValue {
    if (_selectedYear < 2026 || (_selectedYear == 2026 && _selectedMonth < 5)) {
      return '2026-05';
    }
    return '$_selectedYear-${_selectedMonth.toString().padLeft(2, '0')}';
  }

  void _setMonthValue(String value) {
    final parts = value.split('-');
    if (parts.length != 2) return;

    final parsedYear = int.tryParse(parts[0]) ?? DateTime.now().year;
    final parsedMonth = int.tryParse(parts[1]) ?? DateTime.now().month;

    if (parsedYear < 2026 || (parsedYear == 2026 && parsedMonth < 5)) {
      setState(() {
        _selectedYear = 2026;
        _selectedMonth = 5;
      });
    } else {
      setState(() {
        _selectedYear = parsedYear;
        _selectedMonth = parsedMonth;
      });
    }

    _loadTrainingsForSelectedMonth();
  }

  Widget _ratingRow({
    required String label,
    required int value,
    required ValueChanged<int> onChanged,
    String? helper,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: olympusBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: olympusBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    color: olympusBlue,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Row(
                children: List.generate(5, (index) {
                  final rating = index + 1;
                  return IconButton(
                    visualDensity: VisualDensity.compact,
                    onPressed: () => onChanged(rating),
                    icon: Icon(
                      rating <= value
                          ? Icons.star_rounded
                          : Icons.star_border_rounded,
                      color: olympusGold,
                    ),
                  );
                }),
              ),
            ],
          ),
          if (helper != null && helper.trim().isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              helper,
              style: const TextStyle(
                color: olympusMuted,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _textField({
    required String label,
    required TextEditingController controller,
    int maxLines = 3,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        decoration: InputDecoration(
          labelText: label,
          filled: true,
          fillColor: olympusBg,
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
            borderSide: const BorderSide(color: olympusBlue),
          ),
        ),
      ),
    );
  }

  Widget _modeButton({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback? onTap,
    String? badge,
  }) {
    final disabled = onTap == null;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Ink(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: disabled ? Colors.grey.shade100 : Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color:
                    disabled ? Colors.grey.shade300 : color.withOpacity(0.35),
                width: 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: disabled
                      ? Colors.black.withOpacity(0.03)
                      : color.withOpacity(0.10),
                  blurRadius: 14,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: color.withOpacity(disabled ? 0.08 : 0.16),
                  ),
                  child: Icon(
                    icon,
                    color: disabled ? Colors.grey : color,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              title,
                              style: TextStyle(
                                color: disabled ? Colors.grey : olympusBlue,
                                fontSize: 17,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          if (badge != null)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 9,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: disabled
                                    ? Colors.grey.withOpacity(0.14)
                                    : color.withOpacity(0.14),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                badge,
                                style: TextStyle(
                                  color: disabled ? Colors.grey : color,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: TextStyle(
                          color: disabled ? Colors.grey : olympusMuted,
                          fontWeight: FontWeight.w600,
                          height: 1.25,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Icon(
                  Icons.arrow_forward_ios_rounded,
                  color: disabled ? Colors.grey : color,
                  size: 18,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _monthFilter() {
    return DropdownButtonFormField<String>(
      value: _selectedMonthValue,
      decoration: InputDecoration(
        labelText: 'Mês',
        filled: true,
        fillColor: olympusBg,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
      ),
      items: _monthItems(),
      onChanged: (value) {
        if (value == null) return;
        _setMonthValue(value);
      },
    );
  }

  Widget _menuContent() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      children: [
        const Text(
          'Avaliação do Treinador',
          style: TextStyle(
            color: olympusBlue,
            fontSize: 23,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 5),
        const Text(
          'Escolha o tipo de avaliação que deseja preencher.',
          style: TextStyle(color: olympusMuted, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 20),
        _modeButton(
          icon: Icons.fact_check_rounded,
          title: 'Avaliar treino',
          subtitle:
              'Avaliação por treino realizado. Sempre liberado e com filtro mensal.',
          color: olympusBlue,
          badge: 'Liberado',
          onTap: () => setState(() => _mode = _CoachEvaluationMode.training),
        ),
        _modeButton(
          icon: Icons.calendar_month_rounded,
          title: 'Avaliação mensal',
          subtitle: _monthlyEnabled
              ? 'Questionário amplo sobre os treinos e condução do mês.'
              : 'Disponível somente quando o admin liberar.',
          color: olympusPurple,
          badge: _monthlyEnabled ? 'Liberado' : 'Bloqueado',
          onTap: _monthlyEnabled
              ? () async {
                  final user = Supabase.instance.client.auth.currentUser;
                  if (user == null) return;
                  final enabledCoaches =
                      await _service.loadMonthlyEnabledCoaches(
                    athleteId: user.id,
                  );
                  if (!mounted) return;
                  setState(() {
                    _monthlyCoaches = enabledCoaches;
                    _selectedMonthlyCoachId = enabledCoaches.isNotEmpty
                        ? _asString(enabledCoaches.first['id'])
                        : '';
                    _mode = _CoachEvaluationMode.monthly;
                  });
                }
              : null,
        ),
        _modeButton(
          icon: Icons.history_rounded,
          title: 'Avaliações realizadas',
          subtitle: 'Consulte suas avaliações anteriores, organizadas por mês.',
          color: olympusSuccess,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => const AthleteCoachEvaluationHistoryPage(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _trainingContent() {
    if (_events.isEmpty) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        children: [
          const SizedBox(height: 14),
          _monthFilter(),
          const SizedBox(height: 24),
          const Center(
            child: Text(
              'Nenhum treino com check-in disponível para avaliação neste mês.',
              textAlign: TextAlign.center,
              style:
                  TextStyle(color: olympusMuted, fontWeight: FontWeight.w800),
            ),
          ),
        ],
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      children: [
        const SizedBox(height: 14),
        const Text(
          'Avaliar treino',
          style: TextStyle(
            color: olympusBlue,
            fontSize: 22,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Avalie um treino realizado no mês selecionado.',
          style: TextStyle(color: olympusMuted, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 18),
        _monthFilter(),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          value: _selectedEventId.isEmpty ? null : _selectedEventId,
          decoration: InputDecoration(
            labelText: 'Treino',
            filled: true,
            fillColor: olympusBg,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
          ),
          items: _events.map((event) {
            return DropdownMenuItem<String>(
              value: _asString(event['id']),
              child: Text(_eventLabel(event), overflow: TextOverflow.ellipsis),
            );
          }).toList(),
          onChanged: (value) => _selectEvent(value ?? ''),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          value: _selectedCoachId.isEmpty ? null : _selectedCoachId,
          decoration: InputDecoration(
            labelText: 'Treinador',
            filled: true,
            fillColor: olympusBg,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
          ),
          items: _coaches.map((coach) {
            return DropdownMenuItem<String>(
              value: _asString(coach['id']),
              child: Text(
                _asString(coach['full_name']).isEmpty
                    ? 'Treinador'
                    : _asString(coach['full_name']),
                overflow: TextOverflow.ellipsis,
              ),
            );
          }).toList(),
          onChanged: (value) => setState(() => _selectedCoachId = value ?? ''),
        ),
        if (_coaches.isEmpty) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              color: olympusGold.withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: olympusGold.withOpacity(0.28)),
            ),
            child: const Text(
              'Nenhum treinador foi encontrado entre os convocados deste treino.',
              style: TextStyle(
                color: olympusBlue,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
        const SizedBox(height: 18),
        _ratingRow(
          label: 'Nota geral',
          value: _ratingGeneral,
          onChanged: (value) => setState(() => _ratingGeneral = value),
        ),
        _ratingRow(
          label: 'Clareza',
          value: _ratingClarity,
          onChanged: (value) => setState(() => _ratingClarity = value),
        ),
        _ratingRow(
          label: 'Respeito',
          value: _ratingRespect,
          onChanged: (value) => setState(() => _ratingRespect = value),
        ),
        _ratingRow(
          label: 'Qualidade do treino',
          value: _ratingTrainingQuality,
          onChanged: (value) => setState(() => _ratingTrainingQuality = value),
        ),
        const SizedBox(height: 8),
        _textField(label: 'Ponto positivo', controller: _positiveController),
        _textField(
          label: 'Ponto a melhorar',
          controller: _improvementController,
        ),
        _textField(
          label: 'Comentário adicional',
          controller: _commentController,
        ),
        SwitchListTile(
          value: _anonymous,
          onChanged: (value) => setState(() => _anonymous = value),
          title: const Text(
            'Enviar como anônimo para o treinador',
            style: TextStyle(color: olympusBlue, fontWeight: FontWeight.w800),
          ),
          subtitle: const Text(
            'O admin receberá a avaliação e decidirá se libera a visualização ao treinador.',
          ),
        ),
        const SizedBox(height: 14),
        ElevatedButton.icon(
          onPressed: _saving ? null : _submitTrainingEvaluation,
          icon: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.send_rounded),
          label: Text(_saving ? 'Enviando...' : 'Enviar avaliação'),
          style: ElevatedButton.styleFrom(
            backgroundColor: olympusBlue,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 15),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
        ),
      ],
    );
  }

  Widget _monthlyContent() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      children: [
        const SizedBox(height: 14),
        const Text(
          'Avaliação mensal',
          style: TextStyle(
            color: olympusBlue,
            fontSize: 22,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Questionário amplo sobre os treinos e a condução do mês.',
          style: TextStyle(color: olympusMuted, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 18),
        _monthFilter(),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          value:
              _selectedMonthlyCoachId.isEmpty ? null : _selectedMonthlyCoachId,
          decoration: InputDecoration(
            labelText: 'Treinador',
            filled: true,
            fillColor: olympusBg,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
          ),
          items: _monthlyCoaches.map((coach) {
            return DropdownMenuItem<String>(
              value: _asString(coach['id']),
              child: Text(
                _asString(coach['full_name']).isEmpty
                    ? 'Treinador'
                    : _asString(coach['full_name']),
                overflow: TextOverflow.ellipsis,
              ),
            );
          }).toList(),
          onChanged: (value) {
            setState(() => _selectedMonthlyCoachId = value ?? '');
          },
        ),
        const SizedBox(height: 18),
        _ratingRow(
          label: 'Nota geral do mês',
          helper: 'Avaliação geral da condução dos treinos no mês.',
          value: _monthlyGeneral,
          onChanged: (value) => setState(() => _monthlyGeneral = value),
        ),
        _ratingRow(
          label: 'Clareza nas orientações',
          helper: 'Explicação dos objetivos, exercícios e correções.',
          value: _monthlyClarity,
          onChanged: (value) => setState(() => _monthlyClarity = value),
        ),
        _ratingRow(
          label: 'Respeito e postura',
          helper: 'Forma de comunicação, escuta e relacionamento.',
          value: _monthlyRespect,
          onChanged: (value) => setState(() => _monthlyRespect = value),
        ),
        _ratingRow(
          label: 'Qualidade técnica dos treinos',
          helper: 'Organização, intensidade e conteúdo técnico.',
          value: _monthlyTrainingQuality,
          onChanged: (value) => setState(() => _monthlyTrainingQuality = value),
        ),
        _ratingRow(
          label: 'Motivação do grupo',
          helper: 'Capacidade de manter o time engajado.',
          value: _monthlyMotivation,
          onChanged: (value) => setState(() => _monthlyMotivation = value),
        ),
        _ratingRow(
          label: 'Organização do mês',
          helper: 'Pontualidade, planejamento e sequência dos treinos.',
          value: _monthlyOrganization,
          onChanged: (value) => setState(() => _monthlyOrganization = value),
        ),
        _ratingRow(
          label: 'Evolução percebida',
          helper: 'Quanto você sentiu evolução individual e coletiva.',
          value: _monthlyEvolution,
          onChanged: (value) => setState(() => _monthlyEvolution = value),
        ),
        _ratingRow(
          label: 'Comunicação',
          helper: 'Comunicação antes, durante e após os treinos.',
          value: _monthlyCommunication,
          onChanged: (value) => setState(() => _monthlyCommunication = value),
        ),
        const SizedBox(height: 8),
        _textField(
          label: 'Principal ponto positivo do mês',
          controller: _monthlyPositiveController,
        ),
        _textField(
          label: 'Principal ponto a melhorar',
          controller: _monthlyImprovementController,
        ),
        _textField(
          label: 'Comentário sobre comunicação e condução',
          controller: _monthlyCommunicationController,
        ),
        _textField(
          label: 'Sugestão para o próximo mês',
          controller: _monthlySuggestionController,
        ),
        SwitchListTile(
          value: _monthlyAnonymous,
          onChanged: (value) => setState(() => _monthlyAnonymous = value),
          title: const Text(
            'Enviar como anônimo para o treinador',
            style: TextStyle(color: olympusBlue, fontWeight: FontWeight.w800),
          ),
          subtitle: const Text(
            'O admin receberá a avaliação e decidirá se libera a visualização ao treinador.',
          ),
        ),
        const SizedBox(height: 14),
        ElevatedButton.icon(
          onPressed: _saving ? null : _submitMonthlyEvaluation,
          icon: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.send_rounded),
          label: Text(_saving ? 'Enviando...' : 'Enviar avaliação mensal'),
          style: ElevatedButton.styleFrom(
            backgroundColor: olympusPurple,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 15),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
        ),
      ],
    );
  }

  // Remove ou deixe vazio caso não use mais:
  Widget _backToMenuButton() {
    return const SizedBox.shrink();
  }

  Widget _content() {
    if (_loading) return const Center(child: CircularProgressIndicator());

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _error!,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: olympusDanger,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      );
    }

    switch (_mode) {
      case _CoachEvaluationMode.menu:
        return _menuContent();
      case _CoachEvaluationMode.training:
        return _trainingContent();
      case _CoachEvaluationMode.monthly:
        return _monthlyContent();
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _mode == _CoachEvaluationMode.menu,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _mode != _CoachEvaluationMode.menu) {
          setState(() => _mode = _CoachEvaluationMode.menu);
        }
      },
      child: Scaffold(
        backgroundColor: olympusBg,
        appBar: AppBar(
          title: Text(_mode == _CoachEvaluationMode.menu
              ? 'Escolha a avaliação'
              : 'Avaliação do Treinador'),
          backgroundColor: olympusBlue,
          foregroundColor: Colors.white,
          leading: _mode == _CoachEvaluationMode.menu
              ? null
              : IconButton(
                  icon: const Icon(Icons.arrow_back_rounded),
                  onPressed: () {
                    setState(() => _mode = _CoachEvaluationMode.menu);
                  },
                ),
          actions: [
            IconButton(
              tooltip: 'Atualizar',
              onPressed: _loadInitial,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
        body: Stack(
          children: [
            Positioned.fill(
              child: Image.asset(
                'assets/images/monte_olimpo_v2.png',
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(color: olympusBlue),
              ),
            ),
            Positioned.fill(
              child: Container(color: olympusBlue.withOpacity(0.58)),
            ),
            Positioned.fill(
              child: SafeArea(
                child: Container(
                  margin: const EdgeInsets.fromLTRB(10, 10, 10, 12),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.94),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: Colors.white.withOpacity(0.45)),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: _content(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
