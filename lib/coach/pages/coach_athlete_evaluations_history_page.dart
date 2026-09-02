import 'package:flutter/material.dart';
import '../../theme/olympus_theme.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'coach_athlete_evaluation_models.dart';

class AthleteEvaluationsHistoryPage extends StatefulWidget {
  const AthleteEvaluationsHistoryPage({
    super.key,
    required this.athlete,
    required this.selectedMonth,
    required this.canEdit,
  });

  final AthleteEvaluationStatus athlete;
  final DateTime selectedMonth;
  final bool canEdit;

  @override
  State<AthleteEvaluationsHistoryPage> createState() =>
      _AthleteEvaluationsHistoryPageState();
}

class _AthleteEvaluationsHistoryPageState
    extends State<AthleteEvaluationsHistoryPage> {
  final SupabaseClient _supabase = Supabase.instance.client;

  static const Color olympusPurple = Color(0xFF7C3AED);
  static const Color olympusBg = Color(0xFFF4F7FB);
  static const Color olympusMuted = Color(0xFF53657B);
  static const Color olympusBorder = Color(0xFFE4EDF5);
  static const Color olympusDanger = Color(0xFFDC2626);
  static const Color olympusSuccess = Color(0xFF16A34A);

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _evaluations = [];

  @override
  void initState() {
    super.initState();
    _loadEvaluations();
  }

  String _monthLabel() {
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
    return '${names[widget.selectedMonth.month - 1]}/${widget.selectedMonth.year}';
  }

  Future<void> _loadEvaluations() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final coach = _supabase.auth.currentUser;
      if (coach == null) throw Exception('Usuário não autenticado.');
      final rows = await _supabase
          .from('training_evaluations')
          .select(
            'id, event_id, coach_id, athlete_id, tipo, slot, motivo, fundamento, observacao, created_at, event_name, event_date, score',
          )
          .eq('athlete_id', widget.athlete.athleteId)
          .eq('coach_id', coach.id)
          .order('created_at', ascending: false);

      final evaluations = List<Map<String, dynamic>>.from(rows as List);
      final eventIds = evaluations
          .map((row) => (row['event_id'] ?? '').toString())
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList();
      final eventsById = <String, Map<String, dynamic>>{};
      if (eventIds.isNotEmpty) {
        final eventRows = await _supabase
            .from('events')
            .select('id, event_name, event_date, event_time')
            .inFilter('id', eventIds);
        for (final event
            in List<Map<String, dynamic>>.from(eventRows as List)) {
          eventsById[(event['id'] ?? '').toString()] = event;
        }
      }
      for (final evaluation in evaluations) {
        evaluation['training_event'] =
            eventsById[(evaluation['event_id'] ?? '').toString()];
      }

      evaluations.removeWhere((evaluation) {
        final event = evaluation['training_event'];
        final eventDate =
            event is Map ? _parseEventDate(event['event_date']) : null;
        final referenceDate = eventDate ??
            DateTime.tryParse(
              (evaluation['created_at'] ?? '').toString(),
            )?.toLocal();
        return referenceDate == null ||
            referenceDate.year != widget.selectedMonth.year ||
            referenceDate.month != widget.selectedMonth.month;
      });

      if (!mounted) return;
      setState(() {
        _evaluations = evaluations;
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

  String _formatDate(dynamic value) {
    final parsed = DateTime.tryParse((value ?? '').toString())?.toLocal();
    if (parsed == null) return 'Sem data';
    return '${parsed.day.toString().padLeft(2, '0')}/${parsed.month.toString().padLeft(2, '0')}/${parsed.year}';
  }

  Color _typeColor(String tipo) {
    final normalized = tipo.toLowerCase();
    if (normalized == 'destaque') return olympusSuccess;
    if (normalized == 'atencao' || normalized == 'atenção') {
      return const Color(0xFFF59E0B);
    }
    if (normalized == 'completa') return olympusGold;
    return olympusBlue;
  }

  DateTime? _parseEventDate(dynamic value) {
    final raw = (value ?? '').toString().trim();
    final parts = raw.split('/');
    if (parts.length == 3) {
      return DateTime.tryParse('${parts[2]}-${parts[1]}-${parts[0]}');
    }
    return DateTime.tryParse(raw)?.toLocal();
  }

  String _slotLabel(String slot) {
    final normalized = slot.toLowerCase();
    final number = RegExp(r'\d+').firstMatch(slot)?.group(0) ?? '';
    if (normalized.startsWith('destaque')) {
      return 'Destaque${number.isEmpty ? '' : ' $number'}';
    }
    if (normalized.startsWith('atencao') || normalized.startsWith('atenção')) {
      return 'Ponto de atenção${number.isEmpty ? '' : ' $number'}';
    }
    return slot.replaceAll('_', ' ');
  }

  Future<void> _editEvaluation(Map<String, dynamic> evaluation) async {
    final motivoController = TextEditingController(
      text: (evaluation['motivo'] ?? '').toString(),
    );
    final fundamentoController = TextEditingController(
      text: (evaluation['fundamento'] ?? '').toString(),
    );
    final observacaoController = TextEditingController(
      text: (evaluation['observacao'] ?? '').toString(),
    );
    final scoreController = TextEditingController(
      text: (evaluation['score'] ?? '').toString(),
    );

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
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
                    const SizedBox(height: 16),
                    Text(
                      'Editar avaliação',
                      style: TextStyle(
                        color: olympusBlue,
                        fontSize: 19,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: motivoController,
                      decoration: const InputDecoration(
                        labelText: 'Motivo / tendência',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: fundamentoController,
                      decoration: const InputDecoration(
                        labelText: 'Fundamento',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: scoreController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Score / nota',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: observacaoController,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        labelText: 'Observação',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => Navigator.pop(context, false),
                            icon: const Icon(Icons.close),
                            label: const Text('Cancelar'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () async {
                              final id = (evaluation['id'] ?? '').toString();
                              if (id.isEmpty) return;

                              await _supabase
                                  .from('training_evaluations')
                                  .update({
                                'motivo': motivoController.text.trim(),
                                'fundamento': fundamentoController.text.trim(),
                                'observacao': observacaoController.text.trim(),
                                'score':
                                    int.tryParse(scoreController.text.trim()),
                              }).eq('id', id);

                              if (context.mounted) {
                                Navigator.pop(context, true);
                              }
                            },
                            icon: const Icon(Icons.save_outlined),
                            label: const Text('Salvar'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: olympusBlue,
                              foregroundColor: Colors.white,
                            ),
                          ),
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

    motivoController.dispose();
    fundamentoController.dispose();
    observacaoController.dispose();
    scoreController.dispose();

    if (saved == true) {
      await _loadEvaluations();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Avaliação atualizada.'),
          backgroundColor: olympusSuccess,
        ),
      );
    }
  }

  Future<void> _deleteEvaluation(Map<String, dynamic> evaluation) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Excluir avaliação?'),
        content: const Text('Essa ação não pode ser desfeita.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: olympusDanger),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final id = (evaluation['id'] ?? '').toString();
    if (id.isEmpty) return;

    await _supabase.from('training_evaluations').delete().eq('id', id);
    await _loadEvaluations();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Avaliação excluída.'),
        backgroundColor: olympusDanger,
      ),
    );
  }

  Widget _evaluationCard(Map<String, dynamic> evaluation) {
    final tipo = (evaluation['tipo'] ?? 'avaliação').toString();
    final color = _typeColor(tipo);
    final motivo = (evaluation['motivo'] ?? '').toString();
    final fundamento = (evaluation['fundamento'] ?? '').toString();
    final observacao = (evaluation['observacao'] ?? '').toString();
    final slot = (evaluation['slot'] ?? '').toString();
    final score = (evaluation['score'] ?? '').toString();
    final event = evaluation['training_event'];
    final eventMap = event is Map ? event : const <String, dynamic>{};
    final eventName = (eventMap['event_name'] ?? '').toString();
    final eventDate = (eventMap['event_date'] ?? '').toString();
    final eventTime = (eventMap['event_time'] ?? '').toString();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.97),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: olympusBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.07),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  tipo.toUpperCase(),
                  style: TextStyle(
                    color: color,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const Spacer(),
              Text(
                _formatDate(evaluation['created_at']),
                style: const TextStyle(
                  color: olympusMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (eventName.isNotEmpty || eventDate.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
              decoration: BoxDecoration(
                color: olympusBlue.withOpacity(0.06),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.sports_volleyball_rounded,
                    color: olympusBlue,
                    size: 17,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      [
                        if (eventName.isNotEmpty) eventName,
                        if (eventDate.isNotEmpty)
                          '$eventDate${eventTime.isEmpty ? '' : ' • $eventTime'}',
                      ].join(' — '),
                      style: TextStyle(
                        color: olympusBlue,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (slot.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _slotLabel(slot),
                style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          if (fundamento.isNotEmpty) ...[
            const SizedBox(height: 5),
            Text(
              'Fundamento: $fundamento',
              style: TextStyle(
                color: olympusBlue,
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
          if (motivo.isNotEmpty) ...[
            const SizedBox(height: 5),
            Text(
              'Motivo: $motivo',
              style: const TextStyle(
                color: olympusMuted,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          if (score.isNotEmpty && score != 'null') ...[
            const SizedBox(height: 5),
            Text(
              'Score/nota: $score',
              style: const TextStyle(
                color: olympusMuted,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          if (observacao.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              observacao,
              style: const TextStyle(
                color: Color(0xFF6A7E94),
                fontSize: 13,
                fontWeight: FontWeight.w600,
                height: 1.35,
              ),
            ),
          ],
          if (widget.canEdit) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _editEvaluation(evaluation),
                    icon: const Icon(Icons.edit_outlined, size: 16),
                    label: const Text('Editar esta avaliação'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: olympusPurple,
                      foregroundColor: Colors.white,
                      elevation: 0,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 46,
                  child: IconButton.outlined(
                    onPressed: () => _deleteEvaluation(evaluation),
                    icon: const Icon(Icons.delete_outline, size: 18),
                    style: IconButton.styleFrom(
                      foregroundColor: olympusDanger,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const title = 'Avaliações dos treinos';

    return Scaffold(
      backgroundColor: olympusBg,
      appBar: AppBar(
        title: Text(title),
        backgroundColor: olympusBlue,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            onPressed: _loadEvaluations,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: const OlympusBrandBackgroundImage(
              fit: BoxFit.cover,
            ),
          ),
          Positioned.fill(
            child: Container(color: Colors.black.withOpacity(0.35)),
          ),
          SafeArea(
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
                    : ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          Container(
                            padding: const EdgeInsets.all(14),
                            margin: const EdgeInsets.only(bottom: 12),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.97),
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(color: olympusBorder),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  widget.athlete.athleteName,
                                  style: TextStyle(
                                    color: olympusBlue,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'Período: ${_monthLabel()}',
                                  style: const TextStyle(
                                    color: olympusMuted,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (_evaluations.isEmpty)
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.97),
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(color: olympusBorder),
                              ),
                              child: const Text(
                                'Nenhuma avaliação registrada neste mês.',
                                style: TextStyle(
                                  color: olympusMuted,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            )
                          else
                            ..._evaluations.map(_evaluationCard),
                        ],
                      ),
          ),
        ],
      ),
    );
  }
}
