import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'coach_championship_athlete_evaluation_page.dart';

class ScoutMetric {
  final String title;
  final String positiveLabel;
  final String negativeLabel;
  final String positiveField;
  final String negativeField;
  final IconData icon;

  const ScoutMetric({
    required this.title,
    required this.positiveLabel,
    required this.negativeLabel,
    required this.positiveField,
    required this.negativeField,
    required this.icon,
  });
}

class CoachChampionshipScoutEvaluationPage extends StatefulWidget {
  const CoachChampionshipScoutEvaluationPage({
    super.key,
    required this.treino,
  });

  final Map<String, dynamic> treino;

  @override
  State<CoachChampionshipScoutEvaluationPage> createState() =>
      _CoachChampionshipScoutEvaluationPageState();
}

class _CoachChampionshipScoutEvaluationPageState
    extends State<CoachChampionshipScoutEvaluationPage> {
  static const Color olympusBlue = Color(0xFF1E3A5F);
  static const Color olympusGold = Color(0xFFD4AF37);
  static const Color olympusLightBlue = Color(0xFF2C5F8D);
  static const Color olympusBg = Color(0xFFF4F7FB);
  static const Color olympusText = Color(0xFF17324D);
  static const Color olympusMuted = Color(0xFF53657B);
  static const Color olympusSubtle = Color(0xFF6A7E94);
  static const Color olympusBorder = Color(0xFFE4EDF5);
  static const Color olympusSuccess = Color(0xFF16A34A);
  static const Color olympusWarning = Color(0xFFF59E0B);
  static const Color olympusDanger = Color(0xFFDC2626);
  static const Color olympusPurple = Color(0xFF7C3AED);
  static const Color whatsappGreen = Color(0xFF25D366);
  static const Color whatsappDarkGreen = Color(0xFF128C7E);

  final SupabaseClient _supabase = Supabase.instance.client;
  bool _loadingAthletes = true;
  bool _saving = false;
  String? _error;
  int _setSelecionado = 1;
  int _quantidadeSets = 5;
  bool _mostrarSomenteComLancamentos = false;

  final TextEditingController _buscaAtletaController = TextEditingController();
  final List<Map<String, dynamic>> _atletas = [];
  final Map<String, Map<String, dynamic>> _scoutPorAtletaSet = {};
  final Map<String, TextEditingController> _observacaoControllers = {};
  final Set<String> _athleteCardsExpanded = {};

  final List<ScoutMetric> _metrics = const [
    ScoutMetric(
      title: 'Saque',
      positiveLabel: 'Ponto',
      negativeLabel: 'Erro',
      positiveField: 'saque_ponto',
      negativeField: 'saque_erro',
      icon: Icons.sports_volleyball_rounded,
    ),
    ScoutMetric(
      title: 'Recepção',
      positiveLabel: 'Boa',
      negativeLabel: 'Erro',
      positiveField: 'recepcao_boa',
      negativeField: 'recepcao_erro',
      icon: Icons.front_hand_rounded,
    ),
    ScoutMetric(
      title: 'Passe',
      positiveLabel: 'Bom',
      negativeLabel: 'Erro',
      positiveField: 'passe_bom',
      negativeField: 'passe_erro',
      icon: Icons.swap_horiz_rounded,
    ),
    ScoutMetric(
      title: 'Ataque',
      positiveLabel: 'Ponto',
      negativeLabel: 'Erro',
      positiveField: 'ataque_ponto',
      negativeField: 'ataque_erro',
      icon: Icons.bolt_rounded,
    ),
    ScoutMetric(
      title: 'Largada de bola',
      positiveLabel: 'Boa',
      negativeLabel: 'Erro',
      positiveField: 'largada_bola_boa',
      negativeField: 'largada_bola_erro',
      icon: Icons.touch_app_rounded,
    ),
    ScoutMetric(
      title: 'Bloqueio',
      positiveLabel: 'Ponto',
      negativeLabel: 'Erro',
      positiveField: 'bloqueio_ponto',
      negativeField: 'bloqueio_erro',
      icon: Icons.block_rounded,
    ),
    ScoutMetric(
      title: 'Defesa',
      positiveLabel: 'Boa',
      negativeLabel: 'Erro',
      positiveField: 'defesa_boa',
      negativeField: 'defesa_erro',
      icon: Icons.shield_rounded,
    ),
    ScoutMetric(
      title: 'Levantamento',
      positiveLabel: 'Bom',
      negativeLabel: 'Erro',
      positiveField: 'levantamento_bom',
      negativeField: 'levantamento_erro',
      icon: Icons.pan_tool_alt_rounded,
    ),
  ];

  String get _eventId => (widget.treino['id'] ?? '').toString();

  @override
  void initState() {
    super.initState();
    _carregarAtletasEScout();
  }

  @override
  void dispose() {
    _buscaAtletaController.dispose();
    for (final controller in _observacaoControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  bool _isMobile(BuildContext context) {
    return MediaQuery.of(context).size.width < 600;
  }

  String _key(String athleteId, int setNumber) => '$athleteId:$setNumber';

  Map<String, dynamic> _emptyScout(String athleteId, int setNumber) {
    final map = <String, dynamic>{
      'event_id': _eventId,
      'athlete_id': athleteId,
      'set_number': setNumber,
      'saque_ponto': 0,
      'saque_erro': 0,
      'recepcao_boa': 0,
      'recepcao_erro': 0,
      'passe_bom': 0,
      'passe_erro': 0,
      'ataque_ponto': 0,
      'ataque_erro': 0,
      'largada_bola_boa': 0,
      'largada_bola_erro': 0,
      'bloqueio_ponto': 0,
      'bloqueio_erro': 0,
      'defesa_boa': 0,
      'defesa_erro': 0,
      'levantamento_bom': 0,
      'levantamento_erro': 0,
      'observacao': '',
    };
    return map;
  }

  Map<String, dynamic> _getScout(String athleteId) {
    final key = _key(athleteId, _setSelecionado);
    _scoutPorAtletaSet.putIfAbsent(
      key,
      () => _emptyScout(athleteId, _setSelecionado),
    );
    return _scoutPorAtletaSet[key]!;
  }

  int _getInt(Map<String, dynamic> scout, String field) {
    final value = scout[field];
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse((value ?? '0').toString()) ?? 0;
  }

  TextEditingController _getObservationController(String athleteId) {
    final key = _key(athleteId, _setSelecionado);
    final scout = _getScout(athleteId);
    return _observacaoControllers.putIfAbsent(
      key,
      () => TextEditingController(
        text: (scout['observacao'] ?? '').toString(),
      ),
    );
  }

  Future<void> _carregarAtletasEScout() async {
    setState(() {
      _loadingAthletes = true;
      _error = null;
    });

    try {
      if (_eventId.isEmpty) {
        throw Exception('Evento inválido.');
      }

      final user = _supabase.auth.currentUser;
      if (user == null) {
        throw Exception('Usuário não autenticado.');
      }

      final response = await _supabase.rpc(
        'get_checked_in_athletes_for_event',
        params: {'p_event_id': _eventId},
      );

      final rpcRows = List<Map<String, dynamic>>.from(response as List);

      final userIds = rpcRows
          .map((row) => (row['user_id'] ?? '').toString())
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList();

      final avatarsByUser = <String, String>{};
      if (userIds.isNotEmpty) {
        final profiles = await _supabase
            .from('profiles')
            .select('id, avatar_url')
            .inFilter('id', userIds);

        for (final profile in profiles) {
          final id = (profile['id'] ?? '').toString();
          if (id.isEmpty) continue;
          avatarsByUser[id] = (profile['avatar_url'] ?? '').toString();
        }
      }

      final atletas = rpcRows
          .where((row) {
            final userId = (row['user_id'] ?? '').toString();
            return userId.isNotEmpty;
          })
          .map<Map<String, dynamic>>(
            (row) => {
              'user_id': row['user_id'],
              'nome': (row['full_name'] ?? 'Atleta').toString(),
              'avatar_url':
                  avatarsByUser[(row['user_id'] ?? '').toString()] ?? '',
            },
          )
          .toList();

      atletas.sort(
        (a, b) => a['nome'].toString().compareTo(b['nome'].toString()),
      );

      final scoutRows = await _supabase
          .from('match_scouts')
          .select()
          .eq('event_id', _eventId)
          .eq('coach_id', user.id);

      final scoutMap = <String, Map<String, dynamic>>{};
      for (final row in scoutRows) {
        final athleteId = (row['athlete_id'] ?? '').toString();
        final setNumber = (row['set_number'] as num?)?.toInt() ?? 1;
        if (athleteId.isEmpty) continue;
        scoutMap[_key(athleteId, setNumber)] = Map<String, dynamic>.from(row);
      }

      if (!mounted) return;
      setState(() {
        _atletas
          ..clear()
          ..addAll(atletas);
        _scoutPorAtletaSet
          ..clear()
          ..addAll(scoutMap);
        _observacaoControllers.clear();
        _loadingAthletes = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingAthletes = false;
        _error = 'Erro ao carregar scout do campeonato: $e';
      });
    }
  }

  Future<void> _salvarScout(String athleteId) async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    final scout = Map<String, dynamic>.from(_getScout(athleteId));
    final key = _key(athleteId, _setSelecionado);
    final controller = _observacaoControllers[key];

    if (controller != null) {
      scout['observacao'] = controller.text.trim();
      _scoutPorAtletaSet[key]!['observacao'] = controller.text.trim();
    }

    scout.remove('id');
    scout['event_id'] = _eventId;
    scout['coach_id'] = user.id;
    scout['athlete_id'] = athleteId;
    scout['set_number'] = _setSelecionado;
    scout['updated_at'] = DateTime.now().toIso8601String();

    await _supabase.from('match_scouts').upsert(
          scout,
          onConflict: 'event_id,coach_id,athlete_id,set_number',
        );
  }

  Future<void> _notificarAtletaSobreFeedback(String athleteId) async {
    try {
      await _supabase.functions.invoke(
        'send-push-notification',
        body: {
          'userId': athleteId,
          'title': 'Novo feedback do treinador',
          'body':
              'Seu treinador registrou um novo feedback. Consulte no aplicativo.',
          'type': 'athlete_coach_feedback',
          'eventId': _eventId,
        },
      );
    } catch (e) {
      debugPrint('Erro ao notificar atleta sobre feedback: $e');
    }
  }

  bool _isNegativeField(String field) {
    return _metrics.any((metric) => metric.negativeField == field);
  }

  ScoutMetric? _metricByField(String field) {
    for (final metric in _metrics) {
      if (metric.positiveField == field || metric.negativeField == field) {
        return metric;
      }
    }
    return null;
  }

  Future<String?> _selecionarObservacaoRapidaErro(ScoutMetric metric) async {
    const motivos = [
      'Rede',
      'Fora',
      'Comunicação',
      'Posicionamento',
      'Tempo de bola',
      'Decisão precipitada',
      'Desatenção',
      'Técnica',
    ];

    return showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 20),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 44,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.black12,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Motivo do erro em ${metric.title}',
                  style: const TextStyle(
                    color: olympusBlue,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Opcional: toque em um motivo para registrar na observação do atleta.',
                  style: TextStyle(
                    color: olympusMuted,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: motivos
                      .map(
                        (motivo) => ActionChip(
                          label: Text(motivo),
                          onPressed: () => Navigator.pop(context, motivo),
                          backgroundColor: olympusBg,
                          labelStyle: const TextStyle(
                            color: olympusBlue,
                            fontWeight: FontWeight.w800,
                          ),
                          side: const BorderSide(color: olympusBorder),
                        ),
                      )
                      .toList(),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: () => Navigator.pop(context, null),
                    child: const Text('Pular observação'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _adicionarObservacaoDeErro({
    required String athleteId,
    required ScoutMetric metric,
    required String motivo,
  }) {
    final controller = _getObservationController(athleteId);
    final atual = controller.text.trim();
    final prefix = 'Set $_setSelecionado • ${metric.title}: $motivo';
    controller.text = atual.isEmpty ? prefix : '$atual\n$prefix';

    final key = _key(athleteId, _setSelecionado);
    _scoutPorAtletaSet[key]!['observacao'] = controller.text.trim();
  }

  Future<void> _alterarContador(
    String athleteId,
    String field,
    int delta,
  ) async {
    final scout = _getScout(athleteId);
    final atual = _getInt(scout, field);
    final novo = (atual + delta).clamp(0, 9999);
    final metric = _metricByField(field);

    String? motivoErro;
    if (delta > 0 && metric != null && _isNegativeField(field)) {
      motivoErro = await _selecionarObservacaoRapidaErro(metric);
      if (!mounted) return;
    }

    setState(() {
      scout[field] = novo;
      if (motivoErro != null &&
          motivoErro.trim().isNotEmpty &&
          metric != null) {
        _adicionarObservacaoDeErro(
          athleteId: athleteId,
          metric: metric,
          motivo: motivoErro.trim(),
        );
      }
    });

    try {
      setState(() {
        _saving = true;
      });
      await _salvarScout(athleteId);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao salvar scout: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  Future<void> _salvarObservacao(String athleteId) async {
    try {
      setState(() {
        _saving = true;
      });
      await _salvarScout(athleteId);
      await _notificarAtletaSobreFeedback(athleteId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Observação salva')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao salvar observação: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  int _totalPositivo(Map<String, dynamic> scout) {
    return _metrics.fold<int>(
      0,
      (sum, metric) => sum + _getInt(scout, metric.positiveField),
    );
  }

  int _totalErro(Map<String, dynamic> scout) {
    return _metrics.fold<int>(
      0,
      (sum, metric) => sum + _getInt(scout, metric.negativeField),
    );
  }

  int _totalGeralDoSet({required bool positivos}) {
    var total = 0;
    for (final atleta in _atletas) {
      final athleteId = (atleta['user_id'] ?? '').toString();
      if (athleteId.isEmpty) continue;
      final scout = _getScout(athleteId);
      total += positivos ? _totalPositivo(scout) : _totalErro(scout);
    }
    return total;
  }

  int _totalGeralTodosSets({required bool positivos}) {
    var total = 0;
    for (final atleta in _atletas) {
      final athleteId = (atleta['user_id'] ?? '').toString();
      if (athleteId.isEmpty) continue;
      for (var setNumber = 1; setNumber <= _quantidadeSets; setNumber++) {
        final scout = _scoutPorAtletaSet[_key(athleteId, setNumber)] ??
            _emptyScout(athleteId, setNumber);
        total += positivos ? _totalPositivo(scout) : _totalErro(scout);
      }
    }
    return total;
  }

  int _totalCampoTodosSets(String field) {
    var total = 0;
    for (final atleta in _atletas) {
      final athleteId = (atleta['user_id'] ?? '').toString();
      if (athleteId.isEmpty) continue;
      for (var setNumber = 1; setNumber <= _quantidadeSets; setNumber++) {
        final scout = _scoutPorAtletaSet[_key(athleteId, setNumber)] ??
            _emptyScout(athleteId, setNumber);
        total += _getInt(scout, field);
      }
    }
    return total;
  }

  int _setComLancamentos(int setNumber) {
    var total = 0;
    for (final atleta in _atletas) {
      final athleteId = (atleta['user_id'] ?? '').toString();
      if (athleteId.isEmpty) continue;
      final scout = _scoutPorAtletaSet[_key(athleteId, setNumber)] ??
          _emptyScout(athleteId, setNumber);
      total += _totalPositivo(scout) + _totalErro(scout);
    }
    return total;
  }

  List<Map<String, dynamic>> _rankingAtletasTodosSets(
      {required bool porErros}) {
    final ranking = _atletas
        .map((atleta) {
          final athleteId = (atleta['user_id'] ?? '').toString();
          var positivos = 0;
          var erros = 0;
          for (var setNumber = 1; setNumber <= _quantidadeSets; setNumber++) {
            final scout = _scoutPorAtletaSet[_key(athleteId, setNumber)] ??
                _emptyScout(athleteId, setNumber);
            positivos += _totalPositivo(scout);
            erros += _totalErro(scout);
          }
          return {
            ...atleta,
            'positivos': positivos,
            'erros': erros,
            'total': porErros ? erros : positivos,
          };
        })
        .where((item) => (item['total'] as int) > 0)
        .toList();

    ranking.sort((a, b) => (b['total'] as int).compareTo(a['total'] as int));
    return ranking.take(5).toList();
  }

  int _pontuacaoAutomatica(Map<String, dynamic> scout) {
    final positivos = _totalPositivo(scout);
    final erros = _totalErro(scout);
    final total = positivos + erros;
    if (total == 0) return 0;
    final base = ((positivos / total) * 10).round();
    final bonusVolume = positivos >= 10 ? 1 : 0;
    final penalidadeErro = erros >= 8 ? 1 : 0;
    return (base + bonusVolume - penalidadeErro).clamp(0, 10);
  }

  String _conceitoAutomatico(int nota) {
    if (nota >= 9) return 'Excelente';
    if (nota >= 7) return 'Bom';
    if (nota >= 5) return 'Regular';
    if (nota > 0) return 'Atenção';
    return 'Sem nota';
  }

  Map<String, dynamic>? _mvpDoJogo() {
    Map<String, dynamic>? best;
    var bestScore = -999999;

    for (final atleta in _atletas) {
      final athleteId = (atleta['user_id'] ?? '').toString();
      if (athleteId.isEmpty) continue;

      var positivos = 0;
      var erros = 0;
      for (var setNumber = 1; setNumber <= _quantidadeSets; setNumber++) {
        final scout = _scoutPorAtletaSet[_key(athleteId, setNumber)] ??
            _emptyScout(athleteId, setNumber);
        positivos += _totalPositivo(scout);
        erros += _totalErro(scout);
      }

      final score = (positivos * 2) - erros;
      if (positivos + erros > 0 && score > bestScore) {
        bestScore = score;
        best = {
          ...atleta,
          'positivos': positivos,
          'erros': erros,
          'score': score,
        };
      }
    }

    return best;
  }

  Map<String, dynamic>? _atletaMaisRegular() {
    Map<String, dynamic>? best;
    var bestRate = -1.0;

    for (final atleta in _atletas) {
      final athleteId = (atleta['user_id'] ?? '').toString();
      if (athleteId.isEmpty) continue;

      var positivos = 0;
      var erros = 0;
      for (var setNumber = 1; setNumber <= _quantidadeSets; setNumber++) {
        final scout = _scoutPorAtletaSet[_key(athleteId, setNumber)] ??
            _emptyScout(athleteId, setNumber);
        positivos += _totalPositivo(scout);
        erros += _totalErro(scout);
      }

      final total = positivos + erros;
      if (total < 3) continue;
      final rate = positivos / total;
      if (rate > bestRate) {
        bestRate = rate;
        best = {
          ...atleta,
          'positivos': positivos,
          'erros': erros,
          'aproveitamento': (rate * 100).round(),
        };
      }
    }

    return best;
  }

  ScoutMetric? _fundamentoMaisCritico() {
    ScoutMetric? worst;
    var worstErrors = 0;

    for (final metric in _metrics) {
      final erros = _totalCampoTodosSets(metric.negativeField);
      if (erros > worstErrors) {
        worstErrors = erros;
        worst = metric;
      }
    }

    return worst;
  }

  int _setComMaisErros() {
    var selectedSet = 1;
    var maxErrors = -1;

    for (var setNumber = 1; setNumber <= _quantidadeSets; setNumber++) {
      var erros = 0;
      for (final atleta in _atletas) {
        final athleteId = (atleta['user_id'] ?? '').toString();
        if (athleteId.isEmpty) continue;
        final scout = _scoutPorAtletaSet[_key(athleteId, setNumber)] ??
            _emptyScout(athleteId, setNumber);
        erros += _totalErro(scout);
      }

      if (erros > maxErrors) {
        maxErrors = erros;
        selectedSet = setNumber;
      }
    }

    return selectedSet;
  }

  Map<String, int> _totaisAtletaTodosSets(String athleteId) {
    var positivos = 0;
    var erros = 0;
    for (var setNumber = 1; setNumber <= _quantidadeSets; setNumber++) {
      final scout = _scoutPorAtletaSet[_key(athleteId, setNumber)] ??
          _emptyScout(athleteId, setNumber);
      positivos += _totalPositivo(scout);
      erros += _totalErro(scout);
    }
    return {'positivos': positivos, 'erros': erros};
  }

  Map<String, dynamic> _insightInteligente() {
    final critico = _fundamentoMaisCritico();
    final setCritico = _setComMaisErros();

    if (critico == null) {
      return {
        'title': 'Jogo sob controle',
        'message': 'Nenhum fundamento crítico identificado até agora.',
        'icon': Icons.verified_rounded,
        'color': olympusSuccess,
      };
    }

    final errosCritico = _totalCampoTodosSets(critico.negativeField);
    return {
      'title': '${critico.title} merece atenção',
      'message':
          '$errosCritico erros acumulados. Set mais crítico: Set $setCritico.',
      'icon': Icons.warning_amber_rounded,
      'color': olympusDanger,
    };
  }

  Future<void> _abrirRelatorioAtleta(Map<String, dynamic> atleta) async {
    final athleteId = (atleta['user_id'] ?? '').toString();
    final nome = (atleta['nome'] ?? 'Atleta').toString();
    if (athleteId.isEmpty) return;

    final totais = _totaisAtletaTodosSets(athleteId);
    final total = totais['positivos']! + totais['erros']!;
    final aproveitamento =
        total == 0 ? 0 : ((totais['positivos']! / total) * 100).round();

    await showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 560,
            maxHeight: MediaQuery.of(context).size.height * 0.86,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: Column(
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [olympusBlue, olympusLightBlue],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        nome,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Relatório individual • $aproveitamento% aproveitamento',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.82),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: Container(
                    color: olympusBg,
                    child: ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: _buildReportStatCard(
                                label: 'Ações',
                                value: totais['positivos']!,
                                icon: Icons.check_circle_rounded,
                                color: olympusSuccess,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _buildReportStatCard(
                                label: 'Erros',
                                value: totais['erros']!,
                                icon: Icons.cancel_rounded,
                                color: olympusDanger,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _buildReportStatCard(
                                label: 'Nota',
                                value: _pontuacaoAutomatica(
                                  _scoutPorAtletaSet[_key(
                                        athleteId,
                                        _setSelecionado,
                                      )] ??
                                      _emptyScout(athleteId, _setSelecionado),
                                ),
                                icon: Icons.grade_rounded,
                                color: olympusGold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        ...List.generate(_quantidadeSets, (index) {
                          final setNumber = index + 1;
                          final scout =
                              _scoutPorAtletaSet[_key(athleteId, setNumber)] ??
                                  _emptyScout(athleteId, setNumber);
                          final positivos = _totalPositivo(scout);
                          final erros = _totalErro(scout);
                          final obs = (scout['observacao'] ?? '').toString();

                          return Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: olympusBorder),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Set $setNumber • +$positivos ações • $erros erros',
                                  style: const TextStyle(
                                    color: olympusBlue,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                ..._metrics.map((metric) {
                                  final pos =
                                      _getInt(scout, metric.positiveField);
                                  final neg =
                                      _getInt(scout, metric.negativeField);
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 4),
                                    child: Text(
                                      '${metric.title}: +$pos / $neg erros',
                                      style: const TextStyle(
                                        color: olympusMuted,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  );
                                }),
                                if (obs.trim().isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  Text(
                                    obs,
                                    style: const TextStyle(
                                      color: olympusSubtle,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(14),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: olympusBlue,
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('Fechar'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _abrirAvaliacaoAtletas() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CoachChampionshipAthleteEvaluationPage(
          treino: widget.treino,
          quantidadeSets: _quantidadeSets,
        ),
      ),
    );

    if (!mounted) return;
    await _carregarAtletasEScout();
  }

  Future<void> _selecionarQuantidadeSets() async {
    var temp = _quantidadeSets;
    final result = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 20),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 44,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.black12,
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Quantidade de sets',
                      style: TextStyle(
                        color: olympusBlue,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Escolha quantos sets este campeonato terá na avaliação.',
                      style: TextStyle(
                        color: olympusMuted,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: List.generate(5, (index) {
                        final value = index + 1;
                        final selected = temp == value;
                        return ChoiceChip(
                          label: Text('$value set${value > 1 ? 's' : ''}'),
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
                          onSelected: (_) => setModalState(() => temp = value),
                        );
                      }),
                    ),
                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () => Navigator.pop(context, temp),
                        icon: const Icon(Icons.check_rounded),
                        label: const Text('Aplicar sets'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: olympusBlue,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (result == null || !mounted) return;
    setState(() {
      _quantidadeSets = result;
      if (_setSelecionado > _quantidadeSets) {
        _setSelecionado = _quantidadeSets;
      }
    });
  }

  List<Map<String, dynamic>> _getAtletasFiltrados() {
    final busca = _buscaAtletaController.text.trim().toLowerCase();

    return _atletas.where((atleta) {
      final athleteId = (atleta['user_id'] ?? '').toString();
      final nome = (atleta['nome'] ?? '').toString().toLowerCase();
      final scout = _getScout(athleteId);
      final temLancamentos = _totalPositivo(scout) + _totalErro(scout) > 0;

      if (_mostrarSomenteComLancamentos && !temLancamentos) return false;
      if (busca.isNotEmpty && !nome.contains(busca)) return false;

      return true;
    }).toList();
  }

  int _totalCampoDoSet(String field) {
    var total = 0;
    for (final atleta in _atletas) {
      final athleteId = (atleta['user_id'] ?? '').toString();
      if (athleteId.isEmpty) continue;
      total += _getInt(_getScout(athleteId), field);
    }
    return total;
  }

  List<Map<String, dynamic>> _rankingAtletas({required bool porErros}) {
    final ranking = _atletas
        .map((atleta) {
          final athleteId = (atleta['user_id'] ?? '').toString();
          final scout = _getScout(athleteId);
          final positivos = _totalPositivo(scout);
          final erros = _totalErro(scout);
          return {
            ...atleta,
            'positivos': positivos,
            'erros': erros,
            'total': porErros ? erros : positivos,
          };
        })
        .where((item) => (item['total'] as int) > 0)
        .toList();

    ranking.sort((a, b) => (b['total'] as int).compareTo(a['total'] as int));
    return ranking.take(5).toList();
  }

  String _relatorioTexto() {
    final nomeEvento = (widget.treino['event_name'] ?? 'Campeonato').toString();
    final data = (widget.treino['event_date'] ?? '').toString();
    final hora = (widget.treino['event_time'] ?? '').toString();
    final positivosSet = _totalGeralDoSet(positivos: true);
    final errosSet = _totalGeralDoSet(positivos: false);
    final positivosTotal = _totalGeralTodosSets(positivos: true);
    final errosTotal = _totalGeralTodosSets(positivos: false);
    final total = positivosTotal + errosTotal;
    final aproveitamento =
        total == 0 ? 0 : ((positivosTotal / total) * 100).round();
    final critico = _fundamentoMaisCritico();
    final setCritico = _setComMaisErros();
    final mvp = _mvpDoJogo();
    final regular = _atletaMaisRegular();
    final destaques = _rankingAtletasTodosSets(porErros: false);
    final atencao = _rankingAtletasTodosSets(porErros: true);

    final buffer = StringBuffer();

    buffer.writeln('🏆 *Scout do Campeonato*');
    buffer.writeln('*$nomeEvento*');
    if (data.isNotEmpty || hora.isNotEmpty) buffer.writeln('$data • $hora');
    buffer.writeln('');
    buffer.writeln('📊 *Resumo geral*');
    buffer.writeln('✅ Ações positivas: $positivosTotal');
    buffer.writeln('❌ Erros: $errosTotal');
    buffer.writeln('🎯 Aproveitamento: $aproveitamento%');
    buffer.writeln('');
    buffer.writeln('📌 *Set selecionado: $_setSelecionado*');
    buffer.writeln('✅ Ações: $positivosSet');
    buffer.writeln('❌ Erros: $errosSet');

    if (mvp != null) {
      buffer.writeln('');
      buffer.writeln(
        '🏅 *MVP:* ${mvp['nome']} (+${mvp['positivos']} / ${mvp['erros']} erros)',
      );
    }

    if (regular != null) {
      buffer.writeln(
        '🛡️ *Mais regular:* ${regular['nome']} • ${regular['aproveitamento']}%',
      );
    }

    if (critico != null) {
      final errosCritico = _totalCampoTodosSets(critico.negativeField);
      buffer.writeln(
        '⚠️ *Fundamento crítico:* ${critico.title} • $errosCritico erros',
      );
      buffer.writeln('🔥 *Set mais crítico:* Set $setCritico');
    }

    if (destaques.isNotEmpty) {
      buffer.writeln('');
      buffer.writeln('🚀 *Top ações positivas*');
      for (var i = 0; i < destaques.take(3).length; i++) {
        buffer.writeln(
          '${i + 1}. ${destaques[i]['nome']} • ${destaques[i]['positivos']} ações',
        );
      }
    }

    if (atencao.isNotEmpty) {
      buffer.writeln('');
      buffer.writeln('⚠️ *Pontos de atenção*');
      for (var i = 0; i < atencao.take(3).length; i++) {
        buffer.writeln(
          '${i + 1}. ${atencao[i]['nome']} • ${atencao[i]['erros']} erros',
        );
      }
    }

    buffer.writeln('');
    buffer.writeln('📋 *Fundamentos*');
    for (final metric in _metrics) {
      final pos = _totalCampoTodosSets(metric.positiveField);
      final neg = _totalCampoTodosSets(metric.negativeField);
      buffer.writeln('• ${metric.title}: +$pos / $neg erros');
    }

    return buffer.toString().trim();
  }

  Future<void> _copiarRelatorio() async {
    final texto = _relatorioTexto();
    await Clipboard.setData(ClipboardData(text: texto));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Resumo copiado para enviar no WhatsApp')),
    );
  }

  Future<void> _abrirRelatorio() async {
    final texto = _relatorioTexto();
    final positivosTotal = _totalGeralTodosSets(positivos: true);
    final errosTotal = _totalGeralTodosSets(positivos: false);
    final aproveitamento = positivosTotal + errosTotal == 0
        ? 0
        : ((positivosTotal / (positivosTotal + errosTotal)) * 100).round();

    await showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 560,
            maxHeight: MediaQuery.of(context).size.height * 0.86,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFF1E3A5F), Color(0xFF2C5F8D)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: olympusGold.withOpacity(0.20),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                  color: olympusGold.withOpacity(0.35)),
                            ),
                            child: const Icon(Icons.emoji_events_rounded,
                                color: olympusGold),
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Text(
                              'Relatório do campeonato',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(Icons.close_rounded),
                            color: Colors.white,
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: _buildReportStatCard(
                              label: 'Ações',
                              value: positivosTotal,
                              icon: Icons.check_circle_rounded,
                              color: olympusSuccess,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _buildReportStatCard(
                              label: 'Erros',
                              value: errosTotal,
                              icon: Icons.cancel_rounded,
                              color: olympusDanger,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _buildReportStatCard(
                              label: 'Aproveit.',
                              value: aproveitamento,
                              suffix: '%',
                              icon: Icons.insights_rounded,
                              color: olympusGold,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: Container(
                    color: olympusBg,
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: olympusBorder),
                        ),
                        child: SelectableText(
                          texto,
                          style: const TextStyle(
                            color: olympusText,
                            fontSize: 13,
                            height: 1.35,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  color: Colors.white,
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(context),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: olympusBlue,
                            side: const BorderSide(color: olympusBorder),
                            padding: const EdgeInsets.symmetric(vertical: 13),
                          ),
                          child: const Text('Fechar'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () async {
                            await Clipboard.setData(ClipboardData(text: texto));
                            if (context.mounted) Navigator.pop(context);
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text('Relatório copiado')),
                              );
                            }
                          },
                          icon: const Icon(Icons.copy_rounded, size: 16),
                          label: const Text('Copiar'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: olympusPurple,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 13),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGlassPanel({
    required Widget child,
    EdgeInsetsGeometry? padding,
    BorderRadius? borderRadius,
    Color? tint,
    double blur = 18,
    bool elevated = true,
  }) {
    final radius = borderRadius ?? BorderRadius.circular(24);

    return ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: tint ?? Colors.white.withOpacity(0.72),
            borderRadius: radius,
            border: Border.all(
              color: Colors.white.withOpacity(0.58),
              width: 1.1,
            ),
            boxShadow: elevated
                ? [
                    BoxShadow(
                      color: olympusBlue.withOpacity(0.08),
                      blurRadius: 24,
                      offset: const Offset(0, 12),
                    ),
                  ]
                : null,
          ),
          child: child,
        ),
      ),
    );
  }

  Widget _buildWhatsappIcon({double size = 18}) {
    return Stack(
      alignment: Alignment.center,
      children: [
        Icon(
          Icons.chat_bubble_rounded,
          size: size + 4,
          color: Colors.white,
        ),
        Positioned(
          top: size * 0.22,
          child: Icon(
            Icons.phone_rounded,
            size: size * 0.58,
            color: whatsappGreen,
          ),
        ),
      ],
    );
  }

  Widget _buildReportStatCard({
    required String label,
    required int value,
    required IconData icon,
    required Color color,
    String suffix = '',
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(height: 6),
          Text(
            '$value$suffix',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.w900,
            ),
          ),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white.withOpacity(0.78),
              fontSize: 10,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDashboardTecnico(bool isMobile) {
    final mvp = _mvpDoJogo();
    final regular = _atletaMaisRegular();
    final critico = _fundamentoMaisCritico();
    final setCritico = _setComMaisErros();
    final errosCritico =
        critico == null ? 0 : _totalCampoTodosSets(critico.negativeField);

    Widget item({
      required IconData icon,
      required String label,
      required String value,
      required Color color,
    }) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.18)),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: color,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    value,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: olympusBlue,
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final cards = [
      item(
        icon: Icons.emoji_events_rounded,
        label: 'MVP do jogo',
        value: mvp == null
            ? 'Sem dados'
            : '${mvp['nome']} • +${mvp['positivos']} / ${mvp['erros']} erros',
        color: olympusGold,
      ),
      item(
        icon: Icons.verified_rounded,
        label: 'Mais regular',
        value: regular == null
            ? 'Sem dados'
            : '${regular['nome']} • ${regular['aproveitamento']}%',
        color: olympusSuccess,
      ),
      item(
        icon: Icons.warning_amber_rounded,
        label: 'Fundamento crítico',
        value: critico == null
            ? 'Sem erros'
            : '${critico.title} • $errosCritico erros',
        color: olympusDanger,
      ),
      item(
        icon: Icons.stacked_line_chart_rounded,
        label: 'Set mais crítico',
        value:
            'Set $setCritico • ${_setComLancamentos(setCritico)} lançamentos',
        color: olympusPurple,
      ),
    ];

    return Container(
      padding: EdgeInsets.all(isMobile ? 12 : 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: olympusBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Dashboard do técnico',
            style: TextStyle(
              color: olympusBlue,
              fontSize: 15,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 10),
          if (isMobile)
            Column(
              children: [
                for (int i = 0; i < cards.length; i++) ...[
                  SizedBox(width: double.infinity, child: cards[i]),
                  if (i < cards.length - 1) const SizedBox(height: 8),
                ],
              ],
            )
          else
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: cards
                  .map((card) => SizedBox(width: 250, child: card))
                  .toList(),
            ),
        ],
      ),
    );
  }

  Widget _buildChartBar({
    required String label,
    required int value,
    required int maxValue,
    required Color color,
    required String trailing,
    IconData? icon,
    double height = 12,
  }) {
    final safeMax = maxValue <= 0 ? 1 : maxValue;
    final factor = (value / safeMax).clamp(0.0, 1.0).toDouble();

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Icon(icon, color: color, size: 16),
                const SizedBox(width: 6),
              ],
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: olympusBlue,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Text(
                trailing,
                style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: Container(
              height: height,
              width: double.infinity,
              color: color.withOpacity(0.10),
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: factor,
                child: Container(
                  height: height,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVerticalBar({
    required int value,
    required double height,
    required Color color,
    required Color gradientEnd,
    required double width,
  }) {
    final resolvedHeight =
        value == 0 ? 6.0 : height.clamp(14.0, 150.0).toDouble();

    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.bottomCenter,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Text(
            '$value',
            style: TextStyle(
              color: color,
              fontSize: 9.5,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 3),
          AnimatedContainer(
            duration: const Duration(milliseconds: 320),
            curve: Curves.easeOutCubic,
            width: width,
            height: resolvedHeight,
            decoration: BoxDecoration(
              gradient: value == 0
                  ? null
                  : LinearGradient(
                      colors: [color, gradientEnd],
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                    ),
              color: value == 0 ? color.withOpacity(0.16) : null,
              borderRadius: BorderRadius.circular(999),
              boxShadow: value == 0
                  ? []
                  : [
                      BoxShadow(
                        color: color.withOpacity(0.20),
                        blurRadius: 7,
                        offset: const Offset(0, 4),
                      ),
                    ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChartLegendItem({
    required Color color,
    required String label,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(999),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(
            color: olympusMuted,
            fontSize: 11,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }

  Widget _buildComparativoSets(bool isMobile) {
    final dadosSets = <Map<String, int>>[];
    var maxValue = 1;

    for (var setNumber = 1; setNumber <= _quantidadeSets; setNumber++) {
      var positivos = 0;
      var erros = 0;

      for (final atleta in _atletas) {
        final athleteId = (atleta['user_id'] ?? '').toString();
        if (athleteId.isEmpty) continue;

        final scout = _scoutPorAtletaSet[_key(athleteId, setNumber)] ??
            _emptyScout(athleteId, setNumber);

        positivos += _totalPositivo(scout);
        erros += _totalErro(scout);
      }

      final total = positivos + erros;
      if (positivos > maxValue) maxValue = positivos;
      if (erros > maxValue) maxValue = erros;

      dadosSets.add({
        'set': setNumber,
        'positivos': positivos,
        'erros': erros,
        'total': total,
        'aproveitamento': total == 0 ? 0 : ((positivos / total) * 100).round(),
      });
    }

    return Container(
      padding: EdgeInsets.all(isMobile ? 16 : 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: olympusBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.045),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [olympusBlue, olympusLightBlue],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.bar_chart_rounded,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Comparativo por set',
                      style: TextStyle(
                        color: olympusBlue,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Ações positivas, erros e aproveitamento por set',
                      style: TextStyle(
                        color: olympusMuted,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              _buildChartLegendItem(color: olympusSuccess, label: 'Ações'),
              _buildChartLegendItem(color: olympusDanger, label: 'Erros'),
              _buildChartLegendItem(
                  color: olympusGold, label: 'Aproveitamento'),
            ],
          ),
          const SizedBox(height: 18),
          SizedBox(
            height: isMobile ? 270 : 300,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final chartHeight = constraints.maxHeight - 112;

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: dadosSets.map((data) {
                    final setNumber = data['set'] ?? 0;
                    final positivos = data['positivos'] ?? 0;
                    final erros = data['erros'] ?? 0;
                    final aproveitamento = data['aproveitamento'] ?? 0;
                    final selected = setNumber == _setSelecionado;

                    final positiveHeight = maxValue <= 0
                        ? 0.0
                        : (positivos / maxValue) * chartHeight;
                    final errorHeight =
                        maxValue <= 0 ? 0.0 : (erros / maxValue) * chartHeight;

                    return Expanded(
                      child: GestureDetector(
                        onTap: () {
                          setState(() {
                            _setSelecionado = setNumber;
                          });
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 220),
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          padding: const EdgeInsets.fromLTRB(4, 6, 4, 0),
                          decoration: BoxDecoration(
                            color: selected
                                ? olympusBlue.withOpacity(0.06)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: selected
                                  ? olympusBlue.withOpacity(0.16)
                                  : Colors.transparent,
                            ),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Text(
                                '$aproveitamento%',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: selected ? olympusGold : olympusMuted,
                                  fontSize: isMobile ? 10 : 11,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Expanded(
                                child: Align(
                                  alignment: Alignment.bottomCenter,
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      _buildVerticalBar(
                                        value: positivos,
                                        height: positiveHeight,
                                        color: olympusSuccess,
                                        gradientEnd: const Color(0xFF4ADE80),
                                        width: isMobile ? 18 : 24,
                                      ),
                                      SizedBox(width: isMobile ? 5 : 7),
                                      _buildVerticalBar(
                                        value: erros,
                                        height: errorHeight,
                                        color: olympusDanger,
                                        gradientEnd: const Color(0xFFF87171),
                                        width: isMobile ? 18 : 24,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                'Set $setNumber',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: selected ? olympusBlue : olympusMuted,
                                  fontSize: isMobile ? 9.5 : 11,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '+$positivos / $erros',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: olympusSubtle,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFerramentasScout(bool isMobile) {
    return _buildGlassPanel(
      padding: EdgeInsets.all(isMobile ? 14 : 16),
      borderRadius: BorderRadius.circular(24),
      tint: Colors.white.withOpacity(0.68),
      blur: 18,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [],
      ),
    );
  }

  Widget _buildResumoPorFundamento(bool isMobile) {
    var maxValue = 1;

    final dados = _metrics.map((metric) {
      final positivos = _totalCampoDoSet(metric.positiveField);
      final erros = _totalCampoDoSet(metric.negativeField);
      final total = positivos + erros;

      if (positivos > maxValue) maxValue = positivos;
      if (erros > maxValue) maxValue = erros;

      return {
        'metric': metric,
        'positivos': positivos,
        'erros': erros,
        'total': total,
        'aproveitamento': total == 0 ? 0 : ((positivos / total) * 100).round(),
      };
    }).toList();

    return Container(
      padding: EdgeInsets.all(isMobile ? 16 : 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: olympusBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.045),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [olympusBlue, olympusLightBlue],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.sports_volleyball_rounded,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Resumo do time por fundamento',
                      style: TextStyle(
                        color: olympusBlue,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Desempenho vertical do set selecionado',
                      style: TextStyle(
                        color: olympusMuted,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              _buildChartLegendItem(color: olympusSuccess, label: 'Ações'),
              _buildChartLegendItem(color: olympusDanger, label: 'Erros'),
              _buildChartLegendItem(
                  color: olympusGold, label: 'Aproveitamento'),
            ],
          ),
          const SizedBox(height: 18),
          SizedBox(
            height: isMobile ? 340 : 365,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final chartHeight = constraints.maxHeight - 152;

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: dados.map((data) {
                    final metric = data['metric'] as ScoutMetric;
                    final positivos = data['positivos'] as int;
                    final erros = data['erros'] as int;
                    final aproveitamento = data['aproveitamento'] as int;

                    final positiveHeight = maxValue <= 0
                        ? 0.0
                        : (positivos / maxValue) * chartHeight;
                    final errorHeight =
                        maxValue <= 0 ? 0.0 : (erros / maxValue) * chartHeight;

                    return Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Text(
                              '$aproveitamento%',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: olympusGold,
                                fontSize: isMobile ? 10 : 11,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Expanded(
                              child: Align(
                                alignment: Alignment.bottomCenter,
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    _buildVerticalBar(
                                      value: positivos,
                                      height: positiveHeight,
                                      color: olympusSuccess,
                                      gradientEnd: const Color(0xFF4ADE80),
                                      width: isMobile ? 14 : 20,
                                    ),
                                    SizedBox(width: isMobile ? 4 : 6),
                                    _buildVerticalBar(
                                      value: erros,
                                      height: errorHeight,
                                      color: olympusDanger,
                                      gradientEnd: const Color(0xFFF87171),
                                      width: isMobile ? 14 : 20,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            Icon(
                              metric.icon,
                              color: olympusBlue,
                              size: isMobile ? 16 : 18,
                            ),
                            const SizedBox(height: 5),
                            Text(
                              metric.title,
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: olympusBlue,
                                fontSize: isMobile ? 9.5 : 11,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '+$positivos',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: olympusSuccess,
                                fontSize: isMobile ? 9 : 10,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            Text(
                              '$erros erros',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: olympusDanger,
                                fontSize: isMobile ? 8.5 : 9.5,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRankingSection(bool isMobile) {
    final destaques = _rankingAtletas(porErros: false);
    final atencao = _rankingAtletas(porErros: true);

    Widget podiumCard({
      required String title,
      required List<Map<String, dynamic>> data,
      required String valueKey,
      required String suffix,
      required Color color,
      required IconData icon,
    }) {
      return _buildGlassPanel(
        padding: EdgeInsets.all(isMobile ? 12 : 14),
        borderRadius: BorderRadius.circular(22),
        tint: color.withOpacity(0.07),
        blur: 14,
        elevated: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      color: color,
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (data.isEmpty)
              Text(
                'Sem dados ainda',
                style: TextStyle(
                  color: color.withOpacity(0.75),
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                ),
              )
            else
              ...data.take(3).toList().asMap().entries.map((entry) {
                final index = entry.key + 1;
                final item = entry.value;
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.72),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white.withOpacity(0.58)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 26,
                        height: 26,
                        decoration: BoxDecoration(
                          color: color.withOpacity(0.13),
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Text(
                            '$index',
                            style: TextStyle(
                              color: color,
                              fontSize: 12,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Text(
                          (item['nome'] ?? 'Atleta').toString(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: olympusBlue,
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      Text(
                        '${item[valueKey]} $suffix',
                        style: TextStyle(
                          color: color,
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                );
              }),
          ],
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final stack = constraints.maxWidth < 520;

        final children = [
          podiumCard(
            title: 'Top ações',
            data: destaques,
            valueKey: 'positivos',
            suffix: 'ações',
            color: olympusSuccess,
            icon: Icons.trending_up_rounded,
          ),
          podiumCard(
            title: 'Mais erros',
            data: atencao,
            valueKey: 'erros',
            suffix: 'erros',
            color: olympusDanger,
            icon: Icons.warning_amber_rounded,
          ),
        ];

        if (stack) {
          return Column(
            children: [
              SizedBox(width: double.infinity, child: children[0]),
              const SizedBox(height: 10),
              SizedBox(width: double.infinity, child: children[1]),
            ],
          );
        }

        return Row(
          children: [
            Expanded(child: children[0]),
            const SizedBox(width: 10),
            Expanded(child: children[1]),
          ],
        );
      },
    );
  }

  Widget _buildSetSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Sets do jogo',
                style: TextStyle(
                  color: olympusMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            TextButton.icon(
              onPressed: _selecionarQuantidadeSets,
              icon: const Icon(Icons.tune_rounded, size: 16),
              label: Text('$_quantidadeSets sets'),
              style: TextButton.styleFrom(
                foregroundColor: olympusBlue,
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
            ),
          ],
        ),
        SizedBox(
          height: 42,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _quantidadeSets,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final setNumber = index + 1;
              final selected = _setSelecionado == setNumber;

              return ChoiceChip(
                label: Text('Set $setNumber'),
                selected: selected,
                onSelected: (_) {
                  setState(() {
                    _setSelecionado = setNumber;
                  });
                },
                selectedColor: olympusGold,
                backgroundColor: Colors.white,
                labelStyle: TextStyle(
                  color: selected ? olympusBlue : olympusMuted,
                  fontWeight: FontWeight.w800,
                ),
                side: BorderSide(
                  color: selected ? olympusGold : olympusBorder,
                ),
                showCheckmark: false,
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildTopSetFilter(bool isMobile) {
    return _buildGlassPanel(
      padding: EdgeInsets.fromLTRB(
        isMobile ? 12 : 16,
        isMobile ? 10 : 12,
        isMobile ? 12 : 16,
        isMobile ? 10 : 12,
      ),
      borderRadius: BorderRadius.circular(22),
      tint: Colors.white.withOpacity(0.72),
      blur: 18,
      child: Row(
        children: [
          const Icon(Icons.tune_rounded, color: olympusBlue, size: 18),
          const SizedBox(width: 8),
          const Text(
            'Set',
            style: TextStyle(
              color: olympusBlue,
              fontWeight: FontWeight.w900,
              fontSize: 13,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: SizedBox(
              height: 36,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _quantidadeSets,
                separatorBuilder: (_, __) => const SizedBox(width: 7),
                itemBuilder: (context, index) {
                  final setNumber = index + 1;
                  final selected = _setSelecionado == setNumber;

                  return ChoiceChip(
                    label: Text('Set $setNumber'),
                    selected: selected,
                    showCheckmark: false,
                    selectedColor: olympusGold,
                    backgroundColor: Colors.white.withOpacity(0.82),
                    side: BorderSide(
                      color: selected ? olympusGold : olympusBorder,
                    ),
                    labelStyle: TextStyle(
                      color: selected ? olympusBlue : olympusMuted,
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                    ),
                    onSelected: (_) {
                      setState(() {
                        _setSelecionado = setNumber;
                      });
                    },
                  );
                },
              ),
            ),
          ),
          const SizedBox(width: 8),
          InkWell(
            onTap: _selecionarQuantidadeSets,
            borderRadius: BorderRadius.circular(999),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
              decoration: BoxDecoration(
                color: olympusBlue.withOpacity(0.08),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '$_quantidadeSets sets',
                style: const TextStyle(
                  color: olympusBlue,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAlertaInteligente(bool isMobile) {
    final insight = _insightInteligente();
    final color = insight['color'] as Color;

    return _buildGlassPanel(
      padding: EdgeInsets.all(isMobile ? 12 : 14),
      borderRadius: BorderRadius.circular(22),
      tint: color.withOpacity(0.08),
      blur: 16,
      elevated: false,
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: color.withOpacity(0.14),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              insight['icon'] as IconData,
              color: color,
              size: 21,
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  insight['title'].toString(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: color,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  insight['message'].toString(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: olympusMuted,
                    fontSize: 11.5,
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

  Widget _buildResumoTodosSets(bool isMobile) {
    final positivos = _totalGeralTodosSets(positivos: true);
    final erros = _totalGeralTodosSets(positivos: false);
    final total = positivos + erros;
    final aproveitamento = total == 0 ? 0 : ((positivos / total) * 100).round();

    Widget metricCard({
      required String label,
      required String value,
      required Color color,
      required IconData icon,
    }) {
      return Expanded(
        child: Container(
          height: isMobile ? 70 : 82,
          padding: EdgeInsets.symmetric(
            horizontal: isMobile ? 8 : 11,
            vertical: isMobile ? 8 : 10,
          ),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.72),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withOpacity(0.65)),
            boxShadow: [
              BoxShadow(
                color: color.withOpacity(0.10),
                blurRadius: 14,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: isMobile ? 30 : 36,
                height: isMobile ? 30 : 36,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.13),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: isMobile ? 17 : 20),
              ),
              SizedBox(width: isMobile ? 7 : 9),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: color,
                        fontSize: isMobile ? 16 : 22,
                        fontWeight: FontWeight.w900,
                        height: 1,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: olympusBlue,
                        fontSize: isMobile ? 8.5 : 10.5,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    return _buildGlassPanel(
      padding: EdgeInsets.all(isMobile ? 12 : 16),
      borderRadius: BorderRadius.circular(24),
      tint: Colors.white.withOpacity(0.68),
      blur: 18,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Visão consolidada do jogo',
            style: TextStyle(
              color: olympusBlue,
              fontSize: 15,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              metricCard(
                label: 'Ações',
                value: '$positivos',
                color: olympusSuccess,
                icon: Icons.check_circle_rounded,
              ),
              const SizedBox(width: 8),
              metricCard(
                label: 'Erros',
                value: '$erros',
                color: olympusDanger,
                icon: Icons.cancel_rounded,
              ),
              const SizedBox(width: 8),
              metricCard(
                label: 'Aproveit.',
                value: '$aproveitamento%',
                color: olympusGold,
                icon: Icons.auto_awesome_rounded,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(bool isMobile) {
    return _buildGlassPanel(
      padding: EdgeInsets.all(isMobile ? 12 : 14),
      borderRadius: BorderRadius.circular(22),
      tint: Colors.white.withOpacity(0.66),
      blur: 16,
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: olympusGold.withOpacity(0.16),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.emoji_events_rounded,
              color: olympusGold,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  (widget.treino['event_name'] ?? 'Campeonato').toString(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: olympusText,
                    fontSize: isMobile ? 16 : 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${(widget.treino['event_date'] ?? '').toString()} • ${(widget.treino['event_time'] ?? '').toString()}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: olympusMuted,
                    fontSize: isMobile ? 11.5 : 12.5,
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

  Widget _buildSummaryPill({
    required String label,
    required int value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$value',
            style: TextStyle(
              color: color,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCounterButton({
    required IconData icon,
    required VoidCallback onPressed,
    required Color color,
  }) {
    return SizedBox(
      width: 32,
      height: 32,
      child: IconButton.filledTonal(
        onPressed: _saving ? null : onPressed,
        icon: Icon(icon, size: 16),
        color: color,
        padding: EdgeInsets.zero,
      ),
    );
  }

  Widget _buildMetricRow({
    required ScoutMetric metric,
    required String athleteId,
    required Map<String, dynamic> scout,
    required bool isMobile,
  }) {
    final positiveField = metric.positiveField;
    final negativeField = metric.negativeField;
    final positiveValue = _getInt(scout, positiveField);
    final negativeValue = _getInt(scout, negativeField);

    Widget buildSide({
      required String label,
      required int value,
      required String field,
      required Color color,
    }) {
      return Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          decoration: BoxDecoration(
            color: color.withOpacity(0.07),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withOpacity(0.16)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        color: color,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      '$value',
                      style: TextStyle(
                        color: color,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
              _buildCounterButton(
                icon: Icons.remove_rounded,
                color: color,
                onPressed: () => _alterarContador(athleteId, field, -1),
              ),
              const SizedBox(width: 4),
              _buildCounterButton(
                icon: Icons.add_rounded,
                color: color,
                onPressed: () => _alterarContador(athleteId, field, 1),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(metric.icon, size: 16, color: olympusBlue),
              const SizedBox(width: 6),
              Text(
                metric.title,
                style: const TextStyle(
                  color: olympusBlue,
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              buildSide(
                label: metric.positiveLabel,
                value: positiveValue,
                field: positiveField,
                color: olympusSuccess,
              ),
              const SizedBox(width: 8),
              buildSide(
                label: metric.negativeLabel,
                value: negativeValue,
                field: negativeField,
                color: olympusDanger,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAthleteScoutCard(Map<String, dynamic> atleta, bool isMobile) {
    final athleteId = (atleta['user_id'] ?? '').toString();
    final nome = (atleta['nome'] ?? 'Atleta').toString();
    final avatarUrl = (atleta['avatar_url'] ?? '').toString();
    final scout = _getScout(athleteId);
    final positivos = _totalPositivo(scout);
    final erros = _totalErro(scout);
    final controller = _getObservationController(athleteId);
    final expanded = _athleteCardsExpanded.contains(athleteId);

    void toggleExpanded() {
      setState(() {
        if (expanded) {
          _athleteCardsExpanded.remove(athleteId);
        } else {
          _athleteCardsExpanded.add(athleteId);
        }
      });
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: olympusBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Material(
          color: Colors.white,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InkWell(
                onTap: toggleExpanded,
                child: Padding(
                  padding: EdgeInsets.all(isMobile ? 14 : 16),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: isMobile ? 22 : 24,
                        backgroundColor: olympusGold.withOpacity(0.18),
                        backgroundImage: avatarUrl.trim().isNotEmpty
                            ? NetworkImage(avatarUrl)
                            : null,
                        child: avatarUrl.trim().isEmpty
                            ? Text(
                                nome.isNotEmpty ? nome[0].toUpperCase() : '?',
                                style: const TextStyle(
                                  color: olympusBlue,
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
                              nome,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: olympusText,
                                fontSize: isMobile ? 15 : 16,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              'Set $_setSelecionado • +$positivos ações • $erros erros • Nota ${_pontuacaoAutomatica(scout)} (${_conceitoAutomatico(_pontuacaoAutomatica(scout))})',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: olympusMuted,
                                fontSize: isMobile ? 11.5 : 12.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      AnimatedRotation(
                        turns: expanded ? 0.5 : 0,
                        duration: const Duration(milliseconds: 180),
                        child: const Icon(
                          Icons.keyboard_arrow_down_rounded,
                          color: olympusMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              AnimatedCrossFade(
                firstChild: const SizedBox.shrink(),
                secondChild: Padding(
                  padding: EdgeInsets.fromLTRB(
                    isMobile ? 14 : 16,
                    0,
                    isMobile ? 14 : 16,
                    isMobile ? 14 : 16,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Divider(height: 1),
                      const SizedBox(height: 14),
                      ..._metrics.map(
                        (metric) => _buildMetricRow(
                          metric: metric,
                          athleteId: athleteId,
                          scout: scout,
                          isMobile: isMobile,
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () => _abrirRelatorioAtleta(atleta),
                          icon:
                              const Icon(Icons.person_search_rounded, size: 16),
                          label: const Text('Relatório por atleta'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: olympusPurple,
                            side: const BorderSide(color: olympusPurple),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: controller,
                        maxLines: 2,
                        decoration: const InputDecoration(
                          labelText: 'Observação do jogo',
                          hintText:
                              'Ex: entrou no set 2, melhorou recepção, errou saque decisivo...',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _saving
                              ? null
                              : () => _salvarObservacao(athleteId),
                          icon: const Icon(Icons.save_outlined, size: 16),
                          label: const Text('Salvar observação'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: olympusBlue,
                            side: const BorderSide(color: olympusBlue),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                crossFadeState: expanded
                    ? CrossFadeState.showSecond
                    : CrossFadeState.showFirst,
                duration: const Duration(milliseconds: 180),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMobileScoutSection({
    required String title,
    required IconData icon,
    required Widget child,
    bool initiallyExpanded = false,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: olympusBorder),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(
          dividerColor: Colors.transparent,
          splashColor: olympusBlue.withOpacity(0.06),
          highlightColor: olympusBlue.withOpacity(0.04),
        ),
        child: ExpansionTile(
          initiallyExpanded: initiallyExpanded,
          tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
          childrenPadding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
          leading: Icon(icon, color: olympusBlue, size: 18),
          iconColor: olympusBlue,
          collapsedIconColor: olympusMuted,
          title: Text(
            title,
            style: const TextStyle(
              color: olympusBlue,
              fontSize: 13,
              fontWeight: FontWeight.w900,
            ),
          ),
          children: [child],
        ),
      ),
    );
  }

  Widget _buildMobileBottomActions() {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(8, 7, 8, 9),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border(
            top: BorderSide(color: Colors.black.withOpacity(0.08)),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 12,
              offset: const Offset(0, -3),
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _selecionarQuantidadeSets,
                icon: const Icon(Icons.tune_rounded, size: 15),
                label: Text(
                  '$_quantidadeSets sets',
                  overflow: TextOverflow.ellipsis,
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: olympusBlue,
                  side: const BorderSide(color: olympusBlue),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _abrirRelatorio,
                icon: const Icon(Icons.summarize_outlined, size: 15),
                label: const Text(
                  'Relatório',
                  overflow: TextOverflow.ellipsis,
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: olympusBlue,
                  side: const BorderSide(color: olympusBlue),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _copiarRelatorio,
                icon: _buildWhatsappIcon(size: 15),
                label: const Text(
                  'WhatsApp',
                  overflow: TextOverflow.ellipsis,
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: whatsappGreen,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfessionalActionHub(bool isMobile) {
    final totalAtletas = _atletas.length;
    final positivos = _totalGeralTodosSets(positivos: true);
    final erros = _totalGeralTodosSets(positivos: false);
    final total = positivos + erros;
    final aproveitamento = total == 0 ? 0 : ((positivos / total) * 100).round();

    Widget miniStat({
      required String label,
      required String value,
      required IconData icon,
      required Color color,
    }) {
      return Expanded(
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: isMobile ? 8 : 10,
            vertical: isMobile ? 8 : 10,
          ),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.68),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withOpacity(0.58)),
          ),
          child: Row(
            children: [
              Icon(icon, color: color, size: isMobile ? 16 : 18),
              const SizedBox(width: 6),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: color,
                        fontSize: isMobile ? 13 : 15,
                        fontWeight: FontWeight.w900,
                        height: 1,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: olympusMuted,
                        fontSize: isMobile ? 8.5 : 9.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    return _buildGlassPanel(
      padding: EdgeInsets.fromLTRB(
        isMobile ? 10 : 14,
        isMobile ? 10 : 12,
        isMobile ? 10 : 14,
        isMobile ? 10 : 12,
      ),
      borderRadius: BorderRadius.zero,
      tint: Colors.white.withOpacity(0.78),
      blur: 22,
      child: SafeArea(
        bottom: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  width: isMobile ? 34 : 38,
                  height: isMobile ? 34 : 38,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [olympusBlue, olympusLightBlue],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: const Icon(
                    Icons.sports_volleyball_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Central do campeonato',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: olympusText,
                      fontSize: isMobile ? 15 : 17,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: _abrirRelatorio,
                  icon: const Icon(Icons.summarize_outlined, size: 15),
                  label: const Text('Relatório'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: olympusBlue,
                    side: const BorderSide(color: olympusBlue),
                    visualDensity: VisualDensity.compact,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  ),
                ),
                const SizedBox(width: 6),
                ElevatedButton.icon(
                  onPressed: _copiarRelatorio,
                  icon: _buildWhatsappIcon(size: 15),
                  label: const Text('WhatsApp'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: whatsappGreen,
                    foregroundColor: Colors.white,
                    visualDensity: VisualDensity.compact,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 9),
            Row(
              children: [
                miniStat(
                  label: 'Atletas',
                  value: '$totalAtletas',
                  icon: Icons.groups_rounded,
                  color: olympusBlue,
                ),
                const SizedBox(width: 7),
                miniStat(
                  label: 'Ações',
                  value: '$positivos',
                  icon: Icons.trending_up_rounded,
                  color: olympusSuccess,
                ),
                const SizedBox(width: 7),
                miniStat(
                  label: 'Aproveit.',
                  value: '$aproveitamento%',
                  icon: Icons.insights_rounded,
                  color: olympusGold,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = _isMobile(context);

    final contentSections = <Widget>[
      _buildHeader(isMobile),
      const SizedBox(height: 10),
      _buildTopSetFilter(isMobile),
      const SizedBox(height: 10),
      _buildAlertaInteligente(isMobile),
      const SizedBox(height: 10),
      _buildResumoTodosSets(isMobile),
      const SizedBox(height: 10),
      _buildComparativoSets(isMobile),
      const SizedBox(height: 10),
      _buildResumoPorFundamento(isMobile),
      const SizedBox(height: 10),
      _buildRankingSection(isMobile),
    ];

    return Scaffold(
      backgroundColor: olympusBg,
      appBar: AppBar(
        title: const Text('Scout do Campeonato'),
        backgroundColor: olympusBlue,
        foregroundColor: Colors.white,
        actions: [
          if (_saving)
            const Padding(
              padding: EdgeInsets.only(right: 12),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                ),
              ),
            ),
          IconButton(
            tooltip: 'Avaliar atletas',
            onPressed: _loadingAthletes ? null : _abrirAvaliacaoAtletas,
            icon: const Icon(Icons.groups_rounded),
          ),
          IconButton(
            onPressed: _loadingAthletes ? null : _carregarAtletasEScout,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loadingAthletes
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: olympusDanger,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                )
              : Column(
                  children: [
                    _buildProfessionalActionHub(isMobile),
                    Expanded(
                      child: RefreshIndicator(
                        onRefresh: _carregarAtletasEScout,
                        child: ListView(
                          padding: EdgeInsets.fromLTRB(
                            isMobile ? 10 : 16,
                            isMobile ? 10 : 16,
                            isMobile ? 10 : 16,
                            isMobile ? 20 : 24,
                          ),
                          children: contentSections,
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }
}

class ChampionshipLeagueGamesWidget extends StatefulWidget {
  const ChampionshipLeagueGamesWidget({
    super.key,
    required this.jogos,
    required this.onOpenGame,
  });

  final List<Map<String, dynamic>> jogos;
  final void Function(Map<String, dynamic> jogo) onOpenGame;

  @override
  State<ChampionshipLeagueGamesWidget> createState() =>
      _ChampionshipLeagueGamesWidgetState();
}

class _ChampionshipLeagueGamesWidgetState
    extends State<ChampionshipLeagueGamesWidget> {
  String? ligaSelecionada;

  Map<String, List<Map<String, dynamic>>> _groupByLeague() {
    final map = <String, List<Map<String, dynamic>>>{};

    for (final jogo in widget.jogos) {
      final liga = (jogo['league_name'] ??
              jogo['championship_name'] ??
              jogo['event_name'] ??
              'Liga')
          .toString();

      map.putIfAbsent(liga, () => []);
      map[liga]!.add(jogo);
    }

    return map;
  }

  @override
  Widget build(BuildContext context) {
    final ligas = _groupByLeague();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: ligas.keys.map((liga) {
            final selected = ligaSelecionada == liga;

            return ChoiceChip(
              label: Text(liga),
              selected: selected,
              showCheckmark: false,
              selectedColor: const Color(0xFFD4AF37),
              backgroundColor: Colors.white,
              side: BorderSide(
                color: selected
                    ? const Color(0xFFD4AF37)
                    : const Color(0xFFE4EDF5),
              ),
              labelStyle: TextStyle(
                color: selected
                    ? const Color(0xFF1E3A5F)
                    : const Color(0xFF53657B),
                fontWeight: FontWeight.w900,
              ),
              onSelected: (_) {
                setState(() {
                  ligaSelecionada = ligaSelecionada == liga ? null : liga;
                });
              },
            );
          }).toList(),
        ),
        const SizedBox(height: 14),
        if (ligaSelecionada != null)
          ...ligas[ligaSelecionada]!.map(
            (jogo) => Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: const Color(0xFFE4EDF5),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.sports_volleyball_rounded,
                    color: Color(0xFF1E3A5F),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          (jogo['event_name'] ?? 'Jogo').toString(),
                          style: const TextStyle(
                            color: Color(0xFF1E3A5F),
                            fontWeight: FontWeight.w900,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${(jogo['event_date'] ?? '').toString()} • ${(jogo['event_time'] ?? '').toString()}',
                          style: const TextStyle(
                            color: Color(0xFF53657B),
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  ElevatedButton(
                    onPressed: () => widget.onOpenGame(jogo),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1E3A5F),
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Abrir'),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
