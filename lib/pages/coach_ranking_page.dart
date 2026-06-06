import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'athlete_training_history_page.dart';
import '../services/permission_service.dart';

class CoachRankingPage extends StatefulWidget {
  const CoachRankingPage({super.key});

  @override
  State<CoachRankingPage> createState() => _CoachRankingPageState();
}

class _CoachRankingPageState extends State<CoachRankingPage> {
  final SupabaseClient _supabase = Supabase.instance.client;
  final PermissionService _permissionService = PermissionService();

  static const Color olympusBlue = Color(0xFF1E3A5F);
  static const Color olympusGold = Color(0xFFD4AF37);

  bool _loading = true;
  bool _savingWeights = false;
  String? _error;

  List<Map<String, dynamic>> _ranking = [];

  String _periodo = 'mes';
  String _generoFiltro = 'todos';
  String _fundamentoFiltro = 'todos';
  String _coachTeamGender = 'ambos';
  bool _showGenderFilter = true;

  int _pesoDestaque = 2;
  int _pesoAtencao = -1;
  int _pesoPresenca = 1;
  int _pesoFalta = -2;

  @override
  void initState() {
    super.initState();
    _carregarTudo();
  }

  bool _isMobile(BuildContext context) =>
      MediaQuery.of(context).size.width < 600;

  DateTime? _getPeriodoInicio() {
    final now = DateTime.now();
    switch (_periodo) {
      case 'semana':
        return now.subtract(const Duration(days: 7));
      case 'mes':
        return DateTime(now.year, now.month, 1);
      case 'geral':
        return null;
      default:
        return null;
    }
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

  String _normalizarGenero(dynamic value) {
    final raw = (value ?? '').toString().trim().toLowerCase();
    if (raw.contains('fem') || raw == 'f' || raw == 'female') return 'feminino';
    if (raw.contains('masc') || raw == 'm' || raw == 'male') return 'masculino';
    return 'outro';
  }

  String _generoLabel(String value) {
    switch (value) {
      case 'feminino':
        return 'Feminino';
      case 'masculino':
        return 'Masculino';
      case 'todos':
        return 'Todos';
      default:
        return 'Outro';
    }
  }

  String _normalizarFundamento(dynamic value) {
    final raw = (value ?? '').toString().trim().toLowerCase();
    if (raw.contains('saque')) return 'saque';
    if (raw.contains('recep')) return 'recepcao';
    if (raw.contains('ataque')) return 'ataque';
    if (raw.contains('defesa')) return 'defesa';
    if (raw.contains('bloqueio')) return 'bloqueio';
    if (raw.contains('fis') ||
        raw.contains('fís') ||
        raw.contains('condicionamento')) return 'fisico';
    return raw.isEmpty ? 'sem_fundamento' : raw;
  }

  String _fundamentoLabel(String value) {
    switch (value) {
      case 'saque':
        return 'Saque';
      case 'recepcao':
        return 'Recepção';
      case 'ataque':
        return 'Ataque';
      case 'defesa':
        return 'Defesa';
      case 'bloqueio':
        return 'Bloqueio';
      case 'fisico':
        return 'Físico';
      case 'todos':
        return 'Todos';
      default:
        return 'Sem fundamento';
    }
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
      final d = int.tryParse(parts[0]);
      final m = int.tryParse(parts[1]);
      final y = int.tryParse(parts[2]);
      if (d != null && m != null && y != null) return DateTime(y, m, d);
    }
    return null;
  }

  bool _dentroDoPeriodo(dynamic createdAt, DateTime? inicio) {
    if (inicio == null) return true;
    final parsed = _parseDate(createdAt);
    if (parsed == null) return false;
    final local = parsed.toLocal();
    return local.isAfter(inicio) || local.isAtSameMomentAs(inicio);
  }

  Future<void> _carregarTudo() async {
    await _carregarCoachTeamGender();
    await _carregarPesos();
    await _carregarRanking();
  }

  String _normalizarCoachTeamGender(dynamic value) {
    final raw = (value ?? '').toString().trim().toLowerCase();

    if (raw.contains('fem') || raw == 'f' || raw == 'female') {
      return 'feminino';
    }

    if (raw.contains('masc') || raw == 'm' || raw == 'male') {
      return 'masculino';
    }

    return 'ambos';
  }

  Future<void> _carregarCoachTeamGender() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    String scope = 'ambos';

