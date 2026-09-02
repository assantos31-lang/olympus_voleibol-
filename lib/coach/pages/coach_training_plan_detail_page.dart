import 'dart:async';

import 'package:flutter/material.dart';
import '../../theme/olympus_theme.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CoachTrainingPlanDetailPage extends StatefulWidget {
  const CoachTrainingPlanDetailPage({
    super.key,
    required this.treino,
  });

  final Map<String, dynamic> treino;

  @override
  State<CoachTrainingPlanDetailPage> createState() =>
      _CoachTrainingPlanDetailPageState();
}

class _CoachTrainingPlanDetailPageState
    extends State<CoachTrainingPlanDetailPage> {
  final SupabaseClient _supabase = Supabase.instance.client;

  static const Color olympusBg = Color(0xFFF4F7FB);
  static const Color olympusCard = Colors.white;
  static const Color olympusText = Color(0xFF17324D);
  static const Color olympusMuted = Color(0xFF53657B);
  static const Color olympusSubtle = Color(0xFF6A7E94);
  static const Color olympusBorder = Color(0xFFE4EDF5);
  static const Color olympusDanger = Color(0xFFDC2626);
  static const Color olympusSuccess = Color(0xFF16A34A);

  final Map<String, List<String>> _opcoesPorCategoria = const {
    'Fundamentos': [
      'Aquecimento',
      'Saque',
      'Recepção',
      'Toque',
      'Ataque',
      'Bloqueio',
      'Defesa',
      'Levantamento',
      'Passe',
    ],
    'Tático': [
      'Sistema defensivo',
      'Sistema ofensivo',
      'Transição',
      'Cobertura',
      'Posicionamento',
      'Rodízio',
      'Leitura de jogo',
      'Simulação de jogo',
    ],
    'Físico': [
      'Mobilidade',
      'Agilidade',
      'Velocidade',
      'Força',
      'Potência',
      'Resistência',
      'Core',
      'Prevenção',
    ],
  };

  final Map<String, List<String>> _fundamentosPorPosicao = const {
    'Atacantes': [
      'Saque',
      'Recepção',
      'Ataque',
      'Bloqueio',
      'Defesa',
    ],
    'Levantadores(as)': [
      'Saque',
      'Toque',
      'Levantamento',
      'Defesa',
      'Bloqueio',
    ],
    'Líberos': [
      'Recepção',
      'Defesa',
      'Passe',
      'Toque',
    ],
    'Todos': [
      'Aquecimento',
      'Saque',
      'Recepção',
      'Toque',
      'Ataque',
      'Bloqueio',
      'Defesa',
      'Levantamento',
      'Passe',
    ],
  };

  late List<Map<String, dynamic>> _blocos;
  bool _loadingPlan = true;
  RealtimeChannel? _trainingPlanRealtimeChannel;
  Timer? _realtimeReloadTimer;
  bool _editingBlock = false;
  final Map<int, Future<void>> _blockSaveQueues = {};

  String get _eventId => (widget.treino['id'] ?? '').toString();

  @override
  void initState() {
    super.initState();

    _blocos = [];
    _garantirMinimoTresBlocos();

    _carregarPlanejamentoDoSupabase();
    _configurarRealtime();
  }

  @override
  void dispose() {
    _realtimeReloadTimer?.cancel();
    final channel = _trainingPlanRealtimeChannel;
    if (channel != null) {
      _supabase.removeChannel(channel);
    }
    super.dispose();
  }

  void _configurarRealtime() {
    if (_eventId.isEmpty) return;
    final userId = _supabase.auth.currentUser?.id ?? 'anonymous';
    _trainingPlanRealtimeChannel = _supabase
        .channel('training-plan-detail-$userId-$_eventId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'training_plan_blocks',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'event_id',
            value: _eventId,
          ),
          callback: (_) {
            _realtimeReloadTimer?.cancel();
            _realtimeReloadTimer = Timer(
              const Duration(milliseconds: 450),
              () {
                if (mounted && !_editingBlock) {
                  _carregarPlanejamentoDoSupabase();
                }
              },
            );
          },
        )
        .subscribe();
  }

  bool _isMobile(BuildContext context) {
    return MediaQuery.of(context).size.width < 600;
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: olympusDanger,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showSuccess(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: olympusSuccess,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Widget _responsiveActionRow({
    required List<Widget> children,
    double spacing = 10,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final stackVertically = constraints.maxWidth < 360;
        if (stackVertically) {
          return Column(
            children: [
              for (int i = 0; i < children.length; i++) ...[
                SizedBox(width: double.infinity, child: children[i]),
                if (i < children.length - 1) SizedBox(height: spacing),
              ],
            ],
          );
        }

        return Row(
          children: [
            for (int i = 0; i < children.length; i++) ...[
              Expanded(child: children[i]),
              if (i < children.length - 1) SizedBox(width: spacing),
            ],
          ],
        );
      },
    );
  }

  DateTime? _parseHorario(String value) {
    final clean = _normalizarHorario(value);
    final parts = clean.split(':');
    if (parts.length != 2) return null;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return null;
    return DateTime(2000, 1, 1, hour, minute);
  }

  String _formatHorario(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  String _normalizarHorario(dynamic value) {
    final raw = (value ?? '').toString().trim();
    if (raw.isEmpty) return '';

    final parts = raw.split(':');
    if (parts.length >= 2) {
      final h = int.tryParse(parts[0]);
      final m = int.tryParse(parts[1]);

      if (h != null && m != null) {
        return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
      }
    }

    return raw;
  }

  String _getHorarioInicialTreino() {
    return _normalizarHorario(widget.treino['event_time']);
  }

  String _getHorarioFinalTreino() {
    for (final key in const [
      'event_end_time',
      'event_time_end',
      'end_time',
      'event_end_at',
    ]) {
      final raw = widget.treino[key];
      if (raw == null || raw.toString().trim().isEmpty) continue;
      if (key == 'event_end_at') {
        final parsed = DateTime.tryParse(raw.toString())?.toLocal();
        if (parsed != null) return _formatHorario(parsed);
      }
      return _normalizarHorario(raw);
    }
    return '';
  }

  int _duracaoEmMinutos(String inicio, String fim) {
    final inicioParsed = _parseHorario(inicio);
    var fimParsed = _parseHorario(fim);
    if (inicioParsed == null || fimParsed == null) return 0;
    if (fimParsed.isBefore(inicioParsed)) {
      fimParsed = fimParsed.add(const Duration(days: 1));
    }
    return fimParsed.difference(inicioParsed).inMinutes.clamp(0, 1440);
  }

  int get _minutosPlanejados =>
      _blocos.where(_blocoEstaCompleto).fold(0, (total, bloco) {
        return total +
            _duracaoEmMinutos(
              (bloco['inicio'] ?? '').toString(),
              (bloco['fim'] ?? '').toString(),
            );
      });

  int? get _minutosRestantes {
    final fimEvento = _getHorarioFinalTreino();
    if (fimEvento.isEmpty) return null;
    final totalEvento =
        _duracaoEmMinutos(_getHorarioInicialTreino(), fimEvento);
    return (totalEvento - _minutosPlanejados).clamp(0, totalEvento);
  }

  String _formatDuracao(int minutos) {
    final horas = minutos ~/ 60;
    final resto = minutos % 60;
    return '${horas.toString().padLeft(2, '0')}:${resto.toString().padLeft(2, '0')}';
  }

  bool _ultrapassaFimDoEvento(String fimBloco) {
    final fimEvento = _getHorarioFinalTreino();
    if (fimEvento.isEmpty) return false;
    final inicioEvento = _getHorarioInicialTreino();
    return _duracaoEmMinutos(inicioEvento, fimBloco) >
        _duracaoEmMinutos(inicioEvento, fimEvento);
  }

  String _calcularHorarioFimPadrao(String inicio) {
    final parsed = _parseHorario(inicio);
    if (parsed == null) return '';
    return _formatHorario(parsed.add(const Duration(minutes: 10)));
  }

  Map<String, dynamic> _blocoVazioPadrao([String? horarioInicial]) {
    final inicio = horarioInicial ?? _getHorarioInicialTreino();
    return {
      'id': null,
      'categoria': '',
      'tipo': '',
      'inicio': inicio,
      'fim': _calcularHorarioFimPadrao(inicio),
      'observacao': '',
      'posicoes': <String>[],
      'percentual_esforco_fisico': 0,
      'minutos_fisicos': 0,
    };
  }

  void _garantirMinimoTresBlocos() {
    while (_blocos.length < 3) {
      final inicio = _blocos.isEmpty
          ? _getHorarioInicialTreino()
          : _proximoHorarioInicial();
      _blocos.add(_blocoVazioPadrao(inicio));
    }
  }

  void _normalizarSequenciaDosBlocos() {
    if (_blocos.isEmpty) return;
    final duracaoPrimeiro = _duracaoEmMinutos(
      (_blocos.first['inicio'] ?? '').toString(),
      (_blocos.first['fim'] ?? '').toString(),
    );
    final inicioEvento = _getHorarioInicialTreino();
    _blocos.first['inicio'] = inicioEvento;
    final inicioParsed = _parseHorario(inicioEvento);
    if (inicioParsed != null) {
      _blocos.first['fim'] = _formatHorario(
        inicioParsed.add(
          Duration(minutes: duracaoPrimeiro > 0 ? duracaoPrimeiro : 10),
        ),
      );
    }
    _encadearBlocosDepoisDe(0);
  }

  Map<String, dynamic> _mapBlocoFromDb(Map<String, dynamic> row) {
    return {
      'id': row['id'],
      'categoria': (row['category'] ?? '').toString(),
      'tipo': (row['type'] ?? '').toString(),
      'inicio': _normalizarHorario(row['start_time']),
      'fim': _normalizarHorario(row['end_time']),
      'observacao': (row['observation'] ?? '').toString(),
      'posicoes': _parsePosicoes(
        (row['category'] ?? '').toString(),
        (row['type'] ?? '').toString(),
      ).toList(),
      'percentual_esforco_fisico':
          int.tryParse((row['physical_effort_percent'] ?? '0').toString()) ?? 0,
      'minutos_fisicos':
          int.tryParse((row['physical_minutes'] ?? '0').toString()) ?? 0,
    };
  }

  Future<void> _carregarPlanejamentoDoSupabase() async {
    setState(() {
      _loadingPlan = true;
    });

    try {
      final user = _supabase.auth.currentUser;
      if (user == null) {
        throw Exception('Usuário não autenticado.');
      }

      if (_eventId.isEmpty) {
        throw Exception('Evento inválido.');
      }

      final blocosResponse = await _supabase
          .from('training_plan_blocks')
          .select(
              'id, category, type, start_time, end_time, observation, position, physical_effort_percent, physical_minutes')
          .eq('event_id', _eventId)
          .eq('coach_id', user.id)
          .order('position', ascending: true);

      final blocosRows =
          List<Map<String, dynamic>>.from(blocosResponse as List);

      if (!mounted) return;

      setState(() {
        if (blocosRows.isEmpty) {
          _blocos = [];
        } else {
          _blocos = blocosRows.map(_mapBlocoFromDb).toList();
        }

        _normalizarSequenciaDosBlocos();
        _garantirMinimoTresBlocos();

        _loadingPlan = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingPlan = false;
      });
      _showError('Erro ao carregar planejamento: $e');
    }
  }

  bool _blocoEstaCompleto(Map<String, dynamic> bloco) {
    return (bloco['categoria'] ?? '').toString().trim().isNotEmpty &&
        (bloco['tipo'] ?? '').toString().trim().isNotEmpty &&
        ((bloco['posicoes'] as List?) ?? const []).isNotEmpty &&
        (bloco['inicio'] ?? '').toString().trim().isNotEmpty &&
        (bloco['fim'] ?? '').toString().trim().isNotEmpty;
  }

  bool get _podeAdicionarNovoBloco {
    if (_blocos.isEmpty) return true;
    return _blocoEstaCompleto(_blocos.last);
  }

  String _proximoHorarioInicial() {
    if (_blocos.isEmpty) return _getHorarioInicialTreino();
    final ultimoFim = (_blocos.last['fim'] ?? '').toString().trim();
    final parsed = _parseHorario(ultimoFim);
    if (parsed == null) return _getHorarioInicialTreino();
    return _formatHorario(parsed);
  }

  void _encadearBlocosDepoisDe(int index) {
    for (int i = index + 1; i < _blocos.length; i++) {
      final fimAnterior = _normalizarHorario(_blocos[i - 1]['fim']);
      final fimAnteriorParsed = _parseHorario(fimAnterior);
      if (fimAnteriorParsed == null) break;
      final duracaoAtual = _duracaoEmMinutos(
        (_blocos[i]['inicio'] ?? '').toString(),
        (_blocos[i]['fim'] ?? '').toString(),
      );
      _blocos[i]['inicio'] = fimAnterior;
      _blocos[i]['fim'] = _formatHorario(
        fimAnteriorParsed.add(
          Duration(minutes: duracaoAtual > 0 ? duracaoAtual : 10),
        ),
      );
    }
  }

  Future<String?> _selecionarHorario(String valorInicial) async {
    final initialParsed = _parseHorario(valorInicial);
    final picked = await showTimePicker(
      context: context,
      initialTime: initialParsed != null
          ? TimeOfDay(hour: initialParsed.hour, minute: initialParsed.minute)
          : TimeOfDay.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: olympusBlue,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked == null) return null;
    final dt = DateTime(2000, 1, 1, picked.hour, picked.minute);
    return _formatHorario(dt);
  }

  Future<void> _salvarBlocoNoSupabase(int index) async {
    final previous = _blockSaveQueues[index] ?? Future<void>.value();
    final queued = previous.then((_) => _persistirBlocoNoSupabase(index));
    _blockSaveQueues[index] = queued;
    try {
      await queued;
    } finally {
      if (identical(_blockSaveQueues[index], queued)) {
        _blockSaveQueues.remove(index);
      }
    }
  }

  Future<void> _persistirBlocoNoSupabase(int index) async {
    if (index < 0 || index >= _blocos.length) return;
    final user = _supabase.auth.currentUser;
    if (user == null) {
      throw Exception('Usuário não autenticado.');
    }

    if (_eventId.isEmpty) {
      throw Exception('Evento inválido.');
    }

    final bloco = _blocos[index];

    if (!_blocoEstaCompleto(bloco)) {
      return;
    }

    final payload = {
      'event_id': _eventId,
      'coach_id': user.id,
      'category': (bloco['categoria'] ?? '').toString().trim(),
      'type': (bloco['tipo'] ?? '').toString().trim(),
      'start_time': _normalizarHorario(bloco['inicio']),
      'end_time': _normalizarHorario(bloco['fim']),
      'observation': (bloco['observacao'] ?? '').toString().trim(),
      'position': index,
      'physical_effort_percent':
          (bloco['percentual_esforco_fisico'] as num?)?.round() ?? 0,
      'physical_minutes': (bloco['minutos_fisicos'] as num?)?.round() ?? 0,
      'updated_at': DateTime.now().toIso8601String(),
    };

    final blocoId = (bloco['id'] ?? '').toString();

    if (blocoId.isEmpty || blocoId == 'null') {
      Map<String, dynamic> inserted;
      try {
        inserted = await _supabase
            .from('training_plan_blocks')
            .insert(payload)
            .select('id')
            .single();
      } on PostgrestException catch (error) {
        if (error.code != '23505') rethrow;

        final existing = await _supabase
            .from('training_plan_blocks')
            .select('id')
            .eq('event_id', _eventId)
            .eq('coach_id', user.id)
            .eq('position', index)
            .maybeSingle();
        final existingId = (existing?['id'] ?? '').toString();
        if (existingId.isEmpty) rethrow;

        await _supabase
            .from('training_plan_blocks')
            .update(payload)
            .eq('id', existingId);
        inserted = {'id': existingId};
      }

      if (!mounted) return;

      setState(() {
        _blocos[index]['id'] = inserted['id'];
      });
    } else {
      await _supabase
          .from('training_plan_blocks')
          .update(payload)
          .eq('id', blocoId);
    }
  }

  Future<void> _reordenarBlocosNoSupabase() async {
    for (int i = 0; i < _blocos.length; i++) {
      final blocoId = (_blocos[i]['id'] ?? '').toString();
      if (blocoId.isEmpty || blocoId == 'null') continue;

      await _supabase.from('training_plan_blocks').update({
        'position': i,
        'updated_at': DateTime.now().toIso8601String()
      }).eq('id', blocoId);
    }
  }

  Future<void> _removerBlocoDoSupabase(Map<String, dynamic> bloco) async {
    final blocoId = (bloco['id'] ?? '').toString();
    if (blocoId.isEmpty || blocoId == 'null') return;

    await _supabase.from('training_plan_blocks').delete().eq('id', blocoId);
  }

  Future<void> _adicionarBloco() async {
    if (!_podeAdicionarNovoBloco) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Preencha o bloco atual antes de habilitar o próximo.',
          ),
        ),
      );
      return;
    }

    final horarioInicial = _blocos.length == 1 &&
            (_blocos.first['inicio'] ?? '').toString().trim().isEmpty
        ? _getHorarioInicialTreino()
        : _proximoHorarioInicial();

    final novoBloco = {
      'id': null,
      'categoria': '',
      'tipo': '',
      'inicio': horarioInicial,
      'fim': _calcularHorarioFimPadrao(horarioInicial),
      'observacao': '',
      'posicoes': <String>[],
      'percentual_esforco_fisico': 0,
      'minutos_fisicos': 0,
    };

    setState(() {
      _blocos.add(novoBloco);
    });

    await _editarBloco(_blocos.length - 1);
  }

  Map<String, Set<String>> _parseFundamentosSelecionados(String rawValue) {
    final value = rawValue.trim();
    if (value.isEmpty) return <String, Set<String>>{};

    final parsed = <String, Set<String>>{};
    if (value.contains(':')) {
      for (final group in value.split('|')) {
        final separator = group.indexOf(':');
        if (separator <= 0) continue;

        final position = group.substring(0, separator).trim();
        if (!_fundamentosPorPosicao.containsKey(position)) continue;

        final allowed = _fundamentosPorPosicao[position]!.toSet();
        final fundamentals = group
            .substring(separator + 1)
            .split(',')
            .map((item) => item.trim())
            .where((item) => allowed.contains(item))
            .toSet();
        parsed[position] = fundamentals;
      }
    } else {
      final legacyFundamentals = value
          .split(',')
          .map((item) => item.trim())
          .where((item) => _fundamentosPorPosicao['Todos']!.contains(item))
          .toSet();
      if (legacyFundamentals.isNotEmpty) {
        parsed['Todos'] = legacyFundamentals;
      }
    }

    if (parsed.containsKey('Todos')) {
      return {'Todos': parsed['Todos']!};
    }
    return parsed;
  }

  String _serializeFundamentosSelecionados(
    Map<String, Set<String>> selections,
  ) {
    const positionOrder = [
      'Atacantes',
      'Levantadores(as)',
      'Líberos',
      'Todos',
    ];
    final groups = <String>[];

    for (final position in positionOrder) {
      final selected = selections[position];
      if (selected == null || selected.isEmpty) continue;
      final allowed = _fundamentosPorPosicao[position] ?? const <String>[];
      final ordered = allowed.where(selected.contains).toList();
      if (ordered.isNotEmpty) {
        groups.add('$position: ${ordered.join(', ')}');
      }
    }
    return groups.join(' | ');
  }

  Set<String> _parsePosicoes(String categoria, String tipo) {
    if (categoria == 'Fundamentos') {
      return _parseFundamentosSelecionados(tipo).keys.toSet();
    }

    final match = RegExp(r'^Posições \[([^\]]+)\] • ').firstMatch(tipo);
    if (match == null) return <String>{};
    return match
        .group(1)!
        .split(',')
        .map((item) => item.trim())
        .where(_fundamentosPorPosicao.containsKey)
        .toSet();
  }

  String _parseOpcaoTreino(String categoria, String tipo) {
    if (categoria == 'Fundamentos') return tipo;
    final match = RegExp(r'^Posições \[[^\]]+\] • (.+)$').firstMatch(tipo);
    return match?.group(1)?.trim() ?? tipo.trim();
  }

  String _serializeTipoTreino({
    required String categoria,
    required Set<String> posicoes,
    required String opcao,
    required Map<String, Set<String>> fundamentos,
  }) {
    if (categoria == 'Fundamentos') {
      return _serializeFundamentosSelecionados(fundamentos);
    }
    if (posicoes.isEmpty || opcao.trim().isEmpty) return '';

    const ordem = ['Atacantes', 'Levantadores(as)', 'Líberos', 'Todos'];
    final posicoesOrdenadas = ordem.where(posicoes.contains).join(', ');
    return 'Posições [$posicoesOrdenadas] • ${opcao.trim()}';
  }

  Future<void> _editarBloco(int index) async {
    _editingBlock = true;
    final bloco = Map<String, dynamic>.from(_blocos[index]);
    String categoriaSelecionada =
        (bloco['categoria'] ?? '').toString().trim().isEmpty
            ? 'Fundamentos'
            : (bloco['categoria'] ?? 'Fundamentos').toString();
    String tipoSelecionado = (bloco['tipo'] ?? '').toString();
    Map<String, Set<String>> fundamentosSelecionados =
        _parseFundamentosSelecionados(tipoSelecionado);
    Set<String> posicoesSelecionadas = {
      ...((bloco['posicoes'] as List?) ?? const []).map((item) => '$item'),
      ..._parsePosicoes(categoriaSelecionada, tipoSelecionado),
    };
    String opcaoSelecionada =
        _parseOpcaoTreino(categoriaSelecionada, tipoSelecionado);
    int percentualEsforcoFisico =
        int.tryParse((bloco['percentual_esforco_fisico'] ?? '0').toString()) ??
            0;
    if (categoriaSelecionada == 'Físico' && percentualEsforcoFisico == 0) {
      percentualEsforcoFisico = 100;
    }

    String horarioInicio = index == 0
        ? _getHorarioInicialTreino()
        : _normalizarHorario(_blocos[index - 1]['fim']);

    String horarioFim = (bloco['fim'] ?? '').toString().trim().isNotEmpty
        ? _normalizarHorario(bloco['fim'])
        : _calcularHorarioFimPadrao(horarioInicio);

    final observacaoController =
        TextEditingController(text: (bloco['observacao'] ?? '').toString());
    Timer? autoSaveTimer;
    StateSetter? atualizarModal;
    bool salvandoAutomaticamente = false;
    bool salvoAutomaticamente = false;
    String? validationError;

    void sincronizarEAgendarSalvamento() {
      tipoSelecionado = _serializeTipoTreino(
        categoria: categoriaSelecionada,
        posicoes: posicoesSelecionadas,
        opcao: opcaoSelecionada,
        fundamentos: fundamentosSelecionados,
      );

      final currentBlockId = _blocos[index]['id'] ?? bloco['id'];
      final duracaoBloco = _duracaoEmMinutos(horarioInicio, horarioFim);
      final minutosFisicos =
          (duracaoBloco * percentualEsforcoFisico / 100).round();
      setState(() {
        _blocos[index] = {
          'id': currentBlockId,
          'categoria': categoriaSelecionada,
          'tipo': tipoSelecionado,
          'inicio': horarioInicio.trim(),
          'fim': horarioFim.trim(),
          'observacao': observacaoController.text.trim(),
          'posicoes': posicoesSelecionadas.toList(),
          'percentual_esforco_fisico': percentualEsforcoFisico,
          'minutos_fisicos': minutosFisicos,
        };
        _encadearBlocosDepoisDe(index);
      });

      autoSaveTimer?.cancel();
      final inicio = _parseHorario(horarioInicio);
      final fim = _parseHorario(horarioFim);
      if (!_blocoEstaCompleto(_blocos[index]) ||
          inicio == null ||
          fim == null ||
          !fim.isAfter(inicio) ||
          _ultrapassaFimDoEvento(horarioFim)) {
        salvoAutomaticamente = false;
        atualizarModal?.call(() {});
        return;
      }

      salvoAutomaticamente = false;
      validationError = null;
      atualizarModal?.call(() {});
      autoSaveTimer = Timer(const Duration(milliseconds: 600), () async {
        salvandoAutomaticamente = true;
        atualizarModal?.call(() {});
        try {
          await _salvarBlocoNoSupabase(index);
          for (int i = index + 1; i < _blocos.length; i++) {
            if (_blocoEstaCompleto(_blocos[i])) {
              await _salvarBlocoNoSupabase(i);
            }
          }
          salvoAutomaticamente = true;
        } catch (e) {
          validationError = 'Erro ao salvar automaticamente. $e';
          atualizarModal?.call(() {});
        } finally {
          salvandoAutomaticamente = false;
          atualizarModal?.call(() {});
        }
      });
    }

    final salvo = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            atualizarModal = setModalState;
            final opcoesTipos =
                _opcoesPorCategoria[categoriaSelecionada] ?? const <String>[];

            if (horarioFim.trim().isEmpty && horarioInicio.trim().isNotEmpty) {
              horarioFim = _calcularHorarioFimPadrao(horarioInicio);
            }

            Widget buildCategoriaChip(String categoria) {
              final selected = categoriaSelecionada == categoria;
              return ChoiceChip(
                label: Text(categoria),
                selected: selected,
                onSelected: (_) {
                  setModalState(() {
                    final categoriaAnterior = categoriaSelecionada;
                    categoriaSelecionada = categoria;
                    if (categoria == 'Físico') {
                      percentualEsforcoFisico = 100;
                    } else if (categoriaAnterior == 'Físico') {
                      percentualEsforcoFisico = 0;
                    }
                    if (categoria == 'Fundamentos') {
                      opcaoSelecionada = '';
                      fundamentosSelecionados = {
                        for (final posicao in posicoesSelecionadas)
                          posicao:
                              fundamentosSelecionados[posicao] ?? <String>{},
                      };
                    } else {
                      opcaoSelecionada = '';
                    }
                  });
                  sincronizarEAgendarSalvamento();
                },
                selectedColor: const Color(0xFFD4AF37),
                backgroundColor: Colors.white,
                labelStyle: TextStyle(
                  color: selected ? olympusBlue : olympusMuted,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
                side: BorderSide(
                  color: selected ? const Color(0xFFD4AF37) : olympusBorder,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(999),
                ),
              );
            }

            Widget buildTipoChip(String tipo) {
              final selected = opcaoSelecionada == tipo;
              return ChoiceChip(
                label: Text(tipo),
                selected: selected,
                onSelected: (_) {
                  setModalState(() {
                    opcaoSelecionada = tipo;
                  });
                  sincronizarEAgendarSalvamento();
                },
                selectedColor: olympusBlue,
                backgroundColor: Colors.white,
                labelStyle: TextStyle(
                  color: selected ? Colors.white : olympusMuted,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
                side: BorderSide(
                  color: selected ? olympusBlue : olympusBorder,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(999),
                ),
              );
            }

            Widget buildPosicaoChip(String posicao) {
              final selected = posicoesSelecionadas.contains(posicao);
              return FilterChip(
                label: Text(posicao),
                selected: selected,
                onSelected: (shouldSelect) {
                  setModalState(() {
                    if (!shouldSelect) {
                      posicoesSelecionadas.remove(posicao);
                      fundamentosSelecionados.remove(posicao);
                    } else if (posicao == 'Todos') {
                      posicoesSelecionadas = {'Todos'};
                      fundamentosSelecionados = {
                        'Todos': <String>{},
                      };
                    } else {
                      posicoesSelecionadas.remove('Todos');
                      posicoesSelecionadas.add(posicao);
                      fundamentosSelecionados.remove('Todos');
                      if (categoriaSelecionada == 'Fundamentos') {
                        fundamentosSelecionados.putIfAbsent(
                          posicao,
                          () => <String>{},
                        );
                      }
                    }
                  });
                  sincronizarEAgendarSalvamento();
                },
                selectedColor: olympusGold.withOpacity(0.28),
                checkmarkColor: olympusBlue,
                backgroundColor: Colors.white,
                labelStyle: TextStyle(
                  color: olympusBlue,
                  fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
                  fontSize: 12,
                ),
                side: BorderSide(
                  color: selected ? olympusGold : olympusBorder,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(999),
                ),
              );
            }

            Widget buildFundamentosDaPosicao(String posicao) {
              final selected = fundamentosSelecionados[posicao]!;
              final options = _fundamentosPorPosicao[posicao]!;
              return Container(
                width: double.infinity,
                margin: const EdgeInsets.only(top: 10),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF7FAFD),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: olympusBorder),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.sports_volleyball_rounded,
                          color: olympusBlue,
                          size: 18,
                        ),
                        const SizedBox(width: 7),
                        Expanded(
                          child: Text(
                            posicao,
                            style: TextStyle(
                              color: olympusBlue,
                              fontSize: 13,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          tooltip: 'Remover grupo',
                          onPressed: () {
                            setModalState(() {
                              fundamentosSelecionados.remove(posicao);
                              posicoesSelecionadas.remove(posicao);
                            });
                            sincronizarEAgendarSalvamento();
                          },
                          icon: const Icon(
                            Icons.close_rounded,
                            size: 18,
                            color: olympusMuted,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 7,
                      runSpacing: 7,
                      children: options.map((fundamento) {
                        final isSelected = selected.contains(fundamento);
                        return FilterChip(
                          label: Text(fundamento),
                          selected: isSelected,
                          onSelected: (shouldSelect) {
                            setModalState(() {
                              if (shouldSelect) {
                                selected.add(fundamento);
                              } else {
                                selected.remove(fundamento);
                              }
                            });
                            sincronizarEAgendarSalvamento();
                          },
                          selectedColor: olympusBlue,
                          checkmarkColor: Colors.white,
                          labelStyle: TextStyle(
                            color: isSelected ? Colors.white : olympusMuted,
                            fontWeight: FontWeight.w700,
                            fontSize: 11.5,
                          ),
                          side: BorderSide(
                            color: isSelected ? olympusBlue : olympusBorder,
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              );
            }

            Widget buildHorarioBox({
              required String label,
              required String valor,
              required VoidCallback onTap,
              bool enabled = true,
            }) {
              return Expanded(
                child: InkWell(
                  onTap: enabled ? onTap : null,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFD6DEE8)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          label,
                          style: const TextStyle(
                            color: Color(0xFF53657B),
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Icon(
                              Icons.access_time_rounded,
                              size: 16,
                              color: olympusBlue,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              valor.isEmpty ? '--:--' : valor,
                              style: TextStyle(
                                color: olympusBlue,
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }

            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
              ),
              child: Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
                ),
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
                child: SafeArea(
                  top: false,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
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
                          'Bloco ${index + 1}',
                          style: TextStyle(
                            color: olympusBlue,
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Tipo de treino',
                          style: TextStyle(
                            color: olympusBlue,
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            buildCategoriaChip('Fundamentos'),
                            buildCategoriaChip('Tático'),
                            buildCategoriaChip('Físico'),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Posição em quadra *',
                          style: TextStyle(
                            color: olympusBlue,
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Selecione um ou mais grupos. “Todos” substitui os demais.',
                          style: TextStyle(
                            color: olympusMuted,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 9),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _fundamentosPorPosicao.keys
                              .map(buildPosicaoChip)
                              .toList(),
                        ),
                        const SizedBox(height: 14),
                        if (categoriaSelecionada == 'Fundamentos') ...[
                          if (fundamentosSelecionados.isEmpty)
                            Container(
                              width: double.infinity,
                              margin: const EdgeInsets.only(top: 10),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: olympusGold.withOpacity(0.10),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: olympusGold.withOpacity(0.35),
                                ),
                              ),
                              child: Text(
                                'Escolha uma posição para ver os fundamentos disponíveis.',
                                style: TextStyle(
                                  color: olympusBlue,
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ..._fundamentosPorPosicao.keys
                              .where(fundamentosSelecionados.containsKey)
                              .map(buildFundamentosDaPosicao),
                        ] else ...[
                          Text(
                            categoriaSelecionada == 'Tático'
                                ? 'Selecione a opção tática *'
                                : 'Selecione a opção física *',
                            style: TextStyle(
                              color: olympusBlue,
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: opcoesTipos
                                .map((tipo) => buildTipoChip(tipo))
                                .toList(),
                          ),
                        ],
                        const SizedBox(height: 16),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: olympusBlue.withOpacity(0.05),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: olympusBlue.withOpacity(0.14),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.monitor_heart_outlined,
                                    color: olympusBlue,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'Esforço físico do bloco',
                                      style: TextStyle(
                                        color: olympusBlue,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    '$percentualEsforcoFisico%',
                                    style: TextStyle(
                                      color: olympusBlue,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ],
                              ),
                              Slider(
                                value: percentualEsforcoFisico.toDouble(),
                                min: 0,
                                max: 100,
                                divisions: 20,
                                label: '$percentualEsforcoFisico%',
                                activeColor: olympusGold,
                                onChanged: (value) {
                                  setModalState(() {
                                    percentualEsforcoFisico = value.round();
                                  });
                                  sincronizarEAgendarSalvamento();
                                },
                              ),
                              Text(
                                'Equivale a ${(_duracaoEmMinutos(horarioInicio, horarioFim) * percentualEsforcoFisico / 100).round()} min físicos em ${_duracaoEmMinutos(horarioInicio, horarioFim)} min de atividade.',
                                style: const TextStyle(
                                  color: olympusMuted,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            buildHorarioBox(
                              label: 'Horário início',
                              valor: horarioInicio,
                              enabled: false,
                              onTap: () async {
                                final escolhido =
                                    await _selecionarHorario(horarioInicio);
                                if (escolhido != null) {
                                  setModalState(() {
                                    horarioInicio = escolhido;
                                    horarioFim =
                                        _calcularHorarioFimPadrao(escolhido);
                                  });
                                  sincronizarEAgendarSalvamento();
                                }
                              },
                            ),
                            const SizedBox(width: 10),
                            buildHorarioBox(
                              label: 'Horário fim',
                              valor: horarioFim,
                              onTap: () async {
                                final escolhido =
                                    await _selecionarHorario(horarioFim);
                                if (escolhido != null) {
                                  setModalState(() {
                                    horarioFim = escolhido;
                                  });
                                  sincronizarEAgendarSalvamento();
                                }
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: observacaoController,
                          onChanged: (_) => sincronizarEAgendarSalvamento(),
                          maxLines: 3,
                          decoration: const InputDecoration(
                            labelText: 'Observação',
                            hintText: 'Detalhes do bloco',
                          ),
                        ),
                        if (validationError != null) ...[
                          const SizedBox(height: 12),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(11),
                            decoration: BoxDecoration(
                              color: olympusDanger.withOpacity(0.08),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: olympusDanger.withOpacity(0.28),
                              ),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(
                                  Icons.info_outline_rounded,
                                  color: olympusDanger,
                                  size: 18,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    validationError!,
                                    style: const TextStyle(
                                      color: olympusDanger,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: salvandoAutomaticamente
                                ? null
                                : () async {
                                    sincronizarEAgendarSalvamento();
                                    final inicio = _parseHorario(horarioInicio);
                                    final fim = _parseHorario(horarioFim);
                                    if (!_blocoEstaCompleto(_blocos[index])) {
                                      setModalState(() {
                                        validationError = posicoesSelecionadas
                                                .isEmpty
                                            ? 'Selecione ao menos uma posição em quadra.'
                                            : categoriaSelecionada ==
                                                    'Fundamentos'
                                                ? 'Selecione ao menos um fundamento para a posição escolhida.'
                                                : 'Selecione uma atividade para este tipo de treino.';
                                      });
                                      return;
                                    }
                                    if (inicio == null ||
                                        fim == null ||
                                        !fim.isAfter(inicio)) {
                                      setModalState(() {
                                        validationError =
                                            'O horário final precisa ser maior que o horário inicial.';
                                      });
                                      return;
                                    }
                                    if (_ultrapassaFimDoEvento(horarioFim)) {
                                      setModalState(() {
                                        validationError =
                                            'O bloco não pode terminar depois do horário final do evento.';
                                      });
                                      return;
                                    }
                                    autoSaveTimer?.cancel();
                                    setModalState(() {
                                      validationError = null;
                                      salvandoAutomaticamente = true;
                                    });
                                    try {
                                      await _salvarBlocoNoSupabase(index);
                                      for (int i = index + 1;
                                          i < _blocos.length;
                                          i++) {
                                        if (_blocoEstaCompleto(_blocos[i])) {
                                          await _salvarBlocoNoSupabase(i);
                                        }
                                      }
                                      if (context.mounted) {
                                        Navigator.pop(context, true);
                                      }
                                    } catch (e) {
                                      if (context.mounted) {
                                        setModalState(() {
                                          salvandoAutomaticamente = false;
                                          validationError =
                                              'Não foi possível salvar o bloco. $e';
                                        });
                                      }
                                    }
                                  },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: olympusBlue,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                            child: salvandoAutomaticamente
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
                                : Text(
                                    salvoAutomaticamente
                                        ? 'Salvo automaticamente • Concluir'
                                        : 'Concluir bloco',
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    autoSaveTimer?.cancel();
    atualizarModal = null;
    observacaoController.dispose();
    _editingBlock = false;

    if (salvo == true && mounted) {
      _showSuccess('Bloco salvo no Supabase');
    }
  }

  Future<void> _removerBloco(int index) async {
    final blocoRemovido = Map<String, dynamic>.from(_blocos[index]);

    try {
      await _removerBlocoDoSupabase(blocoRemovido);

      setState(() {
        _blocos.removeAt(index);
        _garantirMinimoTresBlocos();
      });

      await _reordenarBlocosNoSupabase();

      if (mounted) {
        _showSuccess('Bloco removido');
      }
    } catch (e) {
      _showError('Erro ao remover bloco: $e');
    }
  }

  Widget _buildBlocoCard(int index, bool isMobile) {
    final bloco = _blocos[index];
    final categoria = (bloco['categoria'] ?? '').toString();
    final tipo = (bloco['tipo'] ?? '').toString();
    final tipoExibicao = _parseOpcaoTreino(categoria, tipo);
    final posicoes = ((bloco['posicoes'] as List?) ?? const [])
        .map((item) => '$item')
        .join(', ');
    final inicio =
        ((bloco['inicio'] ?? '').toString().trim().isEmpty && index == 0)
            ? _getHorarioInicialTreino()
            : _normalizarHorario(bloco['inicio']);
    final fim = (bloco['fim'] ?? '').toString().trim().isEmpty
        ? _calcularHorarioFimPadrao(inicio)
        : _normalizarHorario(bloco['fim']);
    final observacao = (bloco['observacao'] ?? '').toString();
    final percentualFisico =
        int.tryParse((bloco['percentual_esforco_fisico'] ?? '0').toString()) ??
            0;
    final minutosFisicos =
        int.tryParse((bloco['minutos_fisicos'] ?? '0').toString()) ?? 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: EdgeInsets.all(isMobile ? 12 : 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: olympusBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: isMobile ? 34 : 38,
                height: isMobile ? 34 : 38,
                decoration: BoxDecoration(
                  color: olympusBlue.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Center(
                  child: Text(
                    '${index + 1}',
                    style: TextStyle(
                      color: olympusBlue,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  tipoExibicao.isEmpty ? 'Bloco ${index + 1}' : tipoExibicao,
                  style: TextStyle(
                    color: olympusBlue,
                    fontSize: isMobile ? 14 : 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              IconButton(
                onPressed: () => _editarBloco(index),
                icon: const Icon(Icons.edit_outlined),
                color: olympusBlue,
                tooltip: 'Editar',
              ),
              IconButton(
                onPressed: () => _removerBloco(index),
                icon: const Icon(Icons.delete_outline),
                color: olympusDanger,
                tooltip: 'Remover',
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (categoria.trim().isNotEmpty)
            Text(
              categoria,
              style: TextStyle(
                color: olympusMuted,
                fontSize: isMobile ? 11 : 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          if (posicoes.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(
              'Posição: $posicoes',
              style: TextStyle(
                color: olympusMuted,
                fontSize: isMobile ? 11 : 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          const SizedBox(height: 4),
          Text(
            '${inicio.isEmpty ? '--:--' : inicio} às ${fim.isEmpty ? '--:--' : fim}',
            style: TextStyle(
              color: olympusMuted,
              fontSize: isMobile ? 12 : 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (percentualFisico > 0) ...[
            const SizedBox(height: 5),
            Text(
              'Esforço físico: $percentualFisico% • $minutosFisicos min',
              style: TextStyle(
                color: const Color(0xFFF59E0B),
                fontSize: isMobile ? 11 : 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
          if (observacao.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              observacao,
              style: TextStyle(
                color: olympusSubtle,
                fontSize: isMobile ? 12 : 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = _isMobile(context);

    return Scaffold(
      backgroundColor: olympusBg,
      appBar: AppBar(
        title: const Text('Planejamento do treino'),
        backgroundColor: olympusBlue,
        foregroundColor: Colors.white,
      ),
      body: _loadingPlan
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _carregarPlanejamentoDoSupabase,
              child: ListView(
                padding: EdgeInsets.all(isMobile ? 12 : 16),
                children: [
                  Container(
                    padding: EdgeInsets.all(isMobile ? 14 : 16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: olympusBorder),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          (widget.treino['event_name'] ?? 'Treino').toString(),
                          style: TextStyle(
                            color: olympusBlue,
                            fontSize: isMobile ? 18 : 20,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Data: ${(widget.treino['event_date'] ?? '').toString()}',
                          style: TextStyle(
                            color: olympusMuted,
                            fontSize: isMobile ? 12 : 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Horário: ${(widget.treino['event_time'] ?? '').toString()}',
                          style: TextStyle(
                            color: olympusMuted,
                            fontSize: isMobile ? 12 : 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (_getHorarioFinalTreino().isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            'Término: ${_getHorarioFinalTreino()}',
                            style: TextStyle(
                              color: olympusMuted,
                              fontSize: isMobile ? 12 : 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                        if ((widget.treino['gender'] ?? '')
                            .toString()
                            .trim()
                            .isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            'Categoria/Gênero: ${(widget.treino['gender'] ?? '').toString()}',
                            style: TextStyle(
                              color: olympusMuted,
                              fontSize: isMobile ? 12 : 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    padding: EdgeInsets.all(isMobile ? 14 : 16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: olympusBorder),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Planejamento por blocos',
                          style: TextStyle(
                            color: olympusBlue,
                            fontSize: isMobile ? 15 : 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Preencha tipo, posição e atividade. O bloco será salvo automaticamente.',
                          style: TextStyle(
                            color: olympusMuted,
                            fontSize: isMobile ? 12 : 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: olympusBlue.withOpacity(0.06),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: olympusBorder),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Planejado  ${_formatDuracao(_minutosPlanejados)}',
                                  style: TextStyle(
                                    color: olympusBlue,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              Text(
                                _minutosRestantes == null
                                    ? 'Fim do evento não informado'
                                    : 'Falta  ${_formatDuracao(_minutosRestantes!)}',
                                style: TextStyle(
                                  color: _minutosRestantes == 0
                                      ? olympusSuccess
                                      : olympusGold,
                                  fontWeight: FontWeight.w900,
                                  fontSize: isMobile ? 12 : 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        ...List.generate(
                          _blocos.length,
                          (index) => _buildBlocoCard(index, isMobile),
                        ),
                        Align(
                          alignment: Alignment.centerRight,
                          child: ElevatedButton.icon(
                            onPressed: _loadingPlan ? null : _adicionarBloco,
                            icon: const Icon(Icons.add_rounded),
                            label: const Text('Novo bloco'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: olympusBlue,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 18,
                                vertical: 13,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }
}
