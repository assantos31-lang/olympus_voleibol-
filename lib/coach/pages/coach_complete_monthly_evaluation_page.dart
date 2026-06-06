import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> sendEvaluationMessageToAthlete({
  required SupabaseClient supabase,
  required String athleteId,
  required String title,
  required String body,
}) async {
  final currentUser = supabase.auth.currentUser;

  // A tabela app_messages exige thread_id válido em app_message_threads.
  // Como a avaliação mensal não deve falhar por causa da mensagem,
  // o envio aqui é intencionalmente "best effort".
  //
  // Se já existir uma thread compatível no banco, a mensagem será enviada.
  // Se não existir, a avaliação continuará salva sem quebrar o fluxo.
  try {
    final existingThreads = await supabase
        .from('app_message_participants')
        .select('thread_id')
        .eq('user_id', athleteId)
        .limit(1);

    final threadRows = List<Map<String, dynamic>>.from(existingThreads as List);
    if (threadRows.isEmpty) return;

    final threadId = (threadRows.first['thread_id'] ?? '').toString().trim();
    if (threadId.isEmpty) return;

    await supabase.from('app_messages').insert({
      'thread_id': threadId,
      'sender_id': currentUser?.id,
      'sender_name': 'Treinador',
      'sender_type': 'coach',
      'body': '$title\n\n$body',
      'created_at': DateTime.now().toIso8601String(),
    });
  } catch (_) {
    // Não derruba o salvamento da avaliação caso a estrutura de mensagens
    // não tenha thread criada para a atleta.
    return;
  }
}

class CoachCompleteMonthlyEvaluationPage extends StatefulWidget {
  const CoachCompleteMonthlyEvaluationPage({
    super.key,
    required this.athletes,
  });

  final List<dynamic> athletes;

  @override
  State<CoachCompleteMonthlyEvaluationPage> createState() =>
      _CoachCompleteMonthlyEvaluationPageState();
}