    try {
      final profile = await _supabase
          .from('profiles')
          .select('coach_team_gender')
          .eq('id', user.id)
          .maybeSingle();

      scope = _normalizarCoachTeamGender(profile?['coach_team_gender']);
    } catch (_) {
      try {
        final profile = await _supabase
            .from('profiles')
            .select('team_scope')
            .eq('id', user.id)
            .maybeSingle();

        scope = _normalizarCoachTeamGender(profile?['team_scope']);
      } catch (_) {
        scope = 'ambos';
      }
    }

    if (!mounted) return;

    setState(() {
      _coachTeamGender = scope;
      _showGenderFilter = scope == 'ambos';

      if (!_showGenderFilter) {
        _generoFiltro = scope;
      } else if (_generoFiltro != 'todos' &&
          _generoFiltro != 'feminino' &&
          _generoFiltro != 'masculino') {
        _generoFiltro = 'todos';
      }
    });
  }

  Future<void> _carregarPesos() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;

      final rows = await _supabase
          .from('ranking_settings')
          .select('destaque_score, atencao_score, presenca_score, falta_score')
          .eq('coach_id', user.id)
          .limit(1);

      final list = List<Map<String, dynamic>>.from(rows as List);
      if (list.isEmpty) return;

      final row = list.first;
      _pesoDestaque = (row['destaque_score'] as num?)?.toInt() ?? _pesoDestaque;
      _pesoAtencao = (row['atencao_score'] as num?)?.toInt() ?? _pesoAtencao;
      _pesoPresenca = (row['presenca_score'] as num?)?.toInt() ?? _pesoPresenca;
      _pesoFalta = (row['falta_score'] as num?)?.toInt() ?? _pesoFalta;
    } catch (_) {
      // Se a tabela ranking_settings ainda não existir, usa os pesos padrão.
    }
  }

  Future<void> _salvarPesos() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    setState(() => _savingWeights = true);

    try {
      final existingRows = await _supabase
          .from('ranking_settings')
          .select('id')
          .eq('coach_id', user.id)
          .limit(1);

      final existingList =
          List<Map<String, dynamic>>.from(existingRows as List);

      final payload = {
        'coach_id': user.id,
        'destaque_score': _pesoDestaque,
        'atencao_score': _pesoAtencao,
        'presenca_score': _pesoPresenca,
        'falta_score': _pesoFalta,
      };

      if (existingList.isEmpty) {
        await _supabase.from('ranking_settings').insert(payload);
      } else {
        await _supabase
            .from('ranking_settings')
            .update(payload)
            .eq('coach_id', user.id);
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pesos salvos com sucesso')),
      );
      await _carregarRanking();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível salvar os pesos: $e')),
      );
      await _carregarRanking();
    } finally {
      if (mounted) setState(() => _savingWeights = false);
    }
  }

  int _pontosAvaliacao(Map<String, dynamic> row) {
    final tipo = (row['tipo'] ?? '').toString().trim().toLowerCase();
    final dbScore = row['score'];
    if (dbScore is int && dbScore != 0) return dbScore;
    if (dbScore is num && dbScore.toInt() != 0) return dbScore.toInt();
    if (tipo == 'destaque') return _pesoDestaque;
    if (tipo == 'atencao' || tipo == 'atenção') return _pesoAtencao;
    return 0;
  }

  Future<List<Map<String, dynamic>>> _safeSelect(
      String table, String columns) async {
    try {
      final rows = await _supabase.from(table).select(columns);
      return List<Map<String, dynamic>>.from(rows as List);
    } catch (_) {
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> _carregarPerfisApenasAtletas(
    Set<String> idsComHistorico,
  ) async {
    final user = _supabase.auth.currentUser;
    final currentUserId = user?.id ?? '';

    Future<List<Map<String, dynamic>>> tryProfileFilter(
      String column,
      dynamic value,
    ) async {
      try {
        final rows = await _supabase
            .from('profiles')
            .select('id, full_name, avatar_url, gender, is_active, $column')
            .eq(column, value);

        return List<Map<String, dynamic>>.from(rows as List).where((profile) {
          final id = (profile['id'] ?? '').toString();
          final isActive = profile['is_active'] != false;
          return id.isNotEmpty && id != currentUserId && isActive;
        }).toList();
      } catch (_) {
        return [];
      }
    }

    final attempts = <List<Map<String, dynamic>>>[
      await tryProfileFilter('role', 'athlete'),
      await tryProfileFilter('role', 'atleta'),
      await tryProfileFilter('user_role', 'athlete'),
      await tryProfileFilter('user_role', 'atleta'),
      await tryProfileFilter('user_type', 'athlete'),
      await tryProfileFilter('user_type', 'atleta'),
      await tryProfileFilter('profile_type', 'athlete'),
      await tryProfileFilter('profile_type', 'atleta'),
      await tryProfileFilter('type', 'athlete'),
      await tryProfileFilter('type', 'atleta'),
      await tryProfileFilter('account_type', 'athlete'),
      await tryProfileFilter('account_type', 'atleta'),
      await tryProfileFilter('is_athlete', true),
    ];

    for (final rows in attempts) {
      if (rows.isNotEmpty) return rows;
    }

    final allProfiles = await _safeSelect(
      'profiles',
      'id, full_name, avatar_url, gender, is_active',
    );

    return allProfiles.where((profile) {
      final id = (profile['id'] ?? '').toString();
      final isActive = profile['is_active'] != false;
      if (id.isEmpty || id == currentUserId || !isActive) return false;
      if (idsComHistorico.isEmpty) return false;
      return idsComHistorico.contains(id);
    }).toList();
  }

  Future<void> _carregarRanking() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final inicio = _getPeriodoInicio();

      final evaluations = await _safeSelect(
        'training_evaluations',
        'athlete_id, tipo, score, fundamento, motivo, observacao, created_at',
      );
      final checkins = await _safeSelect(
        'checkins',
        'user_id, event_id, check_in_status, created_at',
      );

      final idsComHistorico = <String>{};
      for (final row in evaluations) {
        final id = (row['athlete_id'] ?? '').toString();
        if (id.isNotEmpty) idsComHistorico.add(id);
      }
      for (final row in checkins) {
        final id = (row['user_id'] ?? '').toString();
        if (id.isNotEmpty) idsComHistorico.add(id);
      }

      final visibleRankingIds =
          (await _permissionService.getVisibleUserIdsForPage('ranking'))
              .toSet();

      if (visibleRankingIds.isEmpty) {
        if (!mounted) return;
        setState(() {
          _ranking = [];
          _loading = false;
        });
        return;
      }

      final profiles = (await _carregarPerfisApenasAtletas(idsComHistorico))
          .where((profile) {
        final id = (profile['id'] ?? '').toString();
        return id.isNotEmpty && visibleRankingIds.contains(id);
      }).toList();

      final aggregated = <String, Map<String, dynamic>>{};

      for (final profile in profiles) {
        final id = (profile['id'] ?? '').toString();
        if (id.isEmpty) continue;

        final genero = _normalizarGenero(profile['gender']);
        if (_generoFiltro != 'todos' && genero != _generoFiltro) continue;

        aggregated[id] = {
          'athlete_id': id,
          'nome': (profile['full_name'] ?? 'Atleta').toString(),
          'avatar_url': (profile['avatar_url'] ?? '').toString(),
          'gender': genero,
          'score': 0,
          'destaques': 0,
          'atencoes': 0,
          'avaliacoes': 0,
          'presencas': 0,
          'faltas': 0,
          'alertas': <String>[],
          'ultimas_avaliacoes': <Map<String, dynamic>>[],
          'ultima_avaliacao': null,
        };
      }

      for (final row in evaluations) {
        if (!_dentroDoPeriodo(row['created_at'], inicio)) continue;
        if (_fundamentoFiltro != 'todos' &&
            _normalizarFundamento(row['fundamento']) != _fundamentoFiltro)
          continue;

        final athleteId = (row['athlete_id'] ?? '').toString();
        if (!aggregated.containsKey(athleteId)) continue;

        final tipo = (row['tipo'] ?? '').toString().trim().toLowerCase();
        final pontos = _pontosAvaliacao(row);

        aggregated[athleteId]!['score'] =
            (aggregated[athleteId]!['score'] as int) + pontos;
        aggregated[athleteId]!['avaliacoes'] =
            (aggregated[athleteId]!['avaliacoes'] as int) + 1;

        final ultimas = aggregated[athleteId]!['ultimas_avaliacoes']
            as List<Map<String, dynamic>>;
        ultimas.add(row);

        final createdAt = _parseDate(row['created_at']);
        final atual = aggregated[athleteId]!['ultima_avaliacao'] as DateTime?;
        if (createdAt != null && (atual == null || createdAt.isAfter(atual))) {
          aggregated[athleteId]!['ultima_avaliacao'] = createdAt;
        }

        if (tipo == 'destaque') {
          aggregated[athleteId]!['destaques'] =
              (aggregated[athleteId]!['destaques'] as int) + 1;
        } else if (tipo == 'atencao' || tipo == 'atenção') {
          aggregated[athleteId]!['atencoes'] =
              (aggregated[athleteId]!['atencoes'] as int) + 1;
        }
      }

      for (final row in checkins) {
        if (!_dentroDoPeriodo(row['created_at'], inicio)) continue;
        final userId = (row['user_id'] ?? '').toString();
        if (!aggregated.containsKey(userId)) continue;
        if (!_isCheckinRealizado(row['check_in_status'])) continue;

        aggregated[userId]!['presencas'] =
            (aggregated[userId]!['presencas'] as int) + 1;
        aggregated[userId]!['score'] =
            (aggregated[userId]!['score'] as int) + _pesoPresenca;
      }

      await _aplicarFaltas(aggregated, inicio);
      _aplicarAlertas(aggregated);

      final ranking = aggregated.values.toList()
        ..sort((a, b) {
          final scoreCompare = (b['score'] as int).compareTo(a['score'] as int);
          if (scoreCompare != 0) return scoreCompare;
          final destaqueCompare =
              (b['destaques'] as int).compareTo(a['destaques'] as int);
          if (destaqueCompare != 0) return destaqueCompare;
          final presencaCompare =
              (b['presencas'] as int).compareTo(a['presencas'] as int);
          if (presencaCompare != 0) return presencaCompare;
          return a['nome'].toString().compareTo(b['nome'].toString());
        });

      if (!mounted) return;
      setState(() {
        _ranking = ranking;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Erro ao carregar ranking: $e';
        _loading = false;
      });
    }
  }

  Future<void> _aplicarFaltas(
      Map<String, Map<String, dynamic>> aggregated, DateTime? inicio) async {
    try {
      final events = await _safeSelect('events', 'id, event_type, event_date');
      final treinoIds = events
          .where((e) {
            final type = (e['event_type'] ?? '').toString().toLowerCase();
            if (type != 'treino') return false;
            return _dentroDoPeriodo(e['event_date'], inicio);
          })
          .map((e) => (e['id'] ?? '').toString())
          .where((id) => id.isNotEmpty)
          .toList();

      if (treinoIds.isEmpty || aggregated.isEmpty) return;

      final convocations = await _supabase
          .from('convocations')
          .select('event_id, user_id, status')
          .inFilter('event_id', treinoIds)
          .eq('status', 'accepted');

      final checkins = await _supabase
          .from('checkins')
          .select('event_id, user_id, check_in_status')
          .inFilter('event_id', treinoIds);

      final checkedIn = <String>{};
      for (final row in checkins) {
        if (!_isCheckinRealizado(row['check_in_status'])) continue;
        final eventId = (row['event_id'] ?? '').toString();
        final userId = (row['user_id'] ?? '').toString();
        if (eventId.isNotEmpty && userId.isNotEmpty)
          checkedIn.add('$eventId|$userId');
      }

      for (final row in convocations) {
        final eventId = (row['event_id'] ?? '').toString();
        final userId = (row['user_id'] ?? '').toString();
        if (!aggregated.containsKey(userId)) continue;
        if (checkedIn.contains('$eventId|$userId')) continue;

        aggregated[userId]!['faltas'] =
            (aggregated[userId]!['faltas'] as int) + 1;
        aggregated[userId]!['score'] =
            (aggregated[userId]!['score'] as int) + _pesoFalta;
      }
    } catch (_) {
      // Se alguma tabela ou policy bloquear, o ranking continua sem faltas.
    }
  }

  void _aplicarAlertas(Map<String, Map<String, dynamic>> aggregated) {
    final now = DateTime.now();

    for (final item in aggregated.values) {
      final alertas = item['alertas'] as List<String>;
      final ultimas = item['ultimas_avaliacoes'] as List<Map<String, dynamic>>;

      ultimas.sort((a, b) {
        final ad = _parseDate(a['created_at']) ?? DateTime(1900);
        final bd = _parseDate(b['created_at']) ?? DateTime(1900);
        return bd.compareTo(ad);
      });

      final ultimas3 = ultimas.take(3).toList();
      if (ultimas3.length == 3 &&
          ultimas3.every((e) {
            final tipo = (e['tipo'] ?? '').toString().toLowerCase();
            return tipo == 'atencao' || tipo == 'atenção';
          })) {
        alertas.add('3 pontos de atenção seguidos');
      }

      final ultimaAvaliacao = item['ultima_avaliacao'] as DateTime?;
      if (ultimaAvaliacao == null) {
        alertas.add('Sem avaliação registrada');
      } else if (now.difference(ultimaAvaliacao.toLocal()).inDays >= 30) {
        alertas.add('Sem avaliação há 30 dias');
      }

      final presencas = item['presencas'] as int;
      final faltas = item['faltas'] as int;
      final total = presencas + faltas;
      if (total >= 3 && presencas / total < 0.6) {
        alertas.add('Presença baixa');
      }
    }
  }

  Future<void> _abrirConfigPesos() async {
    int destaque = _pesoDestaque;
    int atencao = _pesoAtencao;
    int presenca = _pesoPresenca;
    int falta = _pesoFalta;

    final result = await showModalBottomSheet<Map<String, int>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            Widget pesoRow(
                String label, int value, ValueChanged<int> onChanged) {
              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF4F7FB),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFE4EDF5)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(label,
                          style: const TextStyle(
                              color: olympusBlue, fontWeight: FontWeight.w800)),
                    ),
                    IconButton(
                        onPressed: () => onChanged(value - 1),
                        icon: const Icon(Icons.remove_circle_outline)),
                    SizedBox(
                      width: 42,
                      child: Text('$value',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              color: olympusBlue,
                              fontWeight: FontWeight.w900,
                              fontSize: 16)),
                    ),
                    IconButton(
                        onPressed: () => onChanged(value + 1),
                        icon: const Icon(Icons.add_circle_outline)),
                  ],
                ),
              );
            }

            return Container(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
              decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius:
                      BorderRadius.vertical(top: Radius.circular(22))),
              child: SafeArea(
                top: false,
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
                                borderRadius: BorderRadius.circular(999)))),
                    const SizedBox(height: 16),
                    const Text('Configurar pesos do ranking',
                        style: TextStyle(
                            color: olympusBlue,
                            fontSize: 18,
                            fontWeight: FontWeight.w900)),
                    const SizedBox(height: 12),
                    pesoRow('Destaque', destaque,
                        (v) => setModalState(() => destaque = v)),
                    pesoRow('Ponto de atenção', atencao,
                        (v) => setModalState(() => atencao = v)),
                    pesoRow('Presença', presenca,
                        (v) => setModalState(() => presenca = v)),
                    pesoRow(
                        'Falta', falta, (v) => setModalState(() => falta = v)),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () => Navigator.pop(context, {
                          'destaque': destaque,
                          'atencao': atencao,
                          'presenca': presenca,
                          'falta': falta
                        }),
                        icon: const Icon(Icons.save_outlined),
                        label: const Text('Salvar pesos'),
                        style: ElevatedButton.styleFrom(
                            backgroundColor: olympusBlue,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14)),
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

    if (result == null) return;

    setState(() {
      _pesoDestaque = result['destaque'] ?? _pesoDestaque;
      _pesoAtencao = result['atencao'] ?? _pesoAtencao;
      _pesoPresenca = result['presenca'] ?? _pesoPresenca;
      _pesoFalta = result['falta'] ?? _pesoFalta;
    });

    await _salvarPesos();
  }

  Widget _buildChip(
      {required String value,
      required String label,
      required String selected,
      required ValueChanged<String> onTap}) {
    final isSelected = value == selected;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) {
        if (isSelected) return;
        onTap(value);
      },
      selectedColor: olympusBlue,
      backgroundColor: Colors.white,
      side:
          BorderSide(color: isSelected ? olympusBlue : const Color(0xFFE4EDF5)),
      labelStyle: TextStyle(
          color: isSelected ? Colors.white : olympusBlue,
          fontWeight: FontWeight.w700,
          fontSize: 12),
    );
  }

  Widget _buildFilterSection(String title, List<Map<String, String>> items,
      String selected, ValueChanged<String> onTap) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: const TextStyle(
                color: olympusBlue, fontSize: 12, fontWeight: FontWeight.w900)),
        const SizedBox(height: 6),
        Wrap(
            spacing: 8,
            runSpacing: 8,
            children: items
                .map((e) => _buildChip(
                    value: e['value']!,
                    label: e['label']!,
                    selected: selected,
                    onTap: onTap))
                .toList()),
      ],
    );
  }

  Widget _buildResumoCard(bool isMobile) {
    return Container(
      padding: EdgeInsets.all(isMobile ? 14 : 16),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFE4EDF5))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                  child: Text('Ranking geral',
                      style: TextStyle(
                          color: olympusBlue,
                          fontSize: 18,
                          fontWeight: FontWeight.w800))),
              IconButton(
                onPressed: _savingWeights ? null : _abrirConfigPesos,
                icon: _savingWeights
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.tune_rounded),
                color: olympusBlue,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
              'Pontuação: destaque = $_pesoDestaque | atenção = $_pesoAtencao | presença = $_pesoPresenca | falta = $_pesoFalta',
              style: const TextStyle(
                  color: Color(0xFF53657B),
                  fontSize: 13,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          _buildFilterSection(
              'Período',
              const [
                {'value': 'semana', 'label': 'Semana'},
                {'value': 'mes', 'label': 'Mês'},
                {'value': 'geral', 'label': 'Geral'},
              ],
              _periodo, (v) {
            setState(() => _periodo = v);
            _carregarRanking();
          }),
          if (_showGenderFilter) ...[
            const SizedBox(height: 12),
            _buildFilterSection(
                'Gênero',
                const [
                  {'value': 'todos', 'label': 'Todos'},
                  {'value': 'feminino', 'label': 'Feminino'},
                  {'value': 'masculino', 'label': 'Masculino'},
                ],
                _generoFiltro, (v) {
              setState(() => _generoFiltro = v);
              _carregarRanking();
            }),
          ] else ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: olympusGold.withOpacity(0.10),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: olympusGold.withOpacity(0.24)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.lock_outline, color: olympusGold, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Ranking filtrado automaticamente para ${_generoLabel(_coachTeamGender)}',
                      style: const TextStyle(
                        color: olympusBlue,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          _buildFilterSection(
              'Fundamento',
              const [
                {'value': 'todos', 'label': 'Todos'},
                {'value': 'saque', 'label': 'Saque'},
                {'value': 'recepcao', 'label': 'Recepção'},
                {'value': 'ataque', 'label': 'Ataque'},
                {'value': 'defesa', 'label': 'Defesa'},
                {'value': 'bloqueio', 'label': 'Bloqueio'},
                {'value': 'fisico', 'label': 'Físico'},
              ],
              _fundamentoFiltro, (v) {
            setState(() => _fundamentoFiltro = v);
            _carregarRanking();
          }),
          const SizedBox(height: 10),
          Text(
              'Atual: ${_getPeriodoLabel()} • ${_generoLabel(_generoFiltro)} • ${_fundamentoLabel(_fundamentoFiltro)}',
              style: const TextStyle(
                  color: Color(0xFF6A7E94),
                  fontSize: 12,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _buildAvatar(String avatarUrl, String nome, int posicao) {
    if (avatarUrl.trim().isNotEmpty) {
      return CircleAvatar(radius: 24, backgroundImage: NetworkImage(avatarUrl));
    }
    return CircleAvatar(
      radius: 24,
      backgroundColor: posicao <= 3
          ? olympusGold.withOpacity(0.18)
          : olympusBlue.withOpacity(0.10),
      child: Text(nome.isNotEmpty ? nome[0].toUpperCase() : '?',
          style:
              const TextStyle(color: olympusBlue, fontWeight: FontWeight.w800)),
    );
  }

  Color _positionColor(int posicao) {
    if (posicao == 1) return const Color(0xFFD4AF37);
    if (posicao == 2) return const Color(0xFF94A3B8);
    if (posicao == 3) return const Color(0xFFB45309);
    return olympusBlue;
  }

  Widget _buildAlertas(List<String> alertas, bool isMobile) {
    if (alertas.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: alertas.take(3).map((alerta) {
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.08),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: Colors.red.withOpacity(0.18))),
            child: Text(alerta,
                style: TextStyle(
                    color: Colors.red.shade700,
                    fontSize: isMobile ? 9.5 : 10.5,
                    fontWeight: FontWeight.w700)),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildTopCard(Map<String, dynamic> item, int index, bool isMobile) {
    final posicao = index + 1;
    final nome = (item['nome'] ?? 'Atleta').toString();
    final avatarUrl = (item['avatar_url'] ?? '').toString();
    final athleteId = (item['athlete_id'] ?? '').toString();
    final color = _positionColor(posicao);
    final alertas = List<String>.from((item['alertas'] as List?) ?? const []);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: athleteId.isEmpty
              ? null
              : () {
                  Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => AthleteTrainingHistoryPage(
                              athleteId: athleteId,
                              athleteName: nome,
                              avatarUrl: avatarUrl)));
                },
          child: Container(
            padding: EdgeInsets.all(isMobile ? 14 : 16),
            decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFFE4EDF5))),
            child: Row(
              children: [
                SizedBox(
                    width: 34,
                    child: Text('$posicao',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: color,
                            fontSize: isMobile ? 20 : 22,
                            fontWeight: FontWeight.w900))),
                const SizedBox(width: 10),
                _buildAvatar(avatarUrl, nome, posicao),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(nome,
                          style: TextStyle(
                              color: olympusBlue,
                              fontSize: isMobile ? 14 : 15,
                              fontWeight: FontWeight.w800)),
                      const SizedBox(height: 4),
                      Text(_generoLabel((item['gender'] ?? 'outro').toString()),
                          style: TextStyle(
                              color: olympusGold,
                              fontSize: isMobile ? 10.5 : 11.5,
                              fontWeight: FontWeight.w800)),
                      const SizedBox(height: 4),
                      Text(
                          'Destaques: ${item['destaques']} • Atenção: ${item['atencoes']} • Avaliações: ${item['avaliacoes']}',
                          style: TextStyle(
                              color: const Color(0xFF6A7E94),
                              fontSize: isMobile ? 10.5 : 11.5,
                              fontWeight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      Text(
                          'Presenças: ${item['presencas']} • Faltas: ${item['faltas']}',
                          style: TextStyle(
                              color: const Color(0xFF94A3B8),
                              fontSize: isMobile ? 10 : 11,
                              fontWeight: FontWeight.w600)),
                      _buildAlertas(alertas, isMobile),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                          color: color.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(999)),
                      child: Text('${item['score']} pts',
                          style: TextStyle(
                              color: color,
                              fontSize: 12,
                              fontWeight: FontWeight.w800)),
                    ),
                    const SizedBox(height: 8),
                    Icon(Icons.chevron_right_rounded,
                        color: Colors.grey.shade500, size: 20),
                  ],
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
    final isMobile = _isMobile(context);

    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FB),
      appBar: AppBar(
        title: const Text('Ranking dos atletas'),
        backgroundColor: olympusBlue,
        foregroundColor: Colors.white,
        actions: [
          IconButton(onPressed: _carregarTudo, icon: const Icon(Icons.refresh))
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _carregarTudo,
        child: ListView(
          padding: EdgeInsets.all(isMobile ? 12 : 16),
          children: [
            _buildResumoCard(isMobile),
            const SizedBox(height: 14),
            if (_loading)
              const Padding(
                  padding: EdgeInsets.all(30),
                  child: Center(child: CircularProgressIndicator()))
            else if (_error != null)
              Container(
                padding: EdgeInsets.all(isMobile ? 14 : 16),
                decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: const Color(0xFFE4EDF5))),
                child: Text(_error!,
                    style: const TextStyle(
                        color: Colors.red, fontWeight: FontWeight.w600)),
              )
            else if (_ranking.isEmpty)
              Container(
                padding: EdgeInsets.all(isMobile ? 14 : 16),
                decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: const Color(0xFFE4EDF5))),
                child: const Text(
                    'Nenhuma atleta visível no ranking para os filtros selecionados. Ative em Gerenciar Permissões > Visível no ranking.',
                    style: TextStyle(
                        color: Color(0xFF53657B), fontWeight: FontWeight.w600)),
              )
            else
              ...List.generate(_ranking.length,
                  (index) => _buildTopCard(_ranking[index], index, isMobile)),
          ],
        ),
      ),
    );
  }
}
