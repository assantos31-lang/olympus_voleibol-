import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';

class AthleteAgendaPage extends StatefulWidget {
  const AthleteAgendaPage({Key? key}) : super(key: key);

  @override
  State<AthleteAgendaPage> createState() => _AthleteAgendaPageState();
}

class _AthleteAgendaPageState extends State<AthleteAgendaPage> {
  final SupabaseClient _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _eventos = [];
  List<Map<String, dynamic>> _eventosFiltrados = [];
  // Mantemos o mapa de status caso precise acessar fora do objeto evento
  Map<String, Map<String, String>> _convocationStatus = {};
  bool _loading = true;
  String? _error;
  String _filtroMes = '';

  // ✅ NOVO: filtro por tipo
  String _filtroTipo = 'todos';

  @override
  void initState() {
    super.initState();
    _setMesAtual();
    _buscarEventos();
  }

  void _setMesAtual() {
    final now = DateTime.now();
    _filtroMes = '${now.month.toString().padLeft(2, '0')}/${now.year}';
  }

  Future<void> _buscarEventos() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final user = _supabase.auth.currentUser;
      if (user == null) {
        setState(() {
          _error = 'Usuário não autenticado';
          _loading = false;
        });
        return;
      }

      print('🔍 User ID: ${user.id}');

      // ✅ Ajuste mínimo: incluir championship_name e endereço no select
      final response = await _supabase.from('convocations').select('''
            status,
            events (
              id,
              event_name,
              event_type,
              event_date,
              event_time,
              gender,
              championship_name,
              street,
              street_number,
              neighborhood,
              city,
              state
            )
          ''').eq('user_id', user.id);

      print('📋 Resposta da Query: ${response.length}');
      print('📋 Dados: $response');

      if (response.isEmpty) {
        setState(() {
          _eventos = [];
          _eventosFiltrados = [];
          _loading = false;
        });
        return;
      }

      // Processar os dados do JOIN
      final eventosList = <Map<String, dynamic>>[];
      final statusMap = <String, Map<String, String>>{};

      for (var item in response) {
        final eventData = item['events'];
        final status = item['status'] ?? 'pending';

        if (eventData != null) {
          eventData['convocation_status'] = status;
          eventosList.add(eventData);

          statusMap[eventData['id']] = {'status': status};
        }
      }

      // Ordenar por data e hora
      eventosList.sort((a, b) {
        final dateA = a['event_date'] ?? '';
        final dateB = b['event_date'] ?? '';
        final timeA = a['event_time'] ?? '';
        final timeB = b['event_time'] ?? '';
        final compare = dateA.compareTo(dateB);
        if (compare != 0) return compare;
        return timeA.compareTo(timeB);
      });