class _CoachCompleteMonthlyEvaluationPageState
    extends State<CoachCompleteMonthlyEvaluationPage> {
  static const Color olympusBlue = Color(0xFF1E3A5F);
  static const Color olympusGold = Color(0xFFD4AF37);
  static const Color olympusBg = Color(0xFFF4F7FB);
  static const Color olympusCard = Colors.white;
  static const Color olympusText = Color(0xFF17324D);
  static const Color olympusMuted = Color(0xFF53657B);
  static const Color olympusSubtle = Color(0xFF6A7E94);
  static const Color olympusBorder = Color(0xFFE4EDF5);
  static const Color olympusSuccess = Color(0xFF16A34A);
  static const Color olympusWarning = Color(0xFFF59E0B);
  static const Color olympusDanger = Color(0xFFDC2626);

  final SupabaseClient _supabase = Supabase.instance.client;

  bool _saving = false;
  bool _sendToAthlete = false;
  String? _selectedAthleteId;

  final TextEditingController _mensagemAtletaController =
      TextEditingController();
  final TextEditingController _observacaoGeralController =
      TextEditingController();
  final TextEditingController _pontoForteController = TextEditingController();
  final TextEditingController _pontoMelhorarController =
      TextEditingController();

  String _evolucaoGeral = 'Estável';
  String _prioridade = 'Média';

  final List<String> _fundamentos = const [
    'Saque',
    'Recepção',
    'Toque',
    'Ataque',
    'Bloqueio',
    'Defesa',
    'Posicionamento tático',
    'Condicionamento físico',
  ];

  final Map<String, int> _notas = {};
  final Map<String, String> _tendencias = {};
  final Map<String, TextEditingController> _observacoesPorFundamento = {};

  @override
  void initState() {
    super.initState();

    _selectedAthleteId =
        widget.athletes.isNotEmpty ? widget.athletes.first.athleteId : null;

    for (final fundamento in _fundamentos) {
      _notas[fundamento] = 3;
      _tendencias[fundamento] = 'Estável';
      _observacoesPorFundamento[fundamento] = TextEditingController();
    }

    if (_selectedAthleteId != null) {
      _carregarAvaliacaoExistente(_selectedAthleteId!);
    }
  }

  @override
  void dispose() {
    _mensagemAtletaController.dispose();
    _observacaoGeralController.dispose();
    _pontoForteController.dispose();
    _pontoMelhorarController.dispose();

    for (final controller in _observacoesPorFundamento.values) {
      controller.dispose();
    }

    super.dispose();
  }

  bool _isMobile(BuildContext context) {
    return MediaQuery.of(context).size.width < 600;
  }

  bool get _isLastFourDaysOfMonth {
    final now = DateTime.now();
    final lastDay = DateTime(now.year, now.month + 1, 0).day;
    return now.day >= lastDay - 3;
  }

  String get _janelaAvaliacaoLabel {
    final now = DateTime.now();
    final lastDay = DateTime(now.year, now.month + 1, 0).day;
    final startDay = lastDay - 3;
    return '$startDay ao $lastDay';
  }

  dynamic get _selectedAthlete {
    if (_selectedAthleteId == null) return null;

    for (final athlete in widget.athletes) {
      if (athlete.athleteId == _selectedAthleteId) return athlete;
    }

    return null;
  }

  Future<void> _carregarAvaliacaoExistente(String athleteId) async {
    try {
      final now = DateTime.now();
      final start = DateTime(now.year, now.month, 1);
      final end = DateTime(now.year, now.month + 1, 1);

      final rows = await _supabase
          .from('training_evaluations')
          .select('slot, fundamento, motivo, observacao, score, created_at')
          .eq('athlete_id', athleteId)
          .eq('tipo', 'mensal_completa')
          .or('slot.eq.resumo_mensal,slot.like.completa_%')
          .gte('created_at', start.toIso8601String())
          .lt('created_at', end.toIso8601String())
          .order('created_at', ascending: false);

      _limparFormulario(manterAtleta: true);

      final list = List<Map<String, dynamic>>.from(rows as List);
      if (list.isEmpty) return;

      for (final row in list) {
        final slot = (row['slot'] ?? '').toString();

        if (slot == 'resumo_mensal') {
          final motivo = (row['motivo'] ?? '').toString();
          final parts = motivo.split('|').map((e) => e.trim()).toList();

          if (parts.isNotEmpty && parts[0].isNotEmpty) {
            _evolucaoGeral = parts[0];
          }
          if (parts.length > 1 && parts[1].isNotEmpty) {
            _prioridade = parts[1];
          }
          if (parts.length > 2) {
            _pontoForteController.text = parts[2];
          }
          if (parts.length > 3) {
            _pontoMelhorarController.text = parts[3];
          }

          _observacaoGeralController.text =
              (row['observacao'] ?? '').toString();
          continue;
        }

        final fundamento = (row['fundamento'] ?? '').toString();
        if (!_fundamentos.contains(fundamento)) continue;

        final score = row['score'];
        if (score is int) {
          _notas[fundamento] = score.clamp(1, 5);
        } else if (score is num) {
          _notas[fundamento] = score.toInt().clamp(1, 5);
        }

        final motivo = (row['motivo'] ?? '').toString();
        if (['Melhorando', 'Estável', 'Piorou'].contains(motivo)) {
          _tendencias[fundamento] = motivo;
        }

        _observacoesPorFundamento[fundamento]?.text =
            (row['observacao'] ?? '').toString();
      }

      if (mounted) setState(() {});
    } catch (_) {
      // Se não carregar histórico, mantém formulário disponível.
    }
  }

  void _limparFormulario({bool manterAtleta = false}) {
    _mensagemAtletaController.clear();
    _observacaoGeralController.clear();
    _pontoForteController.clear();
    _pontoMelhorarController.clear();
    _evolucaoGeral = 'Estável';
    _prioridade = 'Média';

    for (final fundamento in _fundamentos) {
      _notas[fundamento] = 3;
      _tendencias[fundamento] = 'Estável';
      _observacoesPorFundamento[fundamento]?.clear();
    }

    if (!manterAtleta) _selectedAthleteId = null;

    if (mounted) setState(() {});
  }

  int _mediaNotasArredondada() {
    if (_notas.isEmpty) return 3;
    final total = _notas.values.fold<int>(0, (sum, value) => sum + value);
    return (total / _notas.length).round().clamp(1, 5);
  }

  DateTime? _parseEventDate(dynamic value) {
    final raw = (value ?? '').toString().trim();
    if (raw.isEmpty) return null;

    try {
      final parts = raw.split('/');
      if (parts.length == 3) {
        return DateTime(
          int.parse(parts[2]),
          int.parse(parts[1]),
          int.parse(parts[0]),
        );
      }

      return DateTime.tryParse(raw);
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>?> _buscarEventoBaseParaAvaliacaoMensal(
    String athleteId,
  ) async {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, 1);
    final end = DateTime(now.year, now.month + 1, 1);

    // Avaliação completa é mensal, então não depende de check-in.
    // O evento é apenas referência opcional quando existir treino no mês.
    try {
      final eventsResponse = await _supabase
          .from('events')
          .select('id, event_name, event_type, event_date, event_time')
          .eq('event_type', 'treino');

      final events = List<Map<String, dynamic>>.from(eventsResponse as List);
      final eventosDoMes = <Map<String, dynamic>>[];

      for (final event in events) {
        final eventId = (event['id'] ?? '').toString();
        if (eventId.isEmpty) continue;

        final eventDate = _parseEventDate(event['event_date']);
        if (eventDate == null) continue;

        if (eventDate.isBefore(start) || !eventDate.isBefore(end)) continue;

        eventosDoMes.add({
          'id': eventId,
          'event_name': (event['event_name'] ?? 'Avaliação mensal').toString(),
          'event_date': (event['event_date'] ?? '').toString(),
          'event_time': (event['event_time'] ?? '').toString(),
          'eventDate': eventDate,
        });
      }

      if (eventosDoMes.isEmpty) return null;

      eventosDoMes.sort((a, b) {
        final ad = a['eventDate'] as DateTime;
        final bd = b['eventDate'] as DateTime;
        return bd.compareTo(ad);
      });

      return eventosDoMes.first;
    } catch (_) {
      return null;
    }
  }

  Future<void> _salvarAvaliacaoCompleta() async {
    if (!_isLastFourDaysOfMonth) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'A avaliação completa só pode ser feita nos últimos 4 dias do mês ($_janelaAvaliacaoLabel).',
          ),
          backgroundColor: olympusWarning,
        ),
      );
      return;
    }

    final user = _supabase.auth.currentUser;
    final athlete = _selectedAthlete;

    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Usuário não autenticado.')),
      );
      return;
    }

    if (athlete == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecione uma atleta.')),
      );
      return;
    }

    if (_pontoMelhorarController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Informe o principal ponto a melhorar.')),
      );
      return;
    }

    setState(() => _saving = true);

    try {
      final athleteId = athlete.athleteId;
      final now = DateTime.now();
      final start = DateTime(now.year, now.month, 1);
      final end = DateTime(now.year, now.month + 1, 1);
      final eventoBase = await _buscarEventoBaseParaAvaliacaoMensal(athleteId);
      final eventId = (eventoBase?['id'] ?? '').toString();
      final eventName =
          (eventoBase?['event_name'] ?? 'Avaliação completa mensal').toString();
      final eventDate = (eventoBase?['event_date'] ??
              '${now.year}-${now.month.toString().padLeft(2, '0')}-01')
          .toString();

      final existing = await _supabase
          .from('training_evaluations')
          .select('id')
          .eq('athlete_id', athleteId)
          .eq('tipo', 'mensal_completa')
          .or('slot.eq.resumo_mensal,slot.like.completa_%')
          .gte('created_at', start.toIso8601String())
          .lt('created_at', end.toIso8601String());

      final existingIds = List<Map<String, dynamic>>.from(existing as List)
          .map((row) => (row['id'] ?? '').toString())
          .where((id) => id.isNotEmpty)
          .toList();

      if (existingIds.isNotEmpty) {
        await _supabase
            .from('training_evaluations')
            .delete()
            .inFilter('id', existingIds);
      }

      final rows = <Map<String, dynamic>>[];

      rows.add({
        'event_id': eventId.isEmpty ? null : eventId,
        'event_name': eventName,
        'event_date': eventDate,
        'coach_id': user.id,
        'athlete_id': athleteId,
        'tipo': 'mensal_completa',
        'slot': 'resumo_mensal',
        'motivo':
            '$_evolucaoGeral | $_prioridade | ${_pontoForteController.text.trim()} | ${_pontoMelhorarController.text.trim()}',
        'fundamento': 'Resumo mensal',
        'observacao': _observacaoGeralController.text.trim(),
        'score': _mediaNotasArredondada(),
      });

      for (final fundamento in _fundamentos) {
        rows.add({
          'event_id': eventId.isEmpty ? null : eventId,
          'event_name': eventName,
          'event_date': eventDate,
          'coach_id': user.id,
          'athlete_id': athleteId,
          'tipo': 'mensal_completa',
          'slot': 'completa_${fundamento.toLowerCase().replaceAll(' ', '_')}',
          'motivo': _tendencias[fundamento] ?? 'Estável',
          'fundamento': fundamento,
          'observacao':
              _observacoesPorFundamento[fundamento]?.text.trim() ?? '',
          'score': _notas[fundamento] ?? 3,
        });
      }

      await _supabase.from('training_evaluations').insert(rows);

      if (_sendToAthlete) {
        final message = _mensagemAtletaController.text.trim().isEmpty
            ? 'Sua avaliação completa mensal foi registrada. Evolução: $_evolucaoGeral. Prioridade: $_prioridade. Ponto principal: ${_pontoMelhorarController.text.trim()}.'
            : _mensagemAtletaController.text.trim();

        await sendEvaluationMessageToAthlete(
          supabase: _supabase,
          athleteId: athleteId,
          title: 'Avaliação completa mensal',
          body: message,
        );
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Avaliação completa mensal salva para ${athlete.athleteName}.'),
          backgroundColor: olympusSuccess,
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao salvar avaliação completa mensal: $e'),
          backgroundColor: olympusDanger,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _buildBackground() {
    return Stack(
      children: [
        Positioned.fill(
          child: Image.asset(
            'assets/images/monte_olimpo_v2.png',
            fit: BoxFit.cover,
          ),
        ),
        Positioned.fill(
          child: Container(color: Colors.black.withOpacity(0.35)),
        ),
      ],
    );
  }

  Widget _buildWindowInfo(bool isMobile) {
    final opened = _isLastFourDaysOfMonth;

    return Container(
      padding: EdgeInsets.all(isMobile ? 12 : 14),
      decoration: BoxDecoration(
        color: opened
            ? olympusSuccess.withOpacity(0.12)
            : olympusWarning.withOpacity(0.14),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: opened
              ? olympusSuccess.withOpacity(0.28)
              : olympusWarning.withOpacity(0.35),
        ),
      ),
      child: Row(
        children: [
          Icon(
            opened ? Icons.check_circle_outline : Icons.lock_clock_rounded,
            color: opened ? olympusSuccess : olympusWarning,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              opened
                  ? 'Janela mensal aberta. Você pode preencher a avaliação completa.'
                  : 'Liberada apenas nos últimos 4 dias do mês ($_janelaAvaliacaoLabel).',
              style: TextStyle(
                color: opened ? olympusSuccess : olympusBlue,
                fontWeight: FontWeight.w900,
                fontSize: isMobile ? 12 : 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCard({
    required List<Widget> children,
    EdgeInsetsGeometry? padding,
  }) {
    return Container(
      width: double.infinity,
      padding: padding ?? const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: olympusCard.withOpacity(0.97),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: olympusBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }

  Widget _buildHeader(bool isMobile) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(isMobile ? 18 : 22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          colors: [
            Color(0xFF071A30),
            Color(0xFF123861),
            Color(0xFF2C5F8D),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: olympusGold.withOpacity(0.70), width: 1.15),
        boxShadow: [
          BoxShadow(
            color: olympusGold.withOpacity(0.20),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
          BoxShadow(
            color: Colors.black.withOpacity(0.24),
            blurRadius: 22,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            top: -42,
            right: -28,
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
                  Container(
                    width: isMobile ? 54 : 62,
                    height: isMobile ? 54 : 62,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      gradient: const LinearGradient(
                        colors: [
                          Color(0xFFF8E08E),
                          Color(0xFFD4AF37),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: olympusGold.withOpacity(0.24),
                          blurRadius: 18,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.assignment_turned_in_rounded,
                      color: olympusBlue,
                      size: 31,
                    ),
                  ),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Text(
                      'Avaliação completa mensal',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: isMobile ? 22 : 25,
                        fontWeight: FontWeight.w900,
                        height: 1.05,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: olympusSuccess.withOpacity(0.16),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: olympusSuccess.withOpacity(0.35)),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.check_circle_outline_rounded,
                      color: Colors.white,
                      size: 22,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Janela mensal aberta',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: isMobile ? 13 : 14,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAthleteSelector(bool isMobile) {
    final athlete = _selectedAthlete;

    return _buildCard(
      padding: EdgeInsets.all(isMobile ? 16 : 18),
      children: [
        Row(
          children: [
            Container(
              width: isMobile ? 46 : 54,
              height: isMobile ? 46 : 54,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  colors: [
                    Color(0xFF1E3A5F),
                    Color(0xFF2C5F8D),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: olympusBlue.withOpacity(0.22),
                    blurRadius: 14,
                    offset: const Offset(0, 7),
                  ),
                ],
              ),
              child: const Icon(
                Icons.person_rounded,
                color: Colors.white,
                size: 26,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Atleta selecionado',
                    style: TextStyle(
                      color: olympusMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    athlete == null
                        ? 'Nenhum atleta disponível'
                        : athlete.athleteName,
                    style: TextStyle(
                      color: olympusBlue,
                      fontSize: isMobile ? 18 : 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: olympusGold.withOpacity(0.14),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: olympusGold.withOpacity(0.35)),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.workspace_premium_rounded,
                    color: olympusGold,
                    size: 16,
                  ),
                  SizedBox(width: 5),
                  Text(
                    'Mensal',
                    style: TextStyle(
                      color: olympusBlue,
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSummaryCard(bool isMobile) {
    return _buildCard(
      padding: EdgeInsets.all(isMobile ? 14 : 16),
      children: [
        Text(
          'Resumo geral',
          style: TextStyle(
            color: olympusBlue,
            fontSize: isMobile ? 15 : 16,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          value: _evolucaoGeral,
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
          onChanged: _saving
              ? null
              : (value) {
                  if (value == null) return;
                  setState(() => _evolucaoGeral = value);
                },
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          value: _prioridade,
          decoration: const InputDecoration(
            labelText: 'Prioridade de acompanhamento',
            border: OutlineInputBorder(),
          ),
          items: const [
            DropdownMenuItem(value: 'Baixa', child: Text('Baixa')),
            DropdownMenuItem(value: 'Média', child: Text('Média')),
            DropdownMenuItem(value: 'Alta', child: Text('Alta')),
          ],
          onChanged: _saving
              ? null
              : (value) {
                  if (value == null) return;
                  setState(() => _prioridade = value);
                },
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _pontoForteController,
          enabled: !_saving,
          decoration: const InputDecoration(
            labelText: 'Ponto forte',
            hintText: 'Ex: liderança, saque, regularidade',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _pontoMelhorarController,
          enabled: !_saving,
          decoration: const InputDecoration(
            labelText: 'Principal ponto a melhorar',
            hintText: 'Ex: recepção, tomada de decisão',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _observacaoGeralController,
          enabled: !_saving,
          maxLines: 4,
          decoration: const InputDecoration(
            labelText: 'Observação geral',
            hintText: 'Resumo mensal da atleta',
            border: OutlineInputBorder(),
          ),
        ),
      ],
    );
  }

  Widget _buildFundamentoCard(String fundamento, bool isMobile) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: EdgeInsets.all(isMobile ? 12 : 14),
      decoration: BoxDecoration(
        color: olympusCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: olympusBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            fundamento,
            style: TextStyle(
              color: olympusText,
              fontSize: isMobile ? 14 : 15,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final narrow = constraints.maxWidth < 380;

              final notaField = DropdownButtonFormField<int>(
                value: _notas[fundamento],
                decoration: const InputDecoration(
                  labelText: 'Nota',
                  border: OutlineInputBorder(),
                ),
                items: List.generate(
                  5,
                  (index) => DropdownMenuItem<int>(
                    value: index + 1,
                    child: Text('${index + 1}'),
                  ),
                ),
                onChanged: _saving
                    ? null
                    : (value) {
                        if (value == null) return;
                        setState(() => _notas[fundamento] = value);
                      },
              );

              final tendenciaField = DropdownButtonFormField<String>(
                value: _tendencias[fundamento],
                decoration: const InputDecoration(
                  labelText: 'Tendência',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(
                    value: 'Melhorando',
                    child: Text('Melhorando'),
                  ),
                  DropdownMenuItem(value: 'Estável', child: Text('Estável')),
                  DropdownMenuItem(value: 'Piorou', child: Text('Piorou')),
                ],
                onChanged: _saving
                    ? null
                    : (value) {
                        if (value == null) return;
                        setState(() => _tendencias[fundamento] = value);
                      },
              );

              if (narrow) {
                return Column(
                  children: [
                    notaField,
                    const SizedBox(height: 10),
                    tendenciaField,
                  ],
                );
              }

              return Row(
                children: [
                  Expanded(child: notaField),
                  const SizedBox(width: 10),
                  Expanded(child: tendenciaField),
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _observacoesPorFundamento[fundamento],
            enabled: !_saving,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Observação do fundamento',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSendToAthleteCard(bool isMobile) {
    return _buildCard(
      padding: EdgeInsets.all(isMobile ? 14 : 16),
      children: [
        SwitchListTile(
          value: _sendToAthlete,
          contentPadding: EdgeInsets.zero,
          activeColor: olympusBlue,
          secondary: const Icon(
            Icons.send_outlined,
            color: olympusBlue,
          ),
          title: const Text(
            'Enviar para atleta',
            style: TextStyle(
              color: olympusBlue,
              fontWeight: FontWeight.w900,
            ),
          ),
          subtitle: const Text(
            'Ao salvar, a atleta receberá uma mensagem com o resumo mensal.',
            style: TextStyle(
              color: olympusMuted,
              fontWeight: FontWeight.w600,
            ),
          ),
          onChanged: _saving
              ? null
              : (value) {
                  setState(() => _sendToAthlete = value);
                },
        ),
        if (_sendToAthlete) ...[
          const SizedBox(height: 12),
          TextField(
            controller: _mensagemAtletaController,
            enabled: !_saving,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Mensagem para atleta',
              hintText:
                  'Ex: Parabéns pela evolução no saque. Para o próximo mês, o foco será recepção e tomada de decisão.',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildFundamentosSection(bool isMobile) {
    return _buildCard(
      padding: EdgeInsets.all(isMobile ? 14 : 16),
      children: [
        Text(
          'Fundamentos',
          style: TextStyle(
            color: olympusBlue,
            fontSize: isMobile ? 15 : 16,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Dê nota de 1 a 5 e registre a tendência de evolução.',
          style: TextStyle(
            color: olympusMuted,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 12),
        ..._fundamentos.map((item) => _buildFundamentoCard(item, isMobile)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = _isMobile(context);

    if (widget.athletes.isEmpty) {
      return Scaffold(
        backgroundColor: olympusBg,
        appBar: AppBar(
          title: const Text('Avaliação completa mensal'),
          backgroundColor: olympusBlue,
          foregroundColor: Colors.white,
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: olympusCard.withOpacity(0.96),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: olympusBorder),
              ),
              child: Text(
                'Nenhum atleta encontrado em ${'Avaliação completa mensal'}.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: olympusBlue,
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: olympusBg,
      appBar: AppBar(
        title: const Text('Avaliação completa mensal'),
        backgroundColor: olympusBlue,
        foregroundColor: Colors.white,
      ),
      body: Stack(
        children: [
          Positioned.fill(child: _buildBackground()),
          SafeArea(
            child: widget.athletes.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'Nenhuma atleta visível para avaliação completa.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  )
                : ListView(
                    padding: EdgeInsets.all(isMobile ? 12 : 16),
                    children: [
                      _buildHeader(isMobile),
                      const SizedBox(height: 14),
                      _buildAthleteSelector(isMobile),
                      const SizedBox(height: 14),
                      _buildSendToAthleteCard(isMobile),
                      const SizedBox(height: 14),
                      _buildSummaryCard(isMobile),
                      const SizedBox(height: 14),
                      _buildFundamentosSection(isMobile),
                      const SizedBox(height: 18),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _saving || !_isLastFourDaysOfMonth
                              ? null
                              : _salvarAvaliacaoCompleta,
                          icon: _saving
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      Colors.white,
                                    ),
                                  ),
                                )
                              : const Icon(Icons.save_outlined),
                          label: Text(
                            _saving
                                ? 'Salvando...'
                                : 'Salvar avaliação completa',
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: olympusBlue,
                            foregroundColor: Colors.white,
                            disabledBackgroundColor:
                                Colors.grey.withOpacity(0.35),
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 28),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
