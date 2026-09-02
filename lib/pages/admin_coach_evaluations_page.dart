import 'package:flutter/material.dart';
import '../theme/olympus_theme.dart';

import '../services/coach_evaluation_service.dart';

class AdminCoachEvaluationsPage extends StatefulWidget {
  const AdminCoachEvaluationsPage({super.key});

  static Route<void> route() {
    return MaterialPageRoute<void>(
      builder: (_) => const AdminCoachEvaluationsPage(),
    );
  }

  @override
  State<AdminCoachEvaluationsPage> createState() =>
      _AdminCoachEvaluationsPageState();
}

class _AdminCoachEvaluationsPageState extends State<AdminCoachEvaluationsPage> {
  static const Color olympusBg = Color(0xFFF4F7FB);
  static const Color olympusMuted = Color(0xFF53657B);
  static const Color olympusBorder = Color(0xFFE4EDF5);
  static const Color olympusDanger = Color(0xFFDC2626);
  static const Color olympusSuccess = Color(0xFF16A34A);
  static const Color olympusPurple = Color(0xFF6C4AB6);

  final CoachEvaluationService _service = CoachEvaluationService();

  bool _loading = true;
  bool _savingEnabled = false;
  bool _monthlyEnabled = false;
  bool _savingCoaches = false;
  String? _error;
  String _search = '';
  String _coachSearch = '';
  String _typeFilter = '';
  String _statusView = 'pending';
  late String _selectedMonthKey;

