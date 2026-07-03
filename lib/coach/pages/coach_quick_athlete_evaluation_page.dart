import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/permission_service.dart';

class CoachQuickAthleteEvaluationPage extends StatefulWidget {
  const CoachQuickAthleteEvaluationPage({
    super.key,
    required this.treino,
  });

  final Map<String, dynamic> treino;

  @override
  State<CoachQuickAthleteEvaluationPage> createState() =>
      _CoachQuickAthleteEvaluationPageState();
}

class _CoachQuickAthleteEvaluationPageState
    extends State<CoachQuickAthleteEvaluationPage> {
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
  final PermissionService _permissionService = PermissionService();

  bool _loadingAthletes = true;
  String? _athletesError;

  List<Map<String, dynamic>> _atletas = [];

  final List<String> _motivosDestaque = const [
    'Regularidade',
    'Evolução no treino',
    'Liderança / postura',
    'Execução técnica',
    'Intensidade',
    'Tomada de decisão',
    'Comunicação',
    'Consistência',
  ];

  final List<String> _motivosAtencao = const [
    'Baixa regularidade',
    'Erro técnico',
    'Falta de atenção',
    'Tomada de decisão',
    'Intensidade abaixo',
    'Dificuldade no fundamento',
    'Posicionamento',
    'Comunicação',
  ];

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

  final Map<String, Map<String, dynamic>?> _slots = {
    'destaque_1': null,
    'destaque_2': null,
    'atencao_1': null,
    'atencao_2': null,
    'atencao_3': null,
  };

  bool _isMobile(BuildContext context) {
    return MediaQuery.of(context).size.width < 600;
  }

  String _normalizarTipoEvento(dynamic value) {
    final raw = (value ?? '').toString().trim().toLowerCase();

    if (raw.contains('treino')) return 'treino';
    if (raw.contains('campeonato')) return 'campeonato';
    if (raw.contains('liga')) return 'liga';

    return raw;
  }

  String _labelTipoEvento(dynamic value) {
    final tipo = _normalizarTipoEvento(value);

    switch (tipo) {
      case 'treino':
        return 'treino';
      case 'campeonato':
        return 'campeonato';
      case 'liga':
        return 'liga';
      default:
        return tipo.isEmpty ? 'evento' : tipo;
    }
  }

  String get _eventoLabel => _labelTipoEvento(
      widget.treino['normalized_event_type'] ?? widget.treino['event_type']);

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

  @override
  void initState() {
    super.initState();
    _carregarAtletasComCheckin();
  }

  Future<void> _carregarAvaliacoesSalvas() async {
    try {
      final eventId = (widget.treino['id'] ?? '').toString();
      if (eventId.isEmpty) return;

      final rows = await _supabase
          .from('training_evaluations')
          .select('slot, athlete_id, tipo, motivo, fundamento, observacao')
          .eq('event_id', eventId);

      if (!mounted) return;

      setState(() {
        for (final row in rows) {
          final slot = (row['slot'] ?? '').toString();
          if (!_slots.containsKey(slot)) continue;

          final athleteId = (row['athlete_id'] ?? '').toString();
          Map<String, dynamic>? atletaSelecionado;
          for (final atleta in _atletas) {
            if ((atleta['user_id'] ?? '').toString() == athleteId) {
              atletaSelecionado = Map<String, dynamic>.from(atleta);
              break;
            }
          }

          _slots[slot] = {
            'user_id': athleteId,
            'nome': atletaSelecionado?['nome'] ?? 'Atleta',
            'avatar_url': atletaSelecionado?['avatar_url'] ?? '',
            'motivo': (row['motivo'] ?? '').toString(),
            'fundamento': (row['fundamento'] ?? '').toString(),
            'observacao': (row['observacao'] ?? '').toString(),
          };
        }
      });
    } catch (e) {
      debugPrint('Erro ao carregar avaliações salvas: $e');
    }
  }

  String _tipoFromSlot(String slotKey) {
    return slotKey.startsWith('destaque_') ? 'destaque' : 'atencao';
  }

  Future<void> _salvarSlotNoBanco(String slotKey) async {
    final user = _supabase.auth.currentUser;
    if (user == null) {
      throw Exception('Usuário não autenticado');
    }

    final eventId = (widget.treino['id'] ?? '').toString();
    if (eventId.isEmpty) {
      throw Exception('Evento inválido');
    }

    final slot = _slots[slotKey];

    await _supabase
        .from('training_evaluations')
        .delete()
        .eq('event_id', eventId)
        .eq('coach_id', user.id)
        .eq('slot', slotKey);

    if (slot == null) return;

    await _supabase.from('training_evaluations').insert({
      'event_id': eventId,
      'coach_id': user.id,
      'athlete_id': slot['user_id'],
      'tipo': _tipoFromSlot(slotKey),
      'slot': slotKey,
      'motivo': slot['motivo'],
      'fundamento': slot['fundamento'],
      'observacao': slot['observacao'],
    });
  }

  Future<void> _carregarAtletasComCheckin() async {
    setState(() {
      _loadingAthletes = true;
      _athletesError = null;
    });

    try {
      final eventId = (widget.treino['id'] ?? '').toString();
      if (eventId.isEmpty) {
        setState(() {
          _loadingAthletes = false;
          _athletesError = 'Evento inválido.';
        });
        return;
      }

      final response = await _supabase.rpc(
        'get_checked_in_athletes_for_event',
        params: {'p_event_id': eventId},
      );

      final rpcRows = List<Map<String, dynamic>>.from(response as List);

      final visibleEvaluationIds =
          await _permissionService.getVisibleUserIdsForPage('avaliacoes');

      final userIds = rpcRows
          .map((row) => (row['user_id'] ?? '').toString())
          .where((id) => id.isNotEmpty && visibleEvaluationIds.contains(id))
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
            return userId.isNotEmpty && visibleEvaluationIds.contains(userId);
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

      if (!mounted) return;
      setState(() {
        _atletas = atletas;
        _loadingAthletes = false;
      });

      await _carregarAvaliacoesSalvas();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingAthletes = false;
        _athletesError = 'Erro ao carregar atletas com check-in: $e';
      });
    }
  }

  bool _isSlotDestaque(String slotKey) => slotKey.startsWith('destaque_');

  bool _atletaJaSelecionado(String userId, String slotAtual) {
    for (final entry in _slots.entries) {
      if (entry.key == slotAtual) continue;
      final atleta = entry.value;
      if (atleta != null && (atleta['user_id'] ?? '').toString() == userId) {
        return true;
      }
    }
    return false;
  }

  String _getSlotTitle(String slotKey) {
    switch (slotKey) {
      case 'destaque_1':
        return 'Destaque 1';
      case 'destaque_2':
        return 'Destaque 2';
      case 'atencao_1':
        return 'Ponto de atenção 1';
      case 'atencao_2':
        return 'Ponto de atenção 2';
      case 'atencao_3':
        return 'Ponto de atenção 3';
      default:
        return 'Slot';
    }
  }

  Future<void> _selecionarAtletaParaSlot(String slotKey) async {
    if (_loadingAthletes) return;

    if (_athletesError != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_athletesError!)),
      );
      return;
    }

    if (_atletas.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Nenhum atleta com check-in disponível neste $_eventoLabel.'),
        ),
      );
      return;
    }

    Map<String, dynamic>? selecionado = _slots[slotKey];
    String? motivo = selecionado?['motivo']?.toString();
    String? fundamento = selecionado?['fundamento']?.toString();
    final observacaoController = TextEditingController(
      text: selecionado?['observacao']?.toString() ?? '',
    );

    final motivos =
        _isSlotDestaque(slotKey) ? _motivosDestaque : _motivosAtencao;

    final resultado = await showModalBottomSheet<Map<String, dynamic>?>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final disponiveis = _atletas.where((atleta) {
              final userId = (atleta['user_id'] ?? '').toString();
              if (selecionado != null &&
                  (selecionado!['user_id'] ?? '').toString() == userId) {
                return true;
              }
              return !_atletaJaSelecionado(userId, slotKey);
            }).toList();

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
                          _getSlotTitle(slotKey),
                          style: const TextStyle(
                            color: olympusBlue,
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Selecione um atleta que fez check-in.',
                          style: TextStyle(
                            color: Color(0xFF53657B),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 16),
                        DropdownButtonFormField<String>(
                          value: selecionado?['user_id']?.toString(),
                          decoration: const InputDecoration(
                            labelText: 'Atleta',
                          ),
                          items: disponiveis.map((atleta) {
                            return DropdownMenuItem<String>(
                              value: (atleta['user_id'] ?? '').toString(),
                              child:
                                  Text((atleta['nome'] ?? 'Atleta').toString()),
                            );
                          }).toList(),
                          onChanged: (value) {
                            setModalState(() {
                              if (value == null) {
                                selecionado = null;
                              } else {
                                selecionado = disponiveis.firstWhere(
                                  (a) =>
                                      (a['user_id'] ?? '').toString() == value,
                                );
                              }
                            });
                          },
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          value: motivo,
                          decoration: InputDecoration(
                            labelText: _isSlotDestaque(slotKey)
                                ? 'Por que foi destaque?'
                                : 'Ponto de atenção',
                          ),
                          items: motivos.map((item) {
                            return DropdownMenuItem<String>(
                              value: item,
                              child: Text(item),
                            );
                          }).toList(),
                          onChanged: (value) {
                            setModalState(() {
                              motivo = value;
                            });
                          },
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          value: fundamento,
                          decoration: InputDecoration(
                            labelText: _isSlotDestaque(slotKey)
                                ? 'Fundamento em destaque'
                                : 'Fundamento a desenvolver',
                          ),
                          items: _fundamentos.map((item) {
                            return DropdownMenuItem<String>(
                              value: item,
                              child: Text(item),
                            );
                          }).toList(),
                          onChanged: (value) {
                            setModalState(() {
                              fundamento = value;
                            });
                          },
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: observacaoController,
                          maxLines: 3,
                          decoration: InputDecoration(
                            labelText: _isSlotDestaque(slotKey)
                                ? 'Observação do destaque'
                                : 'Observação do técnico',
                            hintText: _isSlotDestaque(slotKey)
                                ? 'Ex: teve ótima regularidade no saque.'
                                : 'Ex: precisa ajustar tempo de bloqueio.',
                          ),
                        ),
                        const SizedBox(height: 16),
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final isNarrow = constraints.maxWidth < 340;
                            final clearButton = OutlinedButton.icon(
                              onPressed: () => Navigator.pop(context, null),
                              icon: const Icon(Icons.clear),
                              label: const Text('Limpar'),
                            );
                            final saveButton = ElevatedButton(
                              onPressed: () {
                                if (selecionado == null ||
                                    motivo == null ||
                                    motivo!.trim().isEmpty ||
                                    fundamento == null ||
                                    fundamento!.trim().isEmpty) {
                                  return;
                                }

                                Navigator.pop(
                                  context,
                                  {
                                    'user_id': selecionado!['user_id'],
                                    'nome': selecionado!['nome'],
                                    'avatar_url': selecionado!['avatar_url'],
                                    'motivo': motivo,
                                    'fundamento': fundamento,
                                    'observacao':
                                        observacaoController.text.trim(),
                                  },
                                );
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: olympusBlue,
                                foregroundColor: Colors.white,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                              ),
                              child: const Text('Salvar'),
                            );

                            if (isNarrow) {
                              return Column(
                                children: [
                                  SizedBox(
                                      width: double.infinity,
                                      child: clearButton),
                                  const SizedBox(height: 10),
                                  SizedBox(
                                      width: double.infinity,
                                      child: saveButton),
                                ],
                              );
                            }

                            return Row(
                              children: [
                                Expanded(child: clearButton),
                                const SizedBox(width: 10),
                                Expanded(child: saveButton),
                              ],
                            );
                          },
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

    observacaoController.dispose();

    if (!mounted) return;

    try {
      setState(() {
        _slots[slotKey] = resultado;
      });

      await _salvarSlotNoBanco(slotKey);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Avaliação salva com sucesso')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao salvar avaliação: $e')),
      );
    }
  }

  Widget _buildSlotCard({
    required String slotKey,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color accentColor,
    required bool isMobile,
  }) {
    final atleta = _slots[slotKey];
    final nome = atleta == null
        ? 'Selecionar atleta'
        : (atleta['nome'] ?? 'Atleta').toString();
    final avatarUrl = (atleta?['avatar_url'] ?? '').toString();
    final motivo = (atleta?['motivo'] ?? '').toString();
    final fundamento = (atleta?['fundamento'] ?? '').toString();
    final observacao = (atleta?['observacao'] ?? '').toString();

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => _selecionarAtletaParaSlot(slotKey),
          child: Container(
            padding: EdgeInsets.all(isMobile ? 14 : 16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: olympusBorder),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                atleta == null
                    ? Container(
                        width: isMobile ? 42 : 46,
                        height: isMobile ? 42 : 46,
                        decoration: BoxDecoration(
                          color: accentColor.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(icon, color: accentColor),
                      )
                    : CircleAvatar(
                        radius: isMobile ? 21 : 23,
                        backgroundColor: accentColor.withOpacity(0.18),
                        backgroundImage: avatarUrl.trim().isNotEmpty
                            ? NetworkImage(avatarUrl)
                            : null,
                        child: avatarUrl.trim().isEmpty
                            ? Text(
                                nome.isNotEmpty ? nome[0].toUpperCase() : '?',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: olympusBlue,
                                ),
                              )
                            : null,
                      ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: olympusBlue,
                          fontSize: isMobile ? 14 : 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: TextStyle(
                          color: olympusSubtle,
                          fontSize: isMobile ? 11 : 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        nome,
                        style: TextStyle(
                          color: atleta == null ? olympusMuted : accentColor,
                          fontSize: isMobile ? 12 : 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (motivo.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          motivo,
                          style: TextStyle(
                            color: olympusMuted,
                            fontSize: isMobile ? 11 : 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                      if (fundamento.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          fundamento,
                          style: TextStyle(
                            color: olympusSubtle,
                            fontSize: isMobile ? 11 : 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                      if (observacao.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          observacao,
                          style: TextStyle(
                            color: olympusSubtle,
                            fontSize: isMobile ? 11 : 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: Color(0xFF94A3B8),
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
      backgroundColor: olympusBg,
      appBar: AppBar(
        title: Text('Avaliação rápida de $_eventoLabel'),
        backgroundColor: olympusBlue,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            onPressed: _carregarAtletasComCheckin,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ListView(
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
                const SizedBox(height: 8),
                Text(
                  'Somente atletas que fizeram check-in neste $_eventoLabel aparecem na seleção.',
                  style: const TextStyle(
                    color: Color(0xFF6A7E94),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
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
            child: _loadingAthletes
                ? const Padding(
                    padding: EdgeInsets.all(20),
                    child: Center(child: CircularProgressIndicator()),
                  )
                : _athletesError != null
                    ? Padding(
                        padding: const EdgeInsets.all(8),
                        child: Text(
                          _athletesError!,
                          style: const TextStyle(
                            color: olympusDanger,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      )
                    : _atletas.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.all(8),
                            child: Text(
                              'Nenhum atleta visível com check-in realizado neste $_eventoLabel.',
                              style: const TextStyle(
                                color: Color(0xFF53657B),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Destaques e pontos de atenção de $_eventoLabel',
                                style: TextStyle(
                                  color: olympusBlue,
                                  fontSize: isMobile ? 15 : 16,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Escolha 2 destaques e 3 pontos de atenção com motivo. Treinos, campeonatos e liga ficam separados pelo evento.',
                                style: TextStyle(
                                  color: olympusMuted,
                                  fontSize: isMobile ? 12 : 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 12),
                              _buildSlotCard(
                                slotKey: 'destaque_1',
                                title: 'Destaque 1',
                                subtitle: 'Melhor desempenho do treino',
                                icon: Icons.star_rounded,
                                accentColor: Colors.green,
                                isMobile: isMobile,
                              ),
                              _buildSlotCard(
                                slotKey: 'destaque_2',
                                title: 'Destaque 2',
                                subtitle: 'Outro nome que mandou bem',
                                icon: Icons.star_half_rounded,
                                accentColor: Colors.green,
                                isMobile: isMobile,
                              ),
                              _buildSlotCard(
                                slotKey: 'atencao_1',
                                title: 'Ponto de atenção 1',
                                subtitle: 'Prioridade de evolução',
                                icon: Icons.warning_amber_rounded,
                                accentColor: Colors.orange,
                                isMobile: isMobile,
                              ),
                              _buildSlotCard(
                                slotKey: 'atencao_2',
                                title: 'Ponto de atenção 2',
                                subtitle: 'Necessita ajuste técnico',
                                icon: Icons.warning_amber_rounded,
                                accentColor: Colors.orange,
                                isMobile: isMobile,
                              ),
                              _buildSlotCard(
                                slotKey: 'atencao_3',
                                title: 'Ponto de atenção 3',
                                subtitle: 'Pode evoluir mais neste fundamento',
                                icon: Icons.warning_amber_rounded,
                                accentColor: Colors.orange,
                                isMobile: isMobile,
                              ),
                            ],
                          ),
          ),
        ],
      ),
    );
  }
}
