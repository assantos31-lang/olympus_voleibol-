import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import '../pages/add_event_page.dart';

class AgendaPage extends StatefulWidget {
  const AgendaPage({Key? key}) : super(key: key);

  @override
  State<AgendaPage> createState() => _AgendaPageState();
}

class _AgendaPageState extends State<AgendaPage> {
  final SupabaseClient _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _eventos = [];
  List<Map<String, dynamic>> _eventosFiltrados = [];
  bool _loading = true;
  String? _error;
  String _filtroSelecionado = 'Todos';
  String _filtroMes = '';
  String _filtroGenero = 'Todos';

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

      final response = await _supabase
          .from('events')
          .select()
          .eq('user_id', user.id)
          .order('event_date', ascending: true)
          .order('event_time', ascending: true);

      setState(() {
        _eventos = List<Map<String, dynamic>>.from(response);
        _aplicarFiltros();
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Erro ao buscar eventos: $e';
        _loading = false;
      });
    }
  }

  void _aplicarFiltros() {
    List<Map<String, dynamic>> eventosFiltrados = _eventos;

    if (_filtroSelecionado != 'Todos') {
      eventosFiltrados = eventosFiltrados
          .where((evento) =>
              (evento['event_type'] ?? '').toLowerCase() ==
              _filtroSelecionado.toLowerCase())
          .toList();
    }

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

    if (_filtroGenero != 'Todos') {
      eventosFiltrados = eventosFiltrados
          .where((evento) =>
              (evento['gender'] ?? evento['category'] ?? '')
                  .toString()
                  .toLowerCase() ==
              _filtroGenero.toLowerCase())
          .toList();
    }

    setState(() {
      _eventosFiltrados = eventosFiltrados;
    });
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

  void _navegarParaCadastroEvento() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const AddEventPage()),
    );

    if (result == true) {
      _refreshEventos();
    }
  }

  void _editarEvento(Map<String, dynamic> evento) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AddEventPage(evento: evento),
      ),
    );

    if (result == true) {
      _refreshEventos();
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Minha Agenda',
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
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
                                  ? Colors.blue
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
                const SizedBox(width: 8),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey[300]!),
                    ),
                    child: DropdownButton<String>(
                      value: _filtroGenero == 'Todos' ? null : _filtroGenero,
                      hint: Text('Gênero',
                          style: TextStyle(color: Colors.grey[600])),
                      isExpanded: true,
                      underline: const SizedBox(),
                      items: [
                        DropdownMenuItem(value: 'Todos', child: Text('Todos')),
                        DropdownMenuItem(
                            value: 'masculino', child: Text('Masculino')),
                        DropdownMenuItem(
                            value: 'feminino', child: Text('Feminino')),
                        DropdownMenuItem(value: 'misto', child: Text('Misto')),
                      ],
                      onChanged: (valor) {
                        setState(() {
                          _filtroGenero = valor ?? 'Todos';
                          _aplicarFiltros();
                        });
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Expanded(
                  child: _buildFiltroButton('Todos', Icons.filter_list),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildFiltroButton('Treino', Icons.fitness_center),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildFiltroButton('Amistoso', Icons.sports),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildFiltroButton('Campeonato', Icons.emoji_events),
                ),
              ],
            ),
          ),
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
                              child: Text('Tentar Novamente'),
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
                                Text(
                                  _filtroSelecionado == 'Todos' &&
                                          _filtroGenero == 'Todos'
                                      ? 'Nenhum evento neste mês'
                                      : 'Nenhum evento encontrado',
                                  style: TextStyle(
                                    fontSize: 18,
                                    color: Colors.grey[600],
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Clique no + para adicionar um evento',
                                  style: TextStyle(color: Colors.grey[500]),
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
                                final corTipo = _getCorTipoEvento(
                                    evento['event_type'] ?? '');

                                return Card(
                                  margin: const EdgeInsets.only(bottom: 12),
                                  elevation: 2,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(12),
                                    onTap: () {
                                      _mostrarDetalhesEvento(evento);
                                    },
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
                                                  color:
                                                      corTipo.withOpacity(0.1),
                                                  borderRadius:
                                                      BorderRadius.circular(20),
                                                  border: Border.all(
                                                      color: corTipo),
                                                ),
                                                child: Text(
                                                  (evento['event_type'] ??
                                                          'Geral')
                                                      .toUpperCase(),
                                                  style: TextStyle(
                                                    color: corTipo,
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 12,
                                                  ),
                                                ),
                                              ),
                                              const Spacer(),
                                              PopupMenuButton<String>(
                                                icon: Icon(
                                                  Icons.more_vert,
                                                  color: Colors.grey[600],
                                                ),
                                                onSelected: (value) {
                                                  if (value == 'editar') {
                                                    _editarEvento(evento);
                                                  }
                                                },
                                                itemBuilder: (context) => [
                                                  PopupMenuItem(
                                                    value: 'editar',
                                                    child: Row(
                                                      children: [
                                                        Icon(
                                                          Icons.edit,
                                                          size: 18,
                                                          color: Colors.blue,
                                                        ),
                                                        SizedBox(width: 8),
                                                        Text('Editar evento'),
                                                      ],
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 12),
                                          Text(
                                            evento['event_name'] ?? 'Sem nome',
                                            style: TextStyle(
                                              fontSize: 18,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
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
                                                    evento['event_date'] ?? ''),
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
                                                evento['event_time'] ?? '',
                                                style: TextStyle(
                                                    color: Colors.grey[700]),
                                              ),
                                            ],
                                          ),
                                          if (evento['location'] != null &&
                                              evento['location']
                                                  .toString()
                                                  .isNotEmpty) ...[
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
                                                    evento['location'],
                                                    style: TextStyle(
                                                        color:
                                                            Colors.grey[700]),
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _navegarParaCadastroEvento,
        icon: Icon(Icons.add),
        label: Text('Cadastrar Evento'),
      ),
    );
  }

  Widget _buildFiltroButton(String tipo, IconData icone) {
    final bool selecionado = _filtroSelecionado == tipo;
    final Color corBase = tipo == 'Campeonato'
        ? Colors.amber[700]!
        : tipo == 'Treino'
            ? Colors.blue
            : tipo == 'Amistoso'
                ? Colors.green
                : Colors.grey[600]!;

    return InkWell(
      onTap: () {
        setState(() {
          _filtroSelecionado = tipo;
          _aplicarFiltros();
        });
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selecionado ? corBase.withOpacity(0.2) : Colors.grey[100],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selecionado ? corBase : Colors.grey[300]!,
            width: 2,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (selecionado) Icon(Icons.check, size: 16, color: corBase),
            if (selecionado) const SizedBox(width: 4),
            Icon(icone,
                size: 16, color: selecionado ? corBase : Colors.grey[600]),
            const SizedBox(width: 4),
            Text(
              tipo,
              style: TextStyle(
                fontWeight: selecionado ? FontWeight.bold : FontWeight.normal,
                color: selecionado ? corBase : Colors.grey[700],
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _mostrarDetalhesEvento(Map<String, dynamic> evento) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.6,
          minChildSize: 0.4,
          maxChildSize: 0.9,
          expand: false,
          builder: (context, scrollController) {
            return SingleChildScrollView(
              controller: scrollController,
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.grey[300],
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      evento['event_name'] ?? 'Detalhes do Evento',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _buildDetailRow(
                      Icons.calendar_today,
                      'Data',
                      _formatarData(evento['event_date'] ?? ''),
                    ),
                    _buildDetailRow(
                      Icons.access_time,
                      'Horário',
                      evento['event_time'] ?? '',
                    ),
                    _buildDetailRow(
                      Icons.category,
                      'Tipo',
                      evento['event_type'] ?? '',
                    ),
                    if (evento['gender'] != null &&
                        evento['gender'].toString().isNotEmpty)
                      _buildDetailRow(
                        Icons.people,
                        'Gênero',
                        evento['gender'],
                      ),
                    if (evento['set_format'] != null &&
                        evento['set_format'].toString().isNotEmpty)
                      _buildDetailRow(
                        Icons.sports_volleyball,
                        'Formato',
                        evento['set_format'],
                      ),
                    if (evento['street'] != null) ...[
                      Divider(),
                      Text('Localização',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      _buildDetailRow(Icons.location_on, 'Endereço',
                          '${evento['street']}, ${evento['street_number']}'),
                      _buildDetailRow(
                          Icons.map, 'Bairro', evento['neighborhood'] ?? ''),
                      _buildDetailRow(Icons.home, 'Cidade',
                          '${evento['city']}, ${evento['state']}'),
                      _buildDetailRow(Icons.pin, 'CEP', evento['cep'] ?? ''),
                    ],
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(context),
                        child: Text('Fechar'),
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

  Widget _buildDetailRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Colors.grey[600]),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[500],
                  ),
                ),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