  List<Map<String, dynamic>> _evaluations = [];
  List<Map<String, dynamic>> _allCoaches = [];
  Set<String> _monthlyEnabledCoachIds = <String>{};

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedMonthKey = _monthKey(now.month, now.year);
    _load();
  }

  String _asString(dynamic value) => (value ?? '').toString().trim();

  String _monthKey(int month, int year) =>
      '$year-${month.toString().padLeft(2, '0')}';

  String _evaluationMonthKey(Map<String, dynamic> row) {
    final month = int.tryParse(_asString(row['reference_month']));
    final year = int.tryParse(_asString(row['reference_year']));
    if (month != null && year != null && month >= 1 && month <= 12) {
      return _monthKey(month, year);
    }
    final created = DateTime.tryParse(_asString(row['created_at']))?.toLocal();
    final date = created ?? DateTime.now();
    return _monthKey(date.month, date.year);
  }

  List<String> get _availableMonthKeys {
    final now = DateTime.now();
    final keys = <String>{
      _monthKey(now.month, now.year),
      ..._evaluations.map(_evaluationMonthKey),
    }.toList()
      ..sort((a, b) => b.compareTo(a));
    return keys;
  }

  String _monthLabelFromKey(String key) {
    final parts = key.split('-');
    if (parts.length != 2) return key;
    return _monthLabel(parts[1], parts[0]);
  }

  bool _isSent(Map<String, dynamic> row) =>
      row['visible_to_coach'] == true ||
      _asString(row['admin_review_status']).toLowerCase() == 'approved';

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final enabled = await _service.isMonthlyEvaluationEnabled();
      final evaluations = await _service.loadAdminEvaluations();
      final coaches = await _service.loadCoaches();
      final enabledCoachIds = await _service.loadMonthlyEnabledCoachIds();

      if (!mounted) return;
      setState(() {
        _monthlyEnabled = enabled;
        _evaluations = evaluations;
        _allCoaches = coaches;
        _monthlyEnabledCoachIds = enabledCoachIds.toSet();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Erro ao carregar avaliações: $e';
        _loading = false;
      });
    }
  }

  Future<void> _toggleMonthlyEnabled(bool value) async {
    setState(() {
      _monthlyEnabled = value;
      _savingEnabled = true;
    });

    try {
      await _service.setMonthlyEvaluationEnabled(value);
      if (!mounted) return;
      setState(() => _savingEnabled = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _monthlyEnabled = !value;
        _savingEnabled = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao salvar configuração: $e'),
          backgroundColor: olympusDanger,
        ),
      );
    }
  }

  Future<void> _toggleMonthlyCoach(String coachId, bool enabled) async {
    if (coachId.trim().isEmpty) return;

    final next = Set<String>.from(_monthlyEnabledCoachIds);

    if (enabled) {
      next.add(coachId);
    } else {
      next.remove(coachId);
    }

    setState(() {
      _monthlyEnabledCoachIds = next;
      _savingCoaches = true;
    });

    try {
      await _service.setMonthlyEnabledCoachIds(next.toList());
      if (!mounted) return;
      setState(() => _savingCoaches = false);
    } catch (e) {
      if (!mounted) return;
      setState(() => _savingCoaches = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao salvar técnicos habilitados: $e'),
          backgroundColor: olympusDanger,
        ),
      );
    }
  }

  List<Map<String, dynamic>> get _filteredCoachesForMonthly {
    final query = _coachSearch.trim().toLowerCase();
    if (query.isEmpty) return _allCoaches;

    return _allCoaches.where((coach) {
      final name = _asString(coach['full_name']).toLowerCase();
      return name.contains(query);
    }).toList();
  }

  Widget _monthlyCoachSelectorCard() {
    final coaches = _filteredCoachesForMonthly;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: olympusBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Técnicos habilitados para avaliação mensal',
            style: TextStyle(
              color: olympusBlue,
              fontWeight: FontWeight.w900,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Somente os técnicos marcados aparecerão para os atletas na Avaliação mensal.',
            style: TextStyle(
              color: olympusMuted,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            onChanged: (value) => setState(() => _coachSearch = value),
            decoration: InputDecoration(
              hintText: 'Buscar técnico...',
              prefixIcon: const Icon(Icons.search_rounded),
              filled: true,
              fillColor: olympusBg,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: olympusBorder),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: olympusBorder),
              ),
            ),
          ),
          const SizedBox(height: 10),
          if (_savingCoaches)
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: LinearProgressIndicator(minHeight: 2),
            ),
          if (coaches.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 14),
              child: Text(
                'Nenhum técnico encontrado.',
                style: TextStyle(
                  color: olympusMuted,
                  fontWeight: FontWeight.w700,
                ),
              ),
            )
          else
            ...coaches.map((coach) {
              final coachId = _asString(coach['id']);
              final coachName = _asString(coach['full_name']).isEmpty
                  ? 'Treinador'
                  : _asString(coach['full_name']);
              final enabled = _monthlyEnabledCoachIds.contains(coachId);

              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: enabled ? olympusSuccess.withOpacity(0.07) : olympusBg,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: enabled
                        ? olympusSuccess.withOpacity(0.25)
                        : olympusBorder,
                  ),
                ),
                child: SwitchListTile(
                  value: enabled,
                  onChanged: _savingCoaches
                      ? null
                      : (value) => _toggleMonthlyCoach(coachId, value),
                  activeThumbColor: olympusSuccess,
                  title: Text(
                    coachName,
                    style: TextStyle(
                      color: olympusBlue,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  subtitle: Text(
                    enabled
                        ? 'Liberado para avaliação mensal'
                        : 'Não aparece para os atletas na avaliação mensal',
                    style: const TextStyle(
                      color: olympusMuted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }

  Future<void> _setVisibleToCoach(
      Map<String, dynamic> row, bool visible) async {
    final id = _asString(row['id']);
    if (id.isEmpty) return;

    try {
      await _service.setEvaluationVisibleToCoach(
        evaluationId: id,
        visible: visible,
      );
      await _load();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            visible
                ? 'Avaliação liberada para o treinador.'
                : 'Avaliação removida da visualização do treinador.',
          ),
          backgroundColor: olympusSuccess,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao atualizar visibilidade: $e'),
          backgroundColor: olympusDanger,
        ),
      );
    }
  }

  Future<void> _deleteEvaluation(Map<String, dynamic> row) async {
    final id = _asString(row['id']);
    if (id.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: const Row(
          children: [
            Icon(Icons.delete_outline_rounded, color: olympusDanger),
            SizedBox(width: 10),
            Expanded(child: Text('Excluir avaliação?')),
          ],
        ),
        content: const Text(
          'Esta ação é permanente e a avaliação não poderá ser recuperada.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: olympusDanger),
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: const Icon(Icons.delete_rounded),
            label: const Text('Excluir'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    try {
      await _service.deleteEvaluation(id);
      if (!mounted) return;
      setState(() {
        _evaluations.removeWhere((item) => _asString(item['id']) == id);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Avaliação excluída.'),
          backgroundColor: olympusSuccess,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao excluir avaliação: $e'),
          backgroundColor: olympusDanger,
        ),
      );
    }
  }

  List<Map<String, dynamic>> get _filteredEvaluations {
    final query = _search.trim().toLowerCase();

    return _evaluations.where((row) {
      if (_evaluationMonthKey(row) != _selectedMonthKey) return false;
      final sent = _isSent(row);
      if (_statusView == 'sent' && !sent) return false;
      if (_statusView == 'pending' && sent) return false;

      final type = _asString(row['evaluation_type']).isEmpty
          ? 'training'
          : _asString(row['evaluation_type']);

      if (_typeFilter.isNotEmpty && type != _typeFilter) return false;

      if (query.isEmpty) return true;

      final athlete = row['athlete'];
      final coach = row['coach'];
      final event = row['events'];

      final text = [
        row['positive_point'],
        row['improvement_point'],
        row['comment'],
        row['communication_comment'],
        row['suggestion'],
        athlete is Map ? athlete['full_name'] : '',
        coach is Map ? coach['full_name'] : '',
        event is Map ? event['event_name'] : '',
        type,
      ].map(_asString).join(' ').toLowerCase();

      return text.contains(query);
    }).toList();
  }

  double _average(String field) {
    if (_filteredEvaluations.isEmpty) return 0;
    final total = _filteredEvaluations.fold<int>(
      0,
      (sum, row) => sum + (int.tryParse((row[field] ?? 0).toString()) ?? 0),
    );
    return total / _filteredEvaluations.length;
  }

  String _monthLabel(dynamic month, dynamic year) {
    final m = int.tryParse((month ?? '').toString());
    final y = int.tryParse((year ?? '').toString());

    if (m == null || y == null) return '';

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

    if (m < 1 || m > 12) return '$m/$y';
    return '${months[m]} / $y';
  }

  Widget _summaryCard({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: olympusBorder),
        ),
        child: Column(
          children: [
            Icon(icon, color: color),
            const SizedBox(height: 6),
            Text(
              value,
              style: TextStyle(
                color: color,
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: olympusMuted,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stars(int value) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (index) {
        return Icon(
          index < value ? Icons.star_rounded : Icons.star_border_rounded,
          size: 18,
          color: olympusGold,
        );
      }),
    );
  }

  Widget _metric(String label, dynamic value) {
    final rating = int.tryParse(value.toString()) ?? 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: olympusMuted,
            fontSize: 11,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 2),
        _stars(rating),
      ],
    );
  }

  Widget _textBlock(String title, String text) {
    if (text.trim().isEmpty) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: olympusBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: olympusBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: olympusBlue,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            text,
            style: const TextStyle(
              color: olympusMuted,
              fontWeight: FontWeight.w600,
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }

  Widget _typeChip({
    required String label,
    required String value,
    required Color color,
  }) {
    final selected = _typeFilter == value;

    return ChoiceChip(
      label: Text(label),
      selected: selected,
      showCheckmark: false,
      selectedColor: color.withOpacity(0.16),
      backgroundColor: Colors.white,
      labelStyle: TextStyle(
        color: selected ? color : olympusMuted,
        fontWeight: FontWeight.w900,
      ),
      side: BorderSide(
        color: selected ? color : olympusBorder,
      ),
      onSelected: (_) {
        setState(() {
          _typeFilter = selected ? '' : value;
        });
      },
    );
  }

  Widget _evaluationCard(Map<String, dynamic> row) {
    final athleteRaw = row['athlete'];
    final coachRaw = row['coach'];
    final eventRaw = row['events'];

    final athlete =
        athleteRaw is Map ? Map<String, dynamic>.from(athleteRaw) : {};
    final coach = coachRaw is Map ? Map<String, dynamic>.from(coachRaw) : {};
    final event = eventRaw is Map ? Map<String, dynamic>.from(eventRaw) : {};

    final type = _asString(row['evaluation_type']).isEmpty
        ? 'training'
        : _asString(row['evaluation_type']);
    final isMonthly = type == 'monthly';
    final anonymousToCoach =
        row['anonymous_to_coach'] == true || row['anonymous'] == true;
    final visibleToCoach = row['visible_to_coach'] == true;

    final athleteName = _asString(athlete['full_name']).isEmpty
        ? 'Atleta'
        : _asString(athlete['full_name']);
    final coachName = _asString(coach['full_name']).isEmpty
        ? 'Treinador'
        : _asString(coach['full_name']);

    final eventName = isMonthly
        ? 'Avaliação mensal • ${_monthLabel(row['reference_month'], row['reference_year'])}'
        : (_asString(event['event_name']).isEmpty
            ? 'Treino'
            : _asString(event['event_name']));

    final created = DateTime.tryParse(_asString(row['created_at']))?.toLocal();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isMonthly ? olympusPurple.withOpacity(0.24) : olympusBorder,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: isMonthly
                      ? olympusPurple.withOpacity(0.12)
                      : olympusBlue.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  isMonthly ? 'Mensal' : 'Treino',
                  style: TextStyle(
                    color: isMonthly ? olympusPurple : olympusBlue,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              if (anonymousToCoach)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                  decoration: BoxDecoration(
                    color: olympusGold.withOpacity(0.14),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    'Anônimo para treinador',
                    style: TextStyle(
                      color: olympusGold,
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: visibleToCoach
                      ? olympusSuccess.withOpacity(0.12)
                      : olympusMuted.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  visibleToCoach ? 'Liberado ao treinador' : 'Só admin',
                  style: TextStyle(
                    color: visibleToCoach ? olympusSuccess : olympusMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            coachName,
            style: TextStyle(
              color: olympusBlue,
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '$athleteName • $eventName',
            style: const TextStyle(
              color: olympusMuted,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (created != null) ...[
            const SizedBox(height: 2),
            Text(
              '${created.day.toString().padLeft(2, '0')}/'
              '${created.month.toString().padLeft(2, '0')}/'
              '${created.year} às ${created.hour.toString().padLeft(2, '0')}:'
              '${created.minute.toString().padLeft(2, '0')}',
              style: const TextStyle(
                color: olympusMuted,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 14,
            runSpacing: 8,
            children: [
              _metric('Geral', row['rating_general'] ?? 0),
              _metric('Clareza', row['rating_clarity'] ?? 0),
              _metric('Respeito', row['rating_respect'] ?? 0),
              _metric('Qualidade', row['rating_training_quality'] ?? 0),
              if (isMonthly) ...[
                _metric('Motivação', row['rating_motivation'] ?? 0),
                _metric('Organização', row['rating_organization'] ?? 0),
                _metric('Evolução', row['rating_evolution'] ?? 0),
                _metric('Comunicação', row['rating_communication'] ?? 0),
              ],
            ],
          ),
          _textBlock('Ponto positivo', _asString(row['positive_point'])),
          _textBlock('Ponto a melhorar', _asString(row['improvement_point'])),
          if (isMonthly)
            _textBlock(
              'Comunicação e condução',
              _asString(row['communication_comment']),
            ),
          if (isMonthly) _textBlock('Sugestão', _asString(row['suggestion'])),
          if (!isMonthly) _textBlock('Comentário', _asString(row['comment'])),
          const SizedBox(height: 12),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: visibleToCoach,
            onChanged: (value) => _setVisibleToCoach(row, value),
            title: Text(
              'Liberar visualização para o treinador',
              style: TextStyle(
                color: olympusBlue,
                fontWeight: FontWeight.w900,
              ),
            ),
            subtitle: Text(
              anonymousToCoach
                  ? 'Ao liberar, o treinador verá como anônimo.'
                  : 'Ao liberar, o treinador poderá visualizar a avaliação.',
              style: const TextStyle(
                color: olympusMuted,
                fontWeight: FontWeight.w600,
              ),
            ),
            activeThumbColor: olympusSuccess,
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () => _deleteEvaluation(row),
              style: TextButton.styleFrom(foregroundColor: olympusDanger),
              icon: const Icon(Icons.delete_outline_rounded, size: 19),
              label: const Text(
                'Excluir avaliação',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusButton({
    required String value,
    required String label,
    required int count,
    required IconData icon,
    required Color color,
  }) {
    final selected = _statusView == value;
    return Material(
      color: selected ? Colors.white : Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => setState(() => _statusView = value),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 11),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: selected ? color : Colors.white70),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: selected ? olympusBlue : Colors.white,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Container(
                constraints: const BoxConstraints(minWidth: 22),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: selected ? color.withOpacity(0.16) : Colors.white12,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '$count',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: selected ? color : Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
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

    final evaluations = _filteredEvaluations;
    final monthRows = _evaluations
        .where((row) => _evaluationMonthKey(row) == _selectedMonthKey)
        .toList();
    final pendingCount = monthRows.where((row) => !_isSent(row)).length;
    final sentCount = monthRows.where(_isSent).length;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: olympusBorder),
            ),
            child: SwitchListTile(
              value: _monthlyEnabled,
              onChanged: _savingEnabled ? null : _toggleMonthlyEnabled,
              title: Text(
                'Habilitar avaliação mensal',
                style: TextStyle(
                  color: olympusBlue,
                  fontWeight: FontWeight.w900,
                ),
              ),
              subtitle: const Text(
                'A avaliação por treino fica sempre liberada. Esta opção libera apenas o questionário mensal.',
              ),
              activeThumbColor: olympusSuccess,
            ),
          ),
          const SizedBox(height: 12),
          _monthlyCoachSelectorCard(),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: olympusBlue,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Row(
              children: [
                Expanded(
                  child: _statusButton(
                    value: 'pending',
                    label: 'Pendentes',
                    count: pendingCount,
                    icon: Icons.schedule_rounded,
                    color: olympusGold,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _statusButton(
                    value: 'sent',
                    label: 'Enviadas',
                    count: sentCount,
                    icon: Icons.check_circle_outline_rounded,
                    color: olympusSuccess,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Mês de referência',
            style: TextStyle(
              color: olympusBlue,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _availableMonthKeys.map((key) {
                final selected = key == _selectedMonthKey;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    selected: selected,
                    showCheckmark: false,
                    label: Text(_monthLabelFromKey(key)),
                    selectedColor: olympusGold,
                    backgroundColor: Colors.white,
                    side: BorderSide(
                      color: selected ? olympusGold : olympusBorder,
                    ),
                    labelStyle: TextStyle(
                      color: selected ? olympusBlue : olympusMuted,
                      fontWeight: FontWeight.w900,
                    ),
                    onSelected: (_) => setState(() => _selectedMonthKey = key),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _summaryCard(
                label: 'Respostas',
                value: evaluations.length.toString(),
                icon: Icons.forum_rounded,
                color: olympusBlue,
              ),
              const SizedBox(width: 8),
              _summaryCard(
                label: 'Média geral',
                value: _average('rating_general').toStringAsFixed(1),
                icon: Icons.star_rounded,
                color: olympusGold,
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            onChanged: (value) => setState(() => _search = value),
            decoration: InputDecoration(
              hintText: 'Buscar por treinador, atleta, treino ou comentário...',
              prefixIcon: const Icon(Icons.search_rounded),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: olympusBorder),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: olympusBorder),
              ),
            ),
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                ChoiceChip(
                  label: const Text('Todos'),
                  selected: _typeFilter.isEmpty,
                  showCheckmark: false,
                  selectedColor: olympusGold.withOpacity(0.16),
                  backgroundColor: Colors.white,
                  labelStyle: TextStyle(
                    color: _typeFilter.isEmpty ? olympusGold : olympusMuted,
                    fontWeight: FontWeight.w900,
                  ),
                  side: BorderSide(
                    color: _typeFilter.isEmpty ? olympusGold : olympusBorder,
                  ),
                  onSelected: (_) => setState(() => _typeFilter = ''),
                ),
                const SizedBox(width: 8),
                _typeChip(
                  label: 'Treino',
                  value: 'training',
                  color: olympusBlue,
                ),
                const SizedBox(width: 8),
                _typeChip(
                  label: 'Mensal',
                  value: 'monthly',
                  color: olympusPurple,
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          if (evaluations.isEmpty)
            Padding(
              padding: const EdgeInsets.all(28),
              child: Center(
                child: Text(
                  'Nenhuma avaliação ${_statusView == 'sent' ? 'enviada' : 'pendente'} neste mês.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: olympusMuted,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            )
          else
            ...evaluations.map(_evaluationCard),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: olympusBg,
      appBar: AppBar(
        title: const Text('Avaliações dos Treinadores'),
        backgroundColor: olympusBlue,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Atualizar',
            onPressed: _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SafeArea(top: false, child: _content()),
    );
  }
}
