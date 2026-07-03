import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ChampionshipAthleteFoundationMetric {
  final String title;
  final String positiveLabel;
  final String negativeLabel;
  final String positiveField;
  final String negativeField;
  final IconData icon;

  const ChampionshipAthleteFoundationMetric({
    required this.title,
    required this.positiveLabel,
    required this.negativeLabel,
    required this.positiveField,
    required this.negativeField,
    required this.icon,
  });
}

class ChampionshipScoutActionOption {
  final String label;
  final String description;
  final String quality;
  final String impact;
  final int weight;

  const ChampionshipScoutActionOption({
    required this.label,
    required this.description,
    required this.quality,
    required this.impact,
    required this.weight,
  });
}

class ChampionshipScoutActionChoice {
  final ChampionshipAthleteFoundationMetric metric;
  final ChampionshipScoutActionOption option;
  final bool isError;

  const ChampionshipScoutActionChoice({
    required this.metric,
    required this.option,
    required this.isError,
  });
}

class CoachChampionshipAthleteEvaluationPage extends StatefulWidget {
  const CoachChampionshipAthleteEvaluationPage({
    super.key,
    required this.treino,
    required this.quantidadeSets,
  });

  final Map<String, dynamic> treino;
  final int quantidadeSets;

  @override
  State<CoachChampionshipAthleteEvaluationPage> createState() =>
      _CoachChampionshipAthleteEvaluationPageState();
}