      setState(() {
        _eventos = eventosList;
        _convocationStatus = statusMap;
        _aplicarFiltros(); // ✅ sem loop (não chama setState)
        _loading = false;
      });
    } catch (e, stackTrace) {
      print('❌ Erro: $e');
      print('❌ Stack: $stackTrace');
      setState(() {
        _error = 'Erro ao carregar eventos: $e';
        _loading = false;
      });
    }
  }

  // ✅ Correção do loop: aqui NÃO deve ter setState
  void _aplicarFiltros() {
    List<Map<String, dynamic>> eventosFiltrados = _eventos;

    if (_filtroMes.isNotEmpty) {
      eventosFiltrados = eventosFiltrados.where((evento) {
        final dataEvento = evento['event_date'] ?? '';
        if (dataEvento.toString().length >= 7) {
          final mesAnoEvento = dataEvento.toString().substring(3);
          return mesAnoEvento == _filtroMes;
        }
        return false;
      }).toList();
    }

    // ✅ NOVO: filtro por tipo
    if (_filtroTipo != 'todos') {
      eventosFiltrados = eventosFiltrados.where((evento) {
        final tipo =
            (evento['event_type'] ?? '').toString().toLowerCase().trim();
        return tipo == _filtroTipo;
      }).toList();
    }

    _eventosFiltrados = eventosFiltrados;
  }

  Future<void> _refreshEventos() async {
    await _buscarEventos();
  }

  String _formatarData(String dataStr) {
    try {
      final parts = dataStr.split('/');
      if (parts.length == 3) {
        final date = DateTime(
            int.parse(parts[2]), int.parse(parts[1]), int.parse(parts[0]));
        return DateFormat('dd/MM/yyyy (EEEE)', 'pt_BR').format(date);
      }
      return dataStr;
    } catch (e) {
      return dataStr;
    }
  }

  Color _getCorTipoEvento(String tipo) {
    switch (tipo.toLowerCase()) {
      case 'treino':
        return Colors.blue;
      case 'jogo':
      case 'partida':
      case 'amistoso':
        return Colors.green;
      case 'campeonato':
        return Colors.amber[700]!;
      case 'reuniao':
        return Colors.orange;
      default:
        return Colors.purple;
    }
  }

  // ✅ NOVO: cores do CARD por tipo
  Color _getCorFundoCard(String genero, String tipo) {
    final t = tipo.toLowerCase().trim();
    if (t == 'treino') return const Color(0xFFE3F2FD); // azul claro
    if (t == 'amistoso') return const Color(0xFFE8F5E9); // verde claro
    if (t == 'campeonato') return const Color(0xFFFFF8E1); // âmbar claro

    final generoLower = genero.toLowerCase();
    if (generoLower == 'masculino') return const Color(0xFFE3F2FD);
    if (generoLower == 'feminino') return const Color(0xFFF3E5F5);
    return Colors.white;
  }

  Color _getStatusColor(String? status) {
    switch (status?.toLowerCase()) {
      case 'accepted':
        return Colors.green;
      case 'rejected':
        return Colors.red;
      default:
        return Colors.orange;
    }
  }

  String _getStatusLabel(String? status) {
    switch (status?.toLowerCase()) {
      case 'accepted':
        return 'Aceitou';
      case 'rejected':
        return 'Recusou';
      default:
        return 'Pendente';
    }
  }

  bool _podeEditar(Map<String, dynamic> evento) {
    final tipo = (evento['event_type'] ?? '').toString().toLowerCase().trim();
    final dataStr = (evento['event_date'] ?? '').toString().trim();
    final horaStr = (evento['event_time'] ?? '').toString().trim();

    if (tipo.isEmpty || dataStr.isEmpty || horaStr.isEmpty) return false;

    try {
      final dp = dataStr.split('/');
      final tp = horaStr.split(':');
      if (dp.length != 3 || tp.length < 2) return false;

      final eventDateTime = DateTime(
        int.parse(dp[2]),
        int.parse(dp[1]),
        int.parse(dp[0]),
        int.parse(tp[0]),
        int.parse(tp[1]),
      );

      final now = DateTime.now();
      if (eventDateTime.isBefore(now)) return false;

      int horasLimite;
      switch (tipo) {
        case 'treino':
          horasLimite = 3;
          break;
        case 'amistoso':
          horasLimite = 12;
          break;
        case 'campeonato':
          horasLimite = 48;
          break;
        default:
          horasLimite = 3;
      }

      return eventDateTime.difference(now).inMinutes >= (horasLimite * 60);
    } catch (e) {
      return false;
    }
  }

  String _getPrazoInfo(Map<String, dynamic> evento) {
    final tipo = (evento['event_type'] ?? '').toString().toLowerCase().trim();
    switch (tipo) {
      case 'treino':
        return 'Treino: edição permitida até 3h antes do evento.';
      case 'amistoso':
        return 'Amistoso: edição permitida até 12h antes do evento.';
      case 'campeonato':
        return 'Campeonato: edição permitida até 48h antes do evento.';
      default:
        return '';
    }
  }

  // ✅ NOVO: dialog para editar (aceitar/recusar novamente)
  Future<void> _editarResposta(Map<String, dynamic> evento) async {
    final escolha = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Editar resposta'),
        content: const Text('Deseja aceitar ou recusar esta convocação?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, null),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'rejected'),
            child: const Text('Recusar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, 'accepted'),
            child: const Text('Aceitar'),
          ),
        ],
      ),
    );

    if (escolha == null) return;

    if (escolha == 'accepted') {
      await _responderConvocacao(evento, true);
    } else if (escolha == 'rejected') {
      await _responderConvocacao(evento, false);
    }
  }

  Future<void> _responderConvocacao(
      Map<String, dynamic> evento, bool aceitar) async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;

      final eventId = evento['id'];

      if (aceitar) {
        await _supabase
            .from('convocations')
            .update({'status': 'accepted', 'justification': null})
            .eq('event_id', eventId)
            .eq('user_id', user.id);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ Convocação aceita!'),
              backgroundColor: Colors.green,
            ),
          );
          _refreshEventos();
        }
        return;
      }

      final controller = TextEditingController();
      final justification = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text('Justificativa obrigatória'),
          content: TextField(
            controller: controller,
            maxLines: 3,
            decoration: const InputDecoration(
              hintText: 'Digite o motivo da recusa',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, null),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () {
                final text = controller.text.trim();
                if (text.isEmpty) return;
                Navigator.pop(context, text);
              },
              child: const Text('Confirmar'),
            ),
          ],
        ),
      );

      if (justification == null) return;

      await _supabase
          .from('convocations')
          .update({'status': 'rejected', 'justification': justification})
          .eq('event_id', eventId)
          .eq('user_id', user.id);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('❌ Convocação recusada'),
            backgroundColor: Colors.red,
          ),
        );
        _refreshEventos();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  List<String> _getMesesDisponiveis() {
    final now = DateTime.now();
    final anoAtual = now.year;
    final meses = <String>[];
    for (int i = 1; i <= 12; i++) {
      meses.add('${i.toString().padLeft(2, '0')}/$anoAtual');
    }
    return meses;
  }

  String _formatarNomeMes(String mesAno) {
    try {
      final parts = mesAno.split('/');
      if (parts.length == 2) {
        final mes = int.parse(parts[0]);
        final ano = parts[1];
        final mesNome =
            DateFormat('MMMM', 'pt_BR').format(DateTime(int.parse(ano), mes));
        return '${mesNome[0].toUpperCase()}${mesNome.substring(1)} $ano';
      }
      return mesAno;
    } catch (e) {
      return mesAno;
    }
  }

  // ✅ NOVO: UI de filtros por tipo (Todos, Treino, Amistoso, Campeonatos)
  Widget _buildFiltroTipoButtons() {
    Widget chip(String label, String value) {
      final selected = _filtroTipo == value;
      return ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) {
          setState(() {
            _filtroTipo = value;
            _aplicarFiltros();
          });
        },
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          chip('Todos', 'todos'),
          chip('Treino', 'treino'),
          chip('Amistoso', 'amistoso'),
          chip('Campeonatos', 'campeonato'),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Minhas Convocações',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: const Color(0xFF1E3A5F),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refreshEventos,
            color: Colors.white,
          ),
        ],
        elevation: 2,
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.grey[50],
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey[300]!),
                    ),
                    child: DropdownButton<String>(
                      value: _filtroMes,
                      hint: Text('Mês',
                          style: TextStyle(color: Colors.grey[600])),
                      isExpanded: true,
                      underline: const SizedBox(),
                      items: _getMesesDisponiveis().map((mes) {
                        return DropdownMenuItem(
                          value: mes,
                          child: Text(
                            _formatarNomeMes(mes),
                            style: TextStyle(
                              fontWeight: _filtroMes == mes
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                              color: _filtroMes == mes
                                  ? const Color(0xFF1E3A5F)
                                  : Colors.black,
                            ),
                          ),
                        );
                      }).toList(),
                      onChanged: (valor) {
                        if (valor != null) {
                          setState(() {
                            _filtroMes = valor;
                            _aplicarFiltros();
                          });
                        }
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ✅ NOVO: botões de filtro por tipo
          _buildFiltroTipoButtons(),

          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.error_outline,
                                size: 48, color: Colors.red[300]),
                            const SizedBox(height: 16),
                            Text(_error!, style: TextStyle(color: Colors.red)),
                            const SizedBox(height: 16),
                            ElevatedButton(
                              onPressed: _buscarEventos,
                              child: const Text('Tentar Novamente'),
                            ),
                          ],
                        ),
                      )
                    : _eventosFiltrados.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.event_busy,
                                    size: 64, color: Colors.grey[400]),
                                const SizedBox(height: 16),
                                const Text(
                                  'Nenhuma convocação encontrada',
                                  style: TextStyle(
                                    fontSize: 18,
                                    color: Colors.grey,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : RefreshIndicator(
                            onRefresh: _refreshEventos,
                            child: ListView.builder(
                              padding: const EdgeInsets.all(16),
                              itemCount: _eventosFiltrados.length,
                              itemBuilder: (context, index) {
                                final evento = _eventosFiltrados[index];
                                final eventId = evento['id'];

                                final statusData = _convocationStatus[eventId];
                                final status = statusData?['status'] ??
                                    evento['convocation_status'] ??
                                    'pending';

                                final eventType =
                                    (evento['event_type'] ?? '').toString();
                                final corTipo = _getCorTipoEvento(eventType);
                                final genero =
                                    (evento['gender'] ?? '').toString();

                                // ✅ prazo + bloqueio
                                final podeEditar = _podeEditar(evento);
                                final prazoInfo = _getPrazoInfo(evento);

                                // ✅ NOVO: campeonato
                                final championshipName =
                                    (evento['championship_name'] ?? '')
                                        .toString()
                                        .trim();

                                // ✅ NOVO: endereço completo
                                String? enderecoCompleto;
                                final street =
                                    (evento['street'] ?? '').toString().trim();
                                if (street.isNotEmpty) {
                                  final numero = (evento['street_number'] ?? '')
                                      .toString()
                                      .trim();
                                  final bairro = (evento['neighborhood'] ?? '')
                                      .toString()
                                      .trim();
                                  final cidade =
                                      (evento['city'] ?? '').toString().trim();
                                  final estado =
                                      (evento['state'] ?? '').toString().trim();

                                  enderecoCompleto = '$street'
                                      '${numero.isNotEmpty ? ', $numero' : ''}'
                                      '${bairro.isNotEmpty ? ' - $bairro' : ''}'
                                      '${cidade.isNotEmpty ? ' - $cidade' : ''}'
                                      '${estado.isNotEmpty ? '/$estado' : ''}';
                                }

                                return Card(
                                  margin: const EdgeInsets.only(bottom: 12),
                                  elevation: 2,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  color: _getCorFundoCard(genero, eventType),
                                  child: Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                horizontal: 12,
                                                vertical: 6,
                                              ),
                                              decoration: BoxDecoration(
                                                color: corTipo.withOpacity(0.1),
                                                borderRadius:
                                                    BorderRadius.circular(20),
                                                border:
                                                    Border.all(color: corTipo),
                                              ),
                                              child: Text(
                                                (evento['event_type'] ??
                                                        'Geral')
                                                    .toString()
                                                    .toUpperCase(),
                                                style: TextStyle(
                                                  color: corTipo,
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 12,
                                                ),
                                              ),
                                            ),
                                            const Spacer(),
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                horizontal: 12,
                                                vertical: 6,
                                              ),
                                              decoration: BoxDecoration(
                                                color: _getStatusColor(status)
                                                    .withOpacity(0.1),
                                                borderRadius:
                                                    BorderRadius.circular(20),
                                                border: Border.all(
                                                  color:
                                                      _getStatusColor(status),
                                                ),
                                              ),
                                              child: Text(
                                                _getStatusLabel(status),
                                                style: TextStyle(
                                                  color:
                                                      _getStatusColor(status),
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 12,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 12),
                                        Text(
                                          (evento['event_name'] ?? 'Sem nome')
                                              .toString(),
                                          style: const TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),

                                        // ✅ NOVO: nome do campeonato
                                        if (eventType.toLowerCase().trim() ==
                                                'campeonato' &&
                                            championshipName.isNotEmpty) ...[
                                          const SizedBox(height: 6),
                                          Row(
                                            children: [
                                              Icon(Icons.emoji_events,
                                                  size: 16,
                                                  color: Colors.amber[700]),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: Text(
                                                  championshipName,
                                                  style: TextStyle(
                                                    fontSize: 14,
                                                    color: Colors.amber[900],
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],

                                        const SizedBox(height: 8),
                                        Row(
                                          children: [
                                            Icon(
                                              Icons.calendar_today,
                                              size: 16,
                                              color: Colors.grey[600],
                                            ),
                                            const SizedBox(width: 8),
                                            Text(
                                              _formatarData(
                                                  (evento['event_date'] ?? '')
                                                      .toString()),
                                              style: TextStyle(
                                                  color: Colors.grey[700]),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        Row(
                                          children: [
                                            Icon(
                                              Icons.access_time,
                                              size: 16,
                                              color: Colors.grey[600],
                                            ),
                                            const SizedBox(width: 8),
                                            Text(
                                              (evento['event_time'] ?? '')
                                                  .toString(),
                                              style: TextStyle(
                                                  color: Colors.grey[700]),
                                            ),
                                          ],
                                        ),

                                        // ✅ NOVO: endereço
                                        if (enderecoCompleto != null &&
                                            enderecoCompleto.isNotEmpty) ...[
                                          const SizedBox(height: 4),
                                          Row(
                                            children: [
                                              Icon(
                                                Icons.location_on,
                                                size: 16,
                                                color: Colors.grey[600],
                                              ),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: Text(
                                                  enderecoCompleto,
                                                  style: TextStyle(
                                                    color: Colors.grey[700],
                                                    fontSize: 13,
                                                  ),
                                                  maxLines: 2,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],

                                        const SizedBox(height: 12),

                                        // ✅ texto informativo
                                        if (prazoInfo.isNotEmpty) ...[
                                          Text(
                                            prazoInfo,
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: Colors.grey[600],
                                              fontStyle: FontStyle.italic,
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                        ],

                                        // ✅ PENDENTE -> Aceitar/Recusar (bloqueia após prazo)
                                        if (status == 'pending')
                                          Row(
                                            children: [
                                              Expanded(
                                                child: ElevatedButton.icon(
                                                  onPressed: podeEditar
                                                      ? () =>
                                                          _responderConvocacao(
                                                              evento, false)
                                                      : null,
                                                  icon: const Icon(Icons.close),
                                                  label: const Text('Recusar'),
                                                  style:
                                                      ElevatedButton.styleFrom(
                                                    backgroundColor: podeEditar
                                                        ? Colors.red
                                                        : Colors.grey,
                                                    foregroundColor:
                                                        Colors.white,
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 12),
                                              Expanded(
                                                child: ElevatedButton.icon(
                                                  onPressed: podeEditar
                                                      ? () =>
                                                          _responderConvocacao(
                                                              evento, true)
                                                      : null,
                                                  icon: const Icon(Icons.check),
                                                  label: const Text('Aceitar'),
                                                  style:
                                                      ElevatedButton.styleFrom(
                                                    backgroundColor: podeEditar
                                                        ? Colors.green
                                                        : Colors.grey,
                                                    foregroundColor:
                                                        Colors.white,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),

                                        // ✅ EDITAR -> sempre aparece quando já respondeu (habilita/desabilita por prazo)
                                        if (status != 'pending') ...[
                                          const SizedBox(height: 8),
                                          SizedBox(
                                            width: double.infinity,
                                            child: ElevatedButton.icon(
                                              onPressed: podeEditar
                                                  ? () =>
                                                      _editarResposta(evento)
                                                  : null,
                                              icon: const Icon(Icons.edit),
                                              label:
                                                  const Text('Editar resposta'),
                                              // ✅ Botão editar com cor diferente
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: podeEditar
                                                    ? Colors.deepPurple
                                                    : Colors.grey,
                                                foregroundColor: Colors.white,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
          ),
        ],
      ),
    );
  }
}