class _CoachChampionshipAthleteEvaluationPageState
    extends State<CoachChampionshipAthleteEvaluationPage> {
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

  final SupabaseClient _supabase = Supabase.instance.client;
  final TextEditingController _buscaController = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  String? _error;

  int _setSelecionado = 1;
  bool _mostrarSomenteComLancamentos = false;

  final List<Map<String, dynamic>> _atletas = [];
  final Map<String, Map<String, dynamic>> _scoutPorAtletaSet = {};
  final Map<String, TextEditingController> _observacaoControllers = {};

  final List<ChampionshipAthleteFoundationMetric> _metrics = const [
    ChampionshipAthleteFoundationMetric(
      title: 'Saque',
      positiveLabel: 'Ponto',
      negativeLabel: 'Erro',
      positiveField: 'saque_ponto',
      negativeField: 'saque_erro',
      icon: Icons.sports_volleyball_rounded,
    ),
    ChampionshipAthleteFoundationMetric(
      title: 'Recepção',
      positiveLabel: 'Boa',
      negativeLabel: 'Erro',
      positiveField: 'recepcao_boa',
      negativeField: 'recepcao_erro',
      icon: Icons.front_hand_rounded,
    ),
    ChampionshipAthleteFoundationMetric(
      title: 'Passe',
      positiveLabel: 'Bom',
      negativeLabel: 'Erro',
      positiveField: 'passe_bom',
      negativeField: 'passe_erro',
      icon: Icons.swap_horiz_rounded,
    ),
    ChampionshipAthleteFoundationMetric(
      title: 'Ataque',
      positiveLabel: 'Ponto',
      negativeLabel: 'Erro',
      positiveField: 'ataque_ponto',
      negativeField: 'ataque_erro',
      icon: Icons.bolt_rounded,
    ),
    ChampionshipAthleteFoundationMetric(
      title: 'Largada de bola',
      positiveLabel: 'Boa',
      negativeLabel: 'Erro',
      positiveField: 'largada_bola_boa',
      negativeField: 'largada_bola_erro',
      icon: Icons.touch_app_rounded,
    ),
    ChampionshipAthleteFoundationMetric(
      title: 'Bloqueio',
      positiveLabel: 'Ponto',
      negativeLabel: 'Erro',
      positiveField: 'bloqueio_ponto',
      negativeField: 'bloqueio_erro',
      icon: Icons.block_rounded,
    ),
    ChampionshipAthleteFoundationMetric(
      title: 'Defesa',
      positiveLabel: 'Boa',
      negativeLabel: 'Erro',
      positiveField: 'defesa_boa',
      negativeField: 'defesa_erro',
      icon: Icons.shield_rounded,
    ),
    ChampionshipAthleteFoundationMetric(
      title: 'Levantamento',
      positiveLabel: 'Bom',
      negativeLabel: 'Erro',
      positiveField: 'levantamento_bom',
      negativeField: 'levantamento_erro',
      icon: Icons.pan_tool_alt_rounded,
    ),
  ];

  static const Map<String, List<ChampionshipScoutActionOption>>
      _positiveActionOptions = {
    'Saque': [
      ChampionshipScoutActionOption(
        label: 'Ace',
        description: 'Bola toca o chão ou gera recepção sem controle.',
        quality: 'elite',
        impact: 'ponto_direto',
        weight: 4,
      ),
      ChampionshipScoutActionOption(
        label: 'Quebrou passe',
        description: 'Adversário recebe mal e não consegue atacar rápido.',
        quality: 'boa',
        impact: 'vantagem',
        weight: 3,
      ),
      ChampionshipScoutActionOption(
        label: 'Saque tático',
        description: 'Saque direcionado que tirou o adversário do sistema.',
        quality: 'boa',
        impact: 'vantagem',
        weight: 2,
      ),
      ChampionshipScoutActionOption(
        label: 'Saque seguro',
        description: 'Saque colocado que manteve pressão sem erro.',
        quality: 'regular',
        impact: 'neutro',
        weight: 1,
      ),
    ],
    'Ataque': [
      ChampionshipScoutActionOption(
        label: 'Ponto direto',
        description: 'Bola toca a quadra adversária.',
        quality: 'elite',
        impact: 'ponto_direto',
        weight: 4,
      ),
      ChampionshipScoutActionOption(
        label: 'Explorada',
        description: 'Bate no bloqueio e sai.',
        quality: 'boa',
        impact: 'ponto_direto',
        weight: 4,
      ),
      ChampionshipScoutActionOption(
        label: 'Largadinha',
        description: 'Bola colocada que gerou ponto.',
        quality: 'boa',
        impact: 'ponto_direto',
        weight: 3,
      ),
      ChampionshipScoutActionOption(
        label: 'Contra-ataque',
        description: 'Ataque convertido após defesa ou bloqueio.',
        quality: 'boa',
        impact: 'ponto_direto',
        weight: 3,
      ),
      ChampionshipScoutActionOption(
        label: 'Ataque potente',
        description: 'Ataque forte que gerou vantagem clara.',
        quality: 'boa',
        impact: 'vantagem',
        weight: 2,
      ),
    ],
    'Largada de bola': [
      ChampionshipScoutActionOption(
        label: 'Ponto de largada',
        description: 'Largada caiu direto na quadra adversária.',
        quality: 'elite',
        impact: 'ponto_direto',
        weight: 4,
      ),
      ChampionshipScoutActionOption(
        label: 'Largada tática',
        description: 'Largada tirou a defesa do sistema.',
        quality: 'boa',
        impact: 'vantagem',
        weight: 3,
      ),
      ChampionshipScoutActionOption(
        label: 'Largada inteligente',
        description: 'Boa leitura do espaço vazio da defesa.',
        quality: 'boa',
        impact: 'vantagem',
        weight: 2,
      ),
    ],
    'Bloqueio': [
      ChampionshipScoutActionOption(
        label: 'Ponto de bloqueio',
        description: 'Bola cai direto na quadra adversária.',
        quality: 'elite',
        impact: 'ponto_direto',
        weight: 4,
      ),
      ChampionshipScoutActionOption(
        label: 'Gerou contra-ataque',
        description: 'Bloqueio amorteceu e deu transição ofensiva.',
        quality: 'boa',
        impact: 'vantagem',
        weight: 3,
      ),
    ],
    'Recepção': [
      ChampionshipScoutActionOption(
        label: 'Passe A',
        description: 'Recepção na mão do levantador.',
        quality: 'elite',
        impact: 'vantagem',
        weight: 3,
      ),
      ChampionshipScoutActionOption(
        label: 'Passe B',
        description: 'Passe corrigível, permitiu sequência organizada.',
        quality: 'boa',
        impact: 'neutro',
        weight: 2,
      ),
      ChampionshipScoutActionOption(
        label: 'Estabilizou rally',
        description: 'Recepção manteve a bola viva sob pressão.',
        quality: 'regular',
        impact: 'neutro',
        weight: 1,
      ),
      ChampionshipScoutActionOption(
        label: 'Passe para pipe',
        description: 'Recepção abriu opção de pipe.',
        quality: 'elite',
        impact: 'vantagem',
        weight: 3,
      ),
    ],
    'Passe': [
      ChampionshipScoutActionOption(
        label: 'Passe A',
        description: 'Passe perfeito, permite todas as opções ofensivas.',
        quality: 'elite',
        impact: 'vantagem',
        weight: 3,
      ),
      ChampionshipScoutActionOption(
        label: 'Passe B',
        description: 'Passe controlado, mantém a jogada organizada.',
        quality: 'boa',
        impact: 'neutro',
        weight: 2,
      ),
      ChampionshipScoutActionOption(
        label: 'Passe de cobertura',
        description: 'Cobertura ou ajuste que manteve a bola viva.',
        quality: 'boa',
        impact: 'neutro',
        weight: 2,
      ),
    ],
    'Defesa': [
      ChampionshipScoutActionOption(
        label: 'Gerou contra-ataque',
        description: 'Defesa permitiu transição ofensiva.',
        quality: 'elite',
        impact: 'vantagem',
        weight: 3,
      ),
      ChampionshipScoutActionOption(
        label: 'Defesa difícil',
        description: 'Salvou bola de alta dificuldade.',
        quality: 'boa',
        impact: 'vantagem',
        weight: 2,
      ),
      ChampionshipScoutActionOption(
        label: 'Cobertura',
        description: 'Cobriu ataque/bloqueio e manteve a jogada.',
        quality: 'boa',
        impact: 'neutro',
        weight: 2,
      ),
      ChampionshipScoutActionOption(
        label: 'Pancada defendida',
        description: 'Defendeu ataque forte.',
        quality: 'boa',
        impact: 'vantagem',
        weight: 2,
      ),
    ],
    'Levantamento': [
      ChampionshipScoutActionOption(
        label: 'Entrada precisa',
        description: 'Bola precisa para entrada.',
        quality: 'boa',
        impact: 'vantagem',
        weight: 2,
      ),
      ChampionshipScoutActionOption(
        label: 'Saída precisa',
        description: 'Bola precisa para saída.',
        quality: 'boa',
        impact: 'vantagem',
        weight: 2,
      ),
      ChampionshipScoutActionOption(
        label: 'Pipe preciso',
        description: 'Bola precisa para pipe.',
        quality: 'elite',
        impact: 'vantagem',
        weight: 3,
      ),
      ChampionshipScoutActionOption(
        label: 'Bola rápida',
        description: 'Levantamento acelerou a jogada.',
        quality: 'boa',
        impact: 'vantagem',
        weight: 2,
      ),
      ChampionshipScoutActionOption(
        label: 'Distribuição inteligente',
        description: 'Escolha tática gerou vantagem ofensiva.',
        quality: 'elite',
        impact: 'vantagem',
        weight: 3,
      ),
    ],
  };

  static const Map<String, List<ChampionshipScoutActionOption>>
      _negativeActionOptions = {
    'Saque': [
      ChampionshipScoutActionOption(
        label: 'Rede',
        description: 'Saque parou na rede.',
        quality: 'ruim',
        impact: 'prejuizo',
        weight: -3,
      ),
      ChampionshipScoutActionOption(
        label: 'Fora',
        description: 'Saque foi para fora.',
        quality: 'ruim',
        impact: 'prejuizo',
        weight: -3,
      ),
      ChampionshipScoutActionOption(
        label: 'Pé na linha',
        description: 'Erro de execução ao sacar.',
        quality: 'ruim',
        impact: 'prejuizo',
        weight: -3,
      ),
      ChampionshipScoutActionOption(
        label: 'Rodízio',
        description: 'Erro de ordem/rodízio no saque.',
        quality: 'ruim',
        impact: 'prejuizo',
        weight: -4,
      ),
      ChampionshipScoutActionOption(
        label: 'Saque fácil',
        description: 'Saque sem pressão, facilitou o passe adversário.',
        quality: 'regular',
        impact: 'neutro',
        weight: -1,
      ),
    ],
    'Ataque': [
      ChampionshipScoutActionOption(
        label: 'Rede',
        description: 'Ataque parou na rede.',
        quality: 'ruim',
        impact: 'prejuizo',
        weight: -3,
      ),
      ChampionshipScoutActionOption(
        label: 'Fora',
        description: 'Ataque foi para fora.',
        quality: 'ruim',
        impact: 'prejuizo',
        weight: -3,
      ),
      ChampionshipScoutActionOption(
        label: 'Bloqueio sofrido',
        description: 'Ataque voltou e gerou ponto/pressão contra.',
        quality: 'ruim',
        impact: 'prejuizo',
        weight: -3,
      ),
      ChampionshipScoutActionOption(
        label: 'Invasão',
        description: 'Tocou na rede ou linha central.',
        quality: 'ruim',
        impact: 'prejuizo',
        weight: -3,
      ),
      ChampionshipScoutActionOption(
        label: 'Linha dos 3m',
        description: 'Erro de ataque por pisar/invadir zona.',
        quality: 'ruim',
        impact: 'prejuizo',
        weight: -3,
      ),
    ],
    'Largada de bola': [
      ChampionshipScoutActionOption(
        label: 'Rede',
        description: 'Largada parou na rede.',
        quality: 'ruim',
        impact: 'prejuizo',
        weight: -3,
      ),
      ChampionshipScoutActionOption(
        label: 'Fora',
        description: 'Largada saiu pela lateral ou fundo.',
        quality: 'ruim',
        impact: 'prejuizo',
        weight: -3,
      ),
      ChampionshipScoutActionOption(
        label: 'Previsível',
        description: 'Largada facilitou a defesa adversária.',
        quality: 'regular',
        impact: 'neutro',
        weight: -1,
      ),
    ],
    'Bloqueio': [
      ChampionshipScoutActionOption(
        label: 'Rede',
        description: 'Tocou na rede durante o bloqueio.',
        quality: 'ruim',
        impact: 'prejuizo',
        weight: -3,
      ),
      ChampionshipScoutActionOption(
        label: 'Invasão',
        description: 'Invadiu antes do ataque adversário terminar.',
        quality: 'ruim',
        impact: 'prejuizo',
        weight: -3,
      ),
      ChampionshipScoutActionOption(
        label: 'Desviou para fora',
        description: 'Amorteceu ou desviou a bola para fora.',
        quality: 'ruim',
        impact: 'prejuizo',
        weight: -2,
      ),
      ChampionshipScoutActionOption(
        label: 'Tempo errado',
        description: 'Subiu fora do tempo da bola.',
        quality: 'regular',
        impact: 'neutro',
        weight: -1,
      ),
      ChampionshipScoutActionOption(
        label: 'Não fechou linha',
        description: 'Deixou caminho livre para o ataque adversário.',
        quality: 'regular',
        impact: 'prejuizo',
        weight: -2,
      ),
    ],
    'Recepção': [
      ChampionshipScoutActionOption(
        label: 'Ace sofrido',
        description: 'Bola caiu direto na quadra.',
        quality: 'ruim',
        impact: 'prejuizo',
        weight: -4,
      ),
      ChampionshipScoutActionOption(
        label: 'Passe C',
        description: 'Passe ruim, tirou o time do sistema.',
        quality: 'ruim',
        impact: 'prejuizo',
        weight: -3,
      ),
      ChampionshipScoutActionOption(
        label: 'Manchete para fora',
        description: 'Recepção saiu da quadra.',
        quality: 'ruim',
        impact: 'prejuizo',
        weight: -3,
      ),
      ChampionshipScoutActionOption(
        label: 'Passe colado na rede',
        description: 'Passe dificultou o levantamento.',
        quality: 'regular',
        impact: 'prejuizo',
        weight: -2,
      ),
      ChampionshipScoutActionOption(
        label: 'Comunicação',
        description: 'Erro por falta de comunicação.',
        quality: 'regular',
        impact: 'prejuizo',
        weight: -2,
      ),
    ],
    'Passe': [
      ChampionshipScoutActionOption(
        label: 'Passe C',
        description: 'Passe ruim, tirou o time do sistema.',
        quality: 'ruim',
        impact: 'prejuizo',
        weight: -3,
      ),
      ChampionshipScoutActionOption(
        label: 'Passe para fora',
        description: 'Passe perdeu totalmente o controle.',
        quality: 'ruim',
        impact: 'prejuizo',
        weight: -3,
      ),
      ChampionshipScoutActionOption(
        label: 'Comunicação',
        description: 'Erro de passe por falta de chamada.',
        quality: 'regular',
        impact: 'prejuizo',
        weight: -2,
      ),
    ],
    'Defesa': [
      ChampionshipScoutActionOption(
        label: 'Bola caiu',
        description: 'Defesa não reagiu ou não chegou na bola.',
        quality: 'ruim',
        impact: 'prejuizo',
        weight: -3,
      ),
      ChampionshipScoutActionOption(
        label: 'Defesa para fora',
        description: 'Defesa perdeu controle da bola.',
        quality: 'ruim',
        impact: 'prejuizo',
        weight: -2,
      ),
      ChampionshipScoutActionOption(
        label: 'Tempo errado',
        description: 'Leitura atrasada ou reação lenta.',
        quality: 'regular',
        impact: 'prejuizo',
        weight: -2,
      ),
      ChampionshipScoutActionOption(
        label: 'Sem cobertura',
        description: 'Não cobriu ataque/bloqueio.',
        quality: 'regular',
        impact: 'prejuizo',
        weight: -2,
      ),
    ],
    'Levantamento': [
      ChampionshipScoutActionOption(
        label: 'Dois toques',
        description: 'Infração técnica no levantamento.',
        quality: 'ruim',
        impact: 'prejuizo',
        weight: -3,
      ),
      ChampionshipScoutActionOption(
        label: 'Distribuição previsível',
        description: 'Levantamento facilitou leitura do bloqueio.',
        quality: 'regular',
        impact: 'prejuizo',
        weight: -1,
      ),
    ],
  };

  String get _eventId => (widget.treino['id'] ?? '').toString();

  int get _quantidadeSetsSegura {
    final value = widget.quantidadeSets;
    if (value < 1) return 1;
    if (value > 5) return 5;
    return value;
  }

  @override
  void initState() {
    super.initState();
    _carregarAtletasEScout();
  }

  @override
  void dispose() {
    _buscaController.dispose();
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
    return {
      'event_id': _eventId,
      'athlete_id': athleteId,
      'set_number': setNumber,
      'saque_ponto': 0,
      'saque_erro': 0,
      'recepcao_boa': 0,
      'recepcao_erro': 0,
      'passe_bom': 0,
      'passe_erro': 0,
      'levantamento_bom': 0,
      'levantamento_erro': 0,
      'ataque_ponto': 0,
      'ataque_erro': 0,
      'largada_bola_boa': 0,
      'largada_bola_erro': 0,
      'bloqueio_ponto': 0,
      'bloqueio_erro': 0,
      'defesa_boa': 0,
      'defesa_erro': 0,
      'observacao': '',
    };
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

  bool _isNegativeField(String field) {
    return _metrics.any((metric) => metric.negativeField == field);
  }

  ChampionshipAthleteFoundationMetric? _metricByField(String field) {
    for (final metric in _metrics) {
      if (metric.positiveField == field || metric.negativeField == field) {
        return metric;
      }
    }
    return null;
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

  int _totalPositivoTodosSets(String athleteId) {
    var total = 0;
    for (var set = 1; set <= _quantidadeSetsSegura; set++) {
      final scout = _scoutPorAtletaSet[_key(athleteId, set)] ??
          _emptyScout(athleteId, set);
      total += _totalPositivo(scout);
    }
    return total;
  }

  int _totalErroTodosSets(String athleteId) {
    var total = 0;
    for (var set = 1; set <= _quantidadeSetsSegura; set++) {
      final scout = _scoutPorAtletaSet[_key(athleteId, set)] ??
          _emptyScout(athleteId, set);
      total += _totalErro(scout);
    }
    return total;
  }

  int _notaAutomatica(Map<String, dynamic> scout) {
    final positivos = _totalPositivo(scout);
    final erros = _totalErro(scout);
    final total = positivos + erros;

    if (total == 0) return 0;

    final base = ((positivos / total) * 10).round();
    final bonusVolume = positivos >= 10 ? 1 : 0;
    final penalidadeErro = erros >= 8 ? 1 : 0;

    return (base + bonusVolume - penalidadeErro).clamp(0, 10);
  }

  String _conceito(int nota) {
    if (nota >= 9) return 'Excelente';
    if (nota >= 7) return 'Bom';
    if (nota >= 5) return 'Regular';
    if (nota > 0) return 'Atenção';
    return 'Sem nota';
  }

  int _totalEquipeSet({required bool positivos}) {
    var total = 0;
    for (final atleta in _atletas) {
      final athleteId = (atleta['user_id'] ?? '').toString();
      if (athleteId.isEmpty) continue;

      final scout = _getScout(athleteId);
      total += positivos ? _totalPositivo(scout) : _totalErro(scout);
    }
    return total;
  }

  Future<void> _carregarAtletasEScout() async {
    setState(() {
      _loading = true;
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
          .where((row) => (row['user_id'] ?? '').toString().isNotEmpty)
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
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Erro ao carregar avaliação por fundamento: $e';
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

  Future<void> _salvarScoutActionDetail({
    required String athleteId,
    required ChampionshipScoutActionChoice choice,
  }) async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    try {
      await _supabase.from('match_scout_action_details').insert({
        'event_id': _eventId,
        'athlete_id': athleteId,
        'coach_id': user.id,
        'set_number': _setSelecionado,
        'foundation': choice.metric.title,
        'action_result': choice.isError ? 'erro' : 'acerto',
        'action_subtype': choice.option.label,
        'action_description': choice.option.description,
        'action_quality': choice.option.quality,
        'action_impact': choice.option.impact,
        'weight': choice.option.weight,
      });
    } on PostgrestException catch (e) {
      if (e.code == 'PGRST205' || e.code == '42P01') {
        debugPrint(
          'Tabela match_scout_action_details ainda não existe. '
          'O resumo match_scouts foi salvo normalmente: $e',
        );
        return;
      }
      rethrow;
    }
  }

  Future<ChampionshipScoutActionChoice?> _selecionarDetalheAcao({
    required ChampionshipAthleteFoundationMetric metric,
    required bool isError,
  }) async {
    final options = isError
        ? (_negativeActionOptions[metric.title] ?? const [])
        : (_positiveActionOptions[metric.title] ?? const []);

    if (options.isEmpty) return null;

    final title = isError
        ? 'Motivo do erro em ${metric.title}'
        : 'Tipo de acerto em ${metric.title}';
    final subtitle = isError
        ? 'Opcional: selecione o motivo técnico do erro.'
        : 'Opcional: selecione o tipo de acerto para enriquecer o scout.';

    return showModalBottomSheet<ChampionshipScoutActionChoice>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final color = isError ? olympusDanger : olympusSuccess;

        return DraggableScrollableSheet(
          initialChildSize: 0.62,
          minChildSize: 0.38,
          maxChildSize: 0.88,
          expand: false,
          builder: (context, scrollController) {
            return Container(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 20),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
              ),
              child: SafeArea(
                top: false,
                child: ListView(
                  controller: scrollController,
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
                    Row(
                      children: [
                        Icon(
                          isError
                              ? Icons.error_outline_rounded
                              : Icons.check_circle_outline_rounded,
                          color: color,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            title,
                            style: const TextStyle(
                              color: olympusBlue,
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: olympusMuted,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 16),
                    ...options.map((option) {
                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        decoration: BoxDecoration(
                          color: color.withOpacity(0.07),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: color.withOpacity(0.18)),
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          title: Text(
                            option.label,
                            style: TextStyle(
                              color: color,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 3),
                            child: Text(
                              option.description,
                              style: const TextStyle(
                                color: olympusMuted,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          trailing: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.75),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              option.weight > 0
                                  ? '+${option.weight}'
                                  : '${option.weight}',
                              style: TextStyle(
                                color: color,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          onTap: () {
                            Navigator.pop(
                              context,
                              ChampionshipScoutActionChoice(
                                metric: metric,
                                option: option,
                                isError: isError,
                              ),
                            );
                          },
                        ),
                      );
                    }),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: TextButton(
                        onPressed: () => Navigator.pop(context, null),
                        child: Text(
                          isError ? 'Pular motivo' : 'Pular detalhe',
                          style: const TextStyle(fontWeight: FontWeight.w900),
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
  }

  void _adicionarObservacaoDeAcao({
    required String athleteId,
    required ChampionshipScoutActionChoice choice,
  }) {
    final controller = _getObservationController(athleteId);
    final atual = controller.text.trim();
    final tipo = choice.isError ? 'Erro' : 'Acerto';
    final prefix =
        'Set $_setSelecionado • ${choice.metric.title} • $tipo: ${choice.option.label}';

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

    ChampionshipScoutActionChoice? actionChoice;
    if (delta > 0 && metric != null) {
      actionChoice = await _selecionarDetalheAcao(
        metric: metric,
        isError: _isNegativeField(field),
      );
      if (!mounted) return;
    }

    setState(() {
      scout[field] = novo;
      if (actionChoice != null) {
        _adicionarObservacaoDeAcao(
          athleteId: athleteId,
          choice: actionChoice!,
        );
      }
    });

    try {
      setState(() {
        _saving = true;
      });
      await _salvarScout(athleteId);
      if (actionChoice != null) {
        await _salvarScoutActionDetail(
          athleteId: athleteId,
          choice: actionChoice,
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao salvar fundamento: $e')),
      );
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

  Future<void> _copiarResumoAtletas() async {
    final buffer = StringBuffer();

    buffer.writeln('🏐 Avaliação por fundamento');
    buffer.writeln((widget.treino['event_name'] ?? 'Campeonato').toString());
    buffer.writeln('Set $_setSelecionado');
    buffer.writeln('');

    for (final atleta in _atletasFiltrados()) {
      final athleteId = (atleta['user_id'] ?? '').toString();
      final nome = (atleta['nome'] ?? 'Atleta').toString();
      final scout = _getScout(athleteId);
      final positivos = _totalPositivo(scout);
      final erros = _totalErro(scout);
      final nota = _notaAutomatica(scout);

      if (positivos + erros == 0) continue;

      buffer.writeln('$nome');
      buffer.writeln('Ações: $positivos | Erros: $erros | Nota: $nota');
      for (final metric in _metrics) {
        final pos = _getInt(scout, metric.positiveField);
        final neg = _getInt(scout, metric.negativeField);
        if (pos + neg == 0) continue;
        buffer.writeln('- ${metric.title}: +$pos / $neg erros');
      }

      final obs = (scout['observacao'] ?? '').toString().trim();
      if (obs.isNotEmpty) buffer.writeln('Obs: $obs');
      buffer.writeln('');
    }

    await Clipboard.setData(ClipboardData(text: buffer.toString().trim()));

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Resumo copiado')),
    );
  }

  List<Map<String, dynamic>> _atletasFiltrados() {
    final busca = _buscaController.text.trim().toLowerCase();

    return _atletas.where((atleta) {
      final athleteId = (atleta['user_id'] ?? '').toString();
      final nome = (atleta['nome'] ?? '').toString().toLowerCase();
      final scout = _getScout(athleteId);
      final temLancamento = _totalPositivo(scout) + _totalErro(scout) > 0;

      if (_mostrarSomenteComLancamentos && !temLancamento) return false;
      if (busca.isNotEmpty && !nome.contains(busca)) return false;

      return true;
    }).toList();
  }

  Widget _buildSetSelector(bool isMobile) {
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
            'Set da avaliação',
            style: TextStyle(
              color: olympusBlue,
              fontSize: 14,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: List.generate(_quantidadeSetsSegura, (index) {
              final setNumber = index + 1;
              final selected = _setSelecionado == setNumber;

              return ChoiceChip(
                label: Text('Set $setNumber'),
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
                onSelected: (_) {
                  setState(() {
                    _setSelecionado = setNumber;
                  });
                },
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(bool isMobile) {
    final nomeEvento = (widget.treino['event_name'] ?? 'Campeonato').toString();
    final data = (widget.treino['event_date'] ?? '').toString();
    final hora = (widget.treino['event_time'] ?? '').toString();
    final positivos = _totalEquipeSet(positivos: true);
    final erros = _totalEquipeSet(positivos: false);

    return Container(
      padding: EdgeInsets.all(isMobile ? 16 : 18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [olympusBlue, olympusLightBlue],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: olympusBlue.withOpacity(0.18),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.groups_rounded, color: olympusGold, size: 28),
          const SizedBox(height: 12),
          Text(
            'Avaliação por fundamento',
            style: TextStyle(
              color: Colors.white,
              fontSize: isMobile ? 20 : 22,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            nomeEvento,
            style: TextStyle(
              color: Colors.white.withOpacity(0.86),
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
          if (data.isNotEmpty || hora.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(
              '$data • $hora',
              style: TextStyle(
                color: Colors.white.withOpacity(0.74),
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              _buildHeaderStat(
                label: 'Atletas',
                value: '${_atletas.length}',
                icon: Icons.how_to_reg_rounded,
                color: olympusGold,
              ),
              const SizedBox(width: 8),
              _buildHeaderStat(
                label: 'Ações',
                value: '$positivos',
                icon: Icons.trending_up_rounded,
                color: olympusSuccess,
              ),
              const SizedBox(width: 8),
              _buildHeaderStat(
                label: 'Erros',
                value: '$erros',
                icon: Icons.error_outline_rounded,
                color: Colors.red.shade200,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderStat({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.11),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withOpacity(0.16)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(height: 5),
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w900,
              ),
            ),
            Text(
              label,
              style: TextStyle(
                color: Colors.white.withOpacity(0.76),
                fontSize: 10,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildToolbar(bool isMobile) {
    return Container(
      padding: EdgeInsets.all(isMobile ? 12 : 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: olympusBorder),
      ),
      child: Column(
        children: [
          TextField(
            controller: _buscaController,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search_rounded),
              labelText: 'Buscar atleta',
              border: const OutlineInputBorder(),
              suffixIcon: _buscaController.text.trim().isEmpty
                  ? null
                  : IconButton(
                      onPressed: () {
                        _buscaController.clear();
                        setState(() {});
                      },
                      icon: const Icon(Icons.clear_rounded),
                    ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: FilterChip(
                  label: const Text('Somente com lançamentos'),
                  selected: _mostrarSomenteComLancamentos,
                  onSelected: (value) {
                    setState(() {
                      _mostrarSomenteComLancamentos = value;
                    });
                  },
                  selectedColor: olympusBlue.withOpacity(0.14),
                  checkmarkColor: olympusBlue,
                  labelStyle: const TextStyle(
                    color: olympusBlue,
                    fontWeight: FontWeight.w800,
                  ),
                  side: const BorderSide(color: olympusBorder),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                tooltip: 'Copiar resumo',
                onPressed: _copiarResumoAtletas,
                icon: const Icon(Icons.copy_rounded),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMetricRow({
    required String athleteId,
    required Map<String, dynamic> scout,
    required ChampionshipAthleteFoundationMetric metric,
    required bool isMobile,
  }) {
    final positive = _getInt(scout, metric.positiveField);
    final negative = _getInt(scout, metric.negativeField);

    Widget counterButton({
      required IconData icon,
      required Color color,
      required VoidCallback onTap,
    }) {
      return InkWell(
        onTap: _saving ? null : onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: isMobile ? 30 : 34,
          height: isMobile ? 30 : 34,
          decoration: BoxDecoration(
            color: color.withOpacity(0.10),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withOpacity(0.22)),
          ),
          child: Icon(icon, color: color, size: 17),
        ),
      );
    }

    Widget valuePill({
      required String label,
      required int value,
      required Color color,
    }) {
      return Container(
        constraints: BoxConstraints(minWidth: isMobile ? 38 : 44),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.18)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$value',
              style: TextStyle(
                color: color,
                fontSize: isMobile ? 14 : 15,
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
                color: color,
                fontSize: 8.5,
                fontWeight: FontWeight.w800,
                height: 1,
              ),
            ),
          ],
        ),
      );
    }

    Widget counterLine({
      required String label,
      required int value,
      required String valueLabel,
      required Color color,
      required String field,
    }) {
      return Row(
        children: [
          SizedBox(
            width: isMobile ? 44 : 56,
            child: Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: isMobile ? 10.5 : 11.5,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          counterButton(
            icon: Icons.remove_rounded,
            color: color,
            onTap: () => _alterarContador(athleteId, field, -1),
          ),
          const SizedBox(width: 6),
          valuePill(label: valueLabel, value: value, color: color),
          const SizedBox(width: 6),
          counterButton(
            icon: Icons.add_rounded,
            color: color,
            onTap: () => _alterarContador(athleteId, field, 1),
          ),
        ],
      );
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 10 : 12,
        vertical: isMobile ? 9 : 10,
      ),
      decoration: BoxDecoration(
        color: olympusBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: olympusBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: isMobile ? 34 : 38,
            height: isMobile ? 34 : 38,
            decoration: BoxDecoration(
              color: olympusBlue.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(metric.icon, color: olympusBlue, size: 19),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              metric.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: olympusBlue,
                fontSize: isMobile ? 12.5 : 13.5,
                fontWeight: FontWeight.w900,
                height: 1.05,
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              counterLine(
                label: 'Ação',
                value: positive,
                valueLabel: metric.positiveLabel,
                color: olympusSuccess,
                field: metric.positiveField,
              ),
              const SizedBox(height: 7),
              counterLine(
                label: 'Erro',
                value: negative,
                valueLabel: metric.negativeLabel,
                color: olympusDanger,
                field: metric.negativeField,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAthleteFoundationCard(
    Map<String, dynamic> atleta,
    bool isMobile,
  ) {
    final athleteId = (atleta['user_id'] ?? '').toString();
    final nome = (atleta['nome'] ?? 'Atleta').toString();
    final avatarUrl = (atleta['avatar_url'] ?? '').toString();
    final scout = _getScout(athleteId);
    final positivosSet = _totalPositivo(scout);
    final errosSet = _totalErro(scout);
    final positivosTotal = _totalPositivoTodosSets(athleteId);
    final errosTotal = _totalErroTodosSets(athleteId);
    final nota = _notaAutomatica(scout);
    final conceito = _conceito(nota);
    final controller = _getObservationController(athleteId);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: olympusBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.035),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ExpansionTile(
        tilePadding: EdgeInsets.symmetric(
          horizontal: isMobile ? 12 : 14,
          vertical: 5,
        ),
        childrenPadding: EdgeInsets.fromLTRB(
          isMobile ? 12 : 14,
          0,
          isMobile ? 12 : 14,
          isMobile ? 12 : 14,
        ),
        leading: CircleAvatar(
          radius: isMobile ? 22 : 24,
          backgroundColor: olympusGold.withOpacity(0.18),
          backgroundImage:
              avatarUrl.trim().isNotEmpty ? NetworkImage(avatarUrl) : null,
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
        title: Text(
          nome,
          style: TextStyle(
            color: olympusText,
            fontSize: isMobile ? 14 : 15,
            fontWeight: FontWeight.w900,
          ),
        ),
        subtitle: Text(
          'Set $_setSelecionado • +$positivosSet ações • $errosSet erros • Nota $nota ($conceito)',
          style: TextStyle(
            color: nota >= 7
                ? olympusSuccess
                : nota > 0
                    ? olympusWarning
                    : olympusMuted,
            fontSize: isMobile ? 11 : 12,
            fontWeight: FontWeight.w800,
          ),
        ),
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: olympusBlue.withOpacity(0.06),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: olympusBlue.withOpacity(0.10)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Consolidado: +$positivosTotal ações • $errosTotal erros',
                    style: const TextStyle(
                      color: olympusBlue,
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: olympusGold.withOpacity(0.16),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    'Set $_setSelecionado',
                    style: const TextStyle(
                      color: olympusBlue,
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
          ),
          ..._metrics.map(
            (metric) => _buildMetricRow(
              athleteId: athleteId,
              scout: scout,
              metric: metric,
              isMobile: isMobile,
            ),
          ),
          const SizedBox(height: 4),
          TextField(
            controller: controller,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Observação do atleta neste set',
              hintText: 'Ex: melhorou recepção, precisa ajustar saque.',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _saving ? null : () => _salvarObservacao(athleteId),
              icon: const Icon(Icons.save_outlined, size: 16),
              label: const Text('Salvar observação'),
              style: ElevatedButton.styleFrom(
                backgroundColor: olympusBlue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = _isMobile(context);
    final atletas = _atletasFiltrados();

    return Scaffold(
      backgroundColor: olympusBg,
      appBar: AppBar(
        title: const Text('Avaliar atletas'),
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
            onPressed: _loading ? null : _carregarAtletasEScout,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
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
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _carregarAtletasEScout,
                  child: ListView(
                    padding: EdgeInsets.all(isMobile ? 12 : 16),
                    children: [
                      _buildHeader(isMobile),
                      const SizedBox(height: 12),
                      _buildSetSelector(isMobile),
                      const SizedBox(height: 12),
                      _buildToolbar(isMobile),
                      const SizedBox(height: 12),
                      if (_atletas.isEmpty)
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: olympusBorder),
                          ),
                          child: const Text(
                            'Nenhum atleta com check-in encontrado neste jogo.',
                            style: TextStyle(
                              color: olympusMuted,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        )
                      else if (atletas.isEmpty)
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: olympusBorder),
                          ),
                          child: const Text(
                            'Nenhum atleta encontrado com os filtros atuais.',
                            style: TextStyle(
                              color: olympusMuted,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        )
                      else
                        ...atletas.map(
                          (atleta) =>
                              _buildAthleteFoundationCard(atleta, isMobile),
                        ),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
    );
  }
}
