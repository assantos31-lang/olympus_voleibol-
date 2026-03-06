import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // ✅ NOVO: para Clipboard na exportação Excel
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
  Map<String, Map<String, int>> _quantidadeConvocados =
      {}; // {eventId: {'athletes': n, 'technicians': n}}
  Map<String, Map<String, int>> _checkinInfo =
      {}; // {eventId: {'checked_in': n, 'pending': n}}
  // ✅ NOVO (cirúrgico): cache da view event_convocation_stats
  // {eventId: {'total_convocados': n, 'total_aceitos': n, 'total_pendentes': n, 'total_recusados': n}}
  Map<String, Map<String, int>> _convocationStats = {};
  bool _loading = true;
  String? _error;
  String _filtroSelecionado = 'Todos';
  String _filtroMes = '';
  String _filtroGenero = 'Todos';
  Set<String> _placaresExpandidos = {}; // IDs dos placares expandidos

  // ✅ Cores do logo Olympus Voleibol
  static const Color olympusBlue = Color(0xFF1E3A5F);
  static const Color olympusGold = Color(0xFFD4AF37);
  static const Color olympusLightBlue = Color(0xFF2C5F8D);

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
      // ✅ NOVO: pega stats em lote (evita zero por RLS e evita loops)
      await _buscarConvocationStats();
      // Mantemos suas funções, mas com correções internas
      await _buscarQuantidadeConvocados();
      await _buscarCheckinInfo();
    } catch (e) {
      setState(() {
        _error = 'Erro ao buscar eventos: $e';
        _loading = false;
      });
    }
  }

  // ✅ NOVO (cirúrgico): busca a view uma vez e guarda em mapa
  Future<void> _buscarConvocationStats() async {
    try {
      final ids =
          _eventos.map((e) => e['id']?.toString()).whereType<String>().toList();
      if (ids.isEmpty) {
        if (mounted) {
          setState(() {
            _convocationStats = {};
          });
        }
        return;
      }
      final resp = await _supabase
          .from('event_convocation_stats')
          .select(
              'event_id,total_convocados,total_aceitos,total_pendentes,total_recusados')
          .inFilter('event_id', ids);
      final map = <String, Map<String, int>>{};
      for (final row in resp) {
        final eventId = row['event_id']?.toString();
        if (eventId == null) continue;
        map[eventId] = {
          'total_convocados': (row['total_convocados'] ?? 0) as int,
          'total_aceitos': (row['total_aceitos'] ?? 0) as int,
          'total_pendentes': (row['total_pendentes'] ?? 0) as int,
          'total_recusados': (row['total_recusados'] ?? 0) as int,
        };
      }
      if (mounted) {
        setState(() {
          _convocationStats = map;
        });
      }
    } catch (e) {
      // Não quebra a tela; apenas mantém vazio e segue
      print('Erro ao buscar event_convocation_stats: $e');
    }
  }

  // ✅ CORREÇÃO: total NÃO depende de profiles (RLS). Tentamos split via join se der.
  Future<void> _buscarQuantidadeConvocados() async {
    try {
      final quantidades = <String, Map<String, int>>{};
      for (var evento in _eventos) {
        final eventId = evento['id']?.toString();
        if (eventId == null) continue;
        // ✅ Busca convocations + tenta join do profiles(user_type)
        final convocationsResponse = await _supabase
            .from('convocations')
            .select('user_id, profiles(user_type)')
            .eq('event_id', eventId);
        // ✅ Total sempre correto (independe de profiles)
        int atletas = 0;
        int tecnicos = 0;
        for (var convocation in convocationsResponse) {
          final profile = convocation['profiles'];
          final userType = profile != null ? profile['user_type'] : null;
          if (userType == 'athlete') {
            atletas++;
          } else if (userType == 'coach') {
            tecnicos++;
          }
        }
        quantidades[eventId] = {'athletes': atletas, 'technicians': tecnicos};
      }
      if (mounted) {
        setState(() {
          _quantidadeConvocados = quantidades;
        });
      }
    } catch (e) {
      print('Erro ao buscar quantidade de convocados: $e');
    }
  }

  // ✅ CORREÇÃO: usa a VIEW (evita loops e evita "zerado")
  Future<void> _buscarCheckinInfo() async {
    try {
      final checkinData = <String, Map<String, int>>{};
      for (var evento in _eventos) {
        final eventId = evento['id']?.toString();
        if (eventId == null) continue;
        final allowCheckin = evento['allow_checkin'] ?? false;
        if (!allowCheckin) continue;
        // ✅ Busca na tabela checkins quem realmente fez check-in
        final checkinsResponse = await _supabase
            .from('checkins')
            .select('user_id')
            .eq('event_id', eventId);
        final checkedIn = checkinsResponse.length;
        // Total de convocados que aceitaram (para calcular pendentes)
        final stats = _convocationStats[eventId];
        final totalAceitos = stats?['total_aceitos'] ?? 0;
        final pending = totalAceitos - checkedIn;
        checkinData[eventId] = {'checked_in': checkedIn, 'pending': pending};
      }
      if (mounted) {
        setState(() {
          _checkinInfo = checkinData;
        });
      }
    } catch (e) {
      print('Erro ao buscar info de check-in: $e');
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

  Color _getCorFundoCard(String genero) {
    final generoLower = genero.toLowerCase();
    if (generoLower == 'masculino') {
      return const Color(0xFFE3F2FD);
    } else if (generoLower == 'feminino') {
      return const Color(0xFFF3E5F5);
    }
    return Colors.white;
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

  // ✅ NOVO: Método para excluir evento
  Future<void> _excluirEvento(Map<String, dynamic> evento) async {
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Excluir evento'),
        content: const Text(
            'Tem certeza que deseja excluir este evento? Esta ação não pode ser desfeita.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (confirmado != true) return;
    try {
      final eventId = evento['id'];
      if (eventId == null) return;
      // ✅ Excluir convocações relacionadas primeiro (evita erro de foreign key)
      await _supabase.from('convocations').delete().eq('event_id', eventId);
      // ✅ Excluir o evento
      await _supabase.from('events').delete().eq('id', eventId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Evento excluído com sucesso!'),
            backgroundColor: Colors.green,
          ),
        );
        _refreshEventos();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Erro ao excluir evento: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // ✅ NOVO: Exportar dados dos convocados para Excel (CSV com delimitador ; e BOM)
  Future<void> _exportarConvocados(Map<String, dynamic> evento) async {
    final eventId = evento['id']?.toString();
    if (eventId == null) return;
    try {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('📊 Preparando exportação para Excel...'),
            backgroundColor: Colors.blue,
            duration: Duration(seconds: 2),
          ),
        );
      }
      final convocationsResponse = await _supabase
          .from('convocations')
          .select('user_id, status, justification')
          .eq('event_id', eventId);
      // ✅ BOM UTF-8 para Excel reconhecer acentos corretamente
      final bom = '\uFEFF';
      // ✅ Cabeçalho com delimitador ; (padrão Excel PT-BR)
      List<String> csvLines = [
        '${bom}Nome;Tipo;Status;Data de Nascimento;RG;Justificativa'
      ];
      for (var convocation in convocationsResponse) {
        final userId = convocation['user_id'];
        if (userId != null) {
          final profileResponse = await _supabase
              .from('profiles')
              .select('full_name, user_type, birth_date, rg')
              .eq('id', userId)
              .maybeSingle();
          if (profileResponse != null) {
            // ✅ Sanitiza campos: remove quebras de linha e envolve em aspas se necessário
            String _sanitize(String? value) {
              if (value == null || value.isEmpty) return '""';
              final cleaned = value
                  .replaceAll('\n', ' ')
                  .replaceAll('\r', ' ')
                  .replaceAll('"', '""');
              return '"$cleaned"';
            }

            final nome = _sanitize(profileResponse['full_name']);
            final tipo = _sanitize(profileResponse['user_type']);
            final status = _sanitize(convocation['status']);
            // ✅ Converte data para formato DD/MM/YYYY (Excel PT-BR)
            String birthDate = '';
            final rawDate = profileResponse['birth_date'];
            if (rawDate != null && rawDate.toString().length >= 10) {
              try {
                final date = DateTime.parse(rawDate.toString());
                birthDate =
                    '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
              } catch (_) {
                birthDate = rawDate.toString();
              }
            }
            final rg = _sanitize(profileResponse['rg']);
            final justification = _sanitize(convocation['justification']);
            // ✅ Linha com delimitador ;
            csvLines.add('$nome;$tipo;$status;$birthDate;$rg;$justification');
          }
        }
      }
      final csvContent = csvLines.join('\n');
      // ✅ Copia para clipboard com formato compatível com Excel
      await Clipboard.setData(ClipboardData(text: csvContent));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Dados copiados! Cole no Excel com Ctrl+V'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Erro ao exportar: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _mostrarCheckinDetalhes(Map<String, dynamic> evento) async {
    final eventId = evento['id']?.toString();
    if (eventId == null) return;
    try {
      final convocationsResponse = await _supabase
          .from('convocations')
          .select('user_id, status, justification')
          .eq('event_id', eventId);
      List<Map<String, dynamic>> participantes = [];
      for (var convocation in convocationsResponse) {
        final userId = convocation['user_id'];
        if (userId != null) {
          final profileResponse = await _supabase
              .from('profiles')
              .select('full_name, user_type')
              .eq('id', userId)
              .single();
          if (profileResponse != null) {
            participantes.add({
              'nome': profileResponse['full_name'] ?? 'Sem nome',
              'tipo': profileResponse['user_type'] ?? 'unknown',
              'status': convocation['status'] ?? 'pending',
              'justification': convocation['justification'],
            });
          }
        }
      }
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => Dialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            child: Container(
              padding: const EdgeInsets.all(24),
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.7,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.people_outline,
                        color: olympusGold,
                        size: 28,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Convocados: ${evento['event_name']}',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: olympusBlue,
                              ),
                            ),
                            Text(
                              '${participantes.where((p) => p['status'] == 'accepted').length} aceitaram de ${participantes.length}',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const Divider(height: 32),
                  if (participantes.isEmpty)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(32),
                        child: Text(
                          'Nenhum participante convocado',
                          style: TextStyle(color: Colors.grey),
                        ),
                      ),
                    )
                  else
                    Expanded(
                      child: SingleChildScrollView(
                        child: Column(
                          children: [
                            ...participantes.map((participante) {
                              final status =
                                  (participante['status'] ?? 'pending')
                                      .toString();
                              final isAceitou = status == 'accepted';
                              final isRecusou = status == 'rejected';
                              final isAtleta =
                                  participante['tipo'] == 'athlete';
                              final labelStatus = isAceitou
                                  ? 'Aceitou'
                                  : (isRecusou ? 'Recusou' : 'Pendente');
                              final colorStatus = isAceitou
                                  ? Colors.green[700]
                                  : (isRecusou
                                      ? Colors.red[700]
                                      : Colors.grey[600]);
                              return Container(
                                margin: const EdgeInsets.only(bottom: 8),
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: isAceitou
                                      ? Colors.green[50]
                                      : (isRecusou
                                          ? Colors.red[50]
                                          : Colors.grey[100]),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: isAceitou
                                        ? Colors.green[300]!
                                        : (isRecusou
                                            ? Colors.red[300]!
                                            : Colors.grey[300]!),
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Icon(
                                          isAceitou
                                              ? Icons.check_circle
                                              : (isRecusou
                                                  ? Icons.cancel
                                                  : Icons.hourglass_empty),
                                          color: colorStatus,
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                participante['nome'],
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w600,
                                                  fontSize: 14,
                                                ),
                                              ),
                                              Text(
                                                isAtleta ? 'Atleta' : 'Técnico',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: Colors.grey[600],
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        Text(
                                          labelStatus,
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: colorStatus,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                    if (isRecusou &&
                                        (participante['justification'] ?? '')
                                            .toString()
                                            .trim()
                                            .isNotEmpty) ...[
                                      const SizedBox(height: 8),
                                      Text(
                                        'Justificativa: ${participante['justification']}',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.red[700],
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              );
                            }).toList(),
                          ],
                        ),
                      ),
                    ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: olympusBlue,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('Fechar'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao carregar convocações: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // ✅ CORREÇÃO: Consulta a tabela checkins para ver quem realmente fez check-in
  Future<void> _mostrarStatusCheckin(Map<String, dynamic> evento) async {
    final eventId = evento['id']?.toString();
    if (eventId == null) return;
    try {
      // ✅ 1. Buscar TODOS os convocados que aceitaram
      final convocationsResponse = await _supabase
          .from('convocations')
          .select('user_id, status')
          .eq('event_id', eventId);
      // ✅ 2. Buscar quem REALMENTE fez check-in (tabela checkins)
      final checkinsResponse = await _supabase
          .from('checkins')
          .select('user_id')
          .eq('event_id', eventId);
      // ✅ 3. Criar set de user_ids que fizeram check-in
      final Set<String> userIdsComCheckin = {};
      for (var checkin in checkinsResponse) {
        final userId = checkin['user_id']?.toString();
        if (userId != null) {
          userIdsComCheckin.add(userId);
        }
      }
      List<Map<String, dynamic>> quemFezCheckin = [];
      List<Map<String, dynamic>> quemNaoFezCheckin = [];
      // ✅ 4. Separar quem fez e quem não fez check-in
      for (var convocation in convocationsResponse) {
        final userId = convocation['user_id']?.toString();
        final status = convocation['status'] ?? 'pending';
        // Só considera quem ACEITOU a convocação
        if (userId != null && status == 'accepted') {
          final profileResponse = await _supabase
              .from('profiles')
              .select('full_name, user_type')
              .eq('id', userId)
              .single();
          if (profileResponse != null) {
            final participante = {
              'nome': profileResponse['full_name'] ?? 'Sem nome',
              'tipo': profileResponse['user_type'] ?? 'unknown',
              'user_id': userId,
            };
            // ✅ Verifica se está na tabela checkins
            if (userIdsComCheckin.contains(userId)) {
              quemFezCheckin.add(participante);
            } else {
              quemNaoFezCheckin.add(participante);
            }
          }
        }
      }
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => Dialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            child: Container(
              padding: const EdgeInsets.all(24),
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.7,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.check_circle_outline,
                        color: olympusGold,
                        size: 28,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Check-in: ${evento['event_name']}',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: olympusBlue,
                              ),
                            ),
                            Text(
                              '${quemFezCheckin.length} fizeram check-in de ${quemFezCheckin.length + quemNaoFezCheckin.length} que aceitaram',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const Divider(height: 32),
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // ✅ QUEM FEZ CHECK-IN (está na tabela checkins)
                          Text(
                            '✅ Fizeram Check-in (${quemFezCheckin.length})',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.green,
                            ),
                          ),
                          const SizedBox(height: 8),
                          if (quemFezCheckin.isEmpty)
                            Padding(
                              padding: const EdgeInsets.all(16),
                              child: Text(
                                'Ninguém fez check-in ainda',
                                style: TextStyle(color: Colors.grey[600]),
                              ),
                            )
                          else
                            ...quemFezCheckin.map((participante) {
                              final isAtleta =
                                  participante['tipo'] == 'athlete';
                              return Container(
                                margin: const EdgeInsets.only(bottom: 8),
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.green[50],
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: Colors.green[300]!,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.check_circle,
                                      color: Colors.green,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            participante['nome'],
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w600,
                                              fontSize: 14,
                                            ),
                                          ),
                                          Text(
                                            isAtleta ? 'Atleta' : 'Técnico',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.grey[600],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }).toList(),
                          const SizedBox(height: 16),
                          // ✅ QUEM NÃO FEZ CHECK-IN (aceitou mas não está na tabela checkins)
                          Text(
                            '⏳ Não Fizeram Check-in (${quemNaoFezCheckin.length})',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.orange,
                            ),
                          ),
                          const SizedBox(height: 8),
                          if (quemNaoFezCheckin.isEmpty)
                            Padding(
                              padding: const EdgeInsets.all(16),
                              child: Text(
                                'Todos que aceitaram já fizeram check-in!',
                                style: TextStyle(color: Colors.grey[600]),
                              ),
                            )
                          else
                            ...quemNaoFezCheckin.map((participante) {
                              final isAtleta =
                                  participante['tipo'] == 'athlete';
                              return Container(
                                margin: const EdgeInsets.only(bottom: 8),
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.orange[50],
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: Colors.orange[300]!,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.hourglass_empty,
                                      color: Colors.orange,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            participante['nome'],
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w600,
                                              fontSize: 14,
                                            ),
                                          ),
                                          Text(
                                            isAtleta ? 'Atleta' : 'Técnico',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.grey[600],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Text(
                                      'Aceitou',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.green[700],
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }).toList(),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: olympusBlue,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('Fechar'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao carregar status de check-in: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _inserirPlacar(Map<String, dynamic> evento) async {
    final setFormat = evento['set_format'] ?? '1 Set';
    int totalSets = 1;
    int setsNeededToWin = 1;
    if (setFormat.contains('3')) {
      totalSets = 3;
      setsNeededToWin = 2;
    } else if (setFormat.contains('5')) {
      totalSets = 5;
      setsNeededToWin = 3;
    }
    final olympusControllers = List<TextEditingController>.generate(
        totalSets, (i) => TextEditingController());
    final opponentControllers = List<TextEditingController>.generate(
        totalSets, (i) => TextEditingController());
    final existingScore = evento['score'] as Map<String, dynamic>?;
    if (existingScore != null) {
      final olympusSets = existingScore['olympus'] as List<dynamic>? ?? [];
      final opponentSets = existingScore['opponent'] as List<dynamic>? ?? [];
      for (int i = 0; i < olympusControllers.length; i++) {
        if (i < olympusSets.length) {
          olympusControllers[i].text = olympusSets[i].toString();
        }
      }
      for (int i = 0; i < opponentControllers.length; i++) {
        if (i < opponentSets.length) {
          opponentControllers[i].text = opponentSets[i].toString();
        }
      }
    }
    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => Dialog(
          elevation: 8,
          shadowColor: olympusGold.withOpacity(0.3),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  olympusBlue,
                  olympusBlue.withOpacity(0.95),
                  Colors.white,
                ],
                stops: const [0.0, 0.15, 0.15],
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: olympusGold,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: olympusGold.withOpacity(0.5),
                              blurRadius: 15,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: Icon(
                          Icons.sports_volleyball,
                          color: olympusBlue,
                          size: 32,
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Inserir Placar',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: olympusGold.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: olympusGold.withOpacity(0.5),
                            width: 1.5,
                          ),
                        ),
                        child: Text(
                          'Formato: $setFormat',
                          style: TextStyle(
                            color: olympusGold,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        ...List.generate(totalSets, (index) {
                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  olympusGold.withOpacity(0.05),
                                  olympusGold.withOpacity(0.1),
                                ],
                              ),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: olympusGold.withOpacity(0.3),
                                width: 1.5,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: olympusGold.withOpacity(0.1),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Column(
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: olympusBlue.withOpacity(0.1),
                                          borderRadius:
                                              BorderRadius.circular(8),
                                        ),
                                        child: Text(
                                          'Olympus',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color: olympusBlue,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                      ),
                                      child: Text(
                                        'VS',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: olympusGold,
                                          fontSize: 14,
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.grey[200],
                                          borderRadius:
                                              BorderRadius.circular(8),
                                        ),
                                        child: Text(
                                          'Adversário',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color: Colors.grey[700],
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  '${index + 1}° Set',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: olympusGold,
                                    fontSize: 16,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    Expanded(
                                      child: TextField(
                                        controller: olympusControllers[index],
                                        keyboardType: TextInputType.number,
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 18,
                                          color: olympusBlue,
                                        ),
                                        decoration: InputDecoration(
                                          border: OutlineInputBorder(
                                            borderRadius:
                                                BorderRadius.circular(12),
                                            borderSide: BorderSide(
                                              color:
                                                  olympusBlue.withOpacity(0.3),
                                            ),
                                          ),
                                          enabledBorder: OutlineInputBorder(
                                            borderRadius:
                                                BorderRadius.circular(12),
                                            borderSide: BorderSide(
                                              color:
                                                  olympusBlue.withOpacity(0.3),
                                            ),
                                          ),
                                          focusedBorder: OutlineInputBorder(
                                            borderRadius:
                                                BorderRadius.circular(12),
                                            borderSide: const BorderSide(
                                              color: olympusGold,
                                              width: 2,
                                            ),
                                          ),
                                          filled: true,
                                          fillColor:
                                              olympusBlue.withOpacity(0.05),
                                          contentPadding:
                                              const EdgeInsets.symmetric(
                                            vertical: 12,
                                            horizontal: 16,
                                          ),
                                        ),
                                        onChanged: (value) {
                                          setDialogState(() {});
                                        },
                                      ),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                      ),
                                      child: Icon(
                                        Icons.remove,
                                        color: Colors.grey[400],
                                      ),
                                    ),
                                    Expanded(
                                      child: TextField(
                                        controller: opponentControllers[index],
                                        keyboardType: TextInputType.number,
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 18,
                                          color: Colors.grey[700],
                                        ),
                                        decoration: InputDecoration(
                                          border: OutlineInputBorder(
                                            borderRadius:
                                                BorderRadius.circular(12),
                                            borderSide: BorderSide(
                                              color: Colors.grey[300]!,
                                            ),
                                          ),
                                          enabledBorder: OutlineInputBorder(
                                            borderRadius:
                                                BorderRadius.circular(12),
                                            borderSide: BorderSide(
                                              color: Colors.grey[300]!,
                                            ),
                                          ),
                                          focusedBorder: OutlineInputBorder(
                                            borderRadius:
                                                BorderRadius.circular(12),
                                            borderSide: const BorderSide(
                                              color: olympusGold,
                                              width: 2,
                                            ),
                                          ),
                                          filled: true,
                                          fillColor: Colors.grey[50],
                                          contentPadding:
                                              const EdgeInsets.symmetric(
                                            vertical: 12,
                                            horizontal: 16,
                                          ),
                                        ),
                                        onChanged: (value) {
                                          setDialogState(() {});
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: const BorderRadius.only(
                      bottomLeft: Radius.circular(20),
                      bottomRight: Radius.circular(20),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 10,
                        offset: const Offset(0, -2),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          onPressed: () => Navigator.pop(context),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: BorderSide(color: Colors.grey[300]!),
                            ),
                          ),
                          child: Text(
                            'Cancelar',
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: ElevatedButton(
                          onPressed: () async {
                            final olympusSets = olympusControllers
                                .map((c) => c.text.isNotEmpty
                                    ? int.tryParse(c.text) ?? 0
                                    : null)
                                .toList();
                            final opponentSets = opponentControllers
                                .map((c) => c.text.isNotEmpty
                                    ? int.tryParse(c.text) ?? 0
                                    : null)
                                .toList();
                            int setsFilled = 0;
                            for (int i = 0; i < totalSets; i++) {
                              if (olympusSets[i] != null &&
                                  opponentSets[i] != null) {
                                setsFilled++;
                              }
                            }
                            if (setsFilled == 0) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Preencha pelo menos um set'),
                                  backgroundColor: Colors.red,
                                ),
                              );
                              return;
                            }
                            int olympusWins = 0;
                            int opponentWins = 0;
                            for (int i = 0; i < totalSets; i++) {
                              if (olympusSets[i] != null &&
                                  opponentSets[i] != null) {
                                if (olympusSets[i]! > opponentSets[i]!) {
                                  olympusWins++;
                                } else if (opponentSets[i]! > olympusSets[i]!) {
                                  opponentWins++;
                                }
                              }
                            }
                            bool hasWinner = olympusWins >= setsNeededToWin ||
                                opponentWins >= setsNeededToWin;
                            if (!hasWinner && totalSets > 1) {
                              bool allSetsFilled = true;
                              for (int i = 0; i < totalSets; i++) {
                                if (olympusSets[i] == null ||
                                    opponentSets[i] == null) {
                                  allSetsFilled = false;
                                  break;
                                }
                              }
                              if (!allSetsFilled) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Preencha todos os sets! '
                                        'Melhor de $totalSets: vence quem ganhar $setsNeededToWin sets primeiro.'),
                                    backgroundColor: Colors.red,
                                  ),
                                );
                                return;
                              }
                            }
                            String winner = '';
                            if (olympusWins >= setsNeededToWin) {
                              winner = 'Olympus';
                            } else if (opponentWins >= setsNeededToWin) {
                              winner = 'Adversário';
                            } else if (setsFilled == totalSets) {
                              if (olympusWins > opponentWins) {
                                winner = 'Olympus';
                              } else if (opponentWins > olympusWins) {
                                winner = 'Adversário';
                              } else {
                                int olympusTotalPoints = olympusSets
                                    .where((s) => s != null)
                                    .fold(0, (sum, s) => sum + s!);
                                int opponentTotalPoints = opponentSets
                                    .where((s) => s != null)
                                    .fold(0, (sum, s) => sum + s!);
                                winner =
                                    olympusTotalPoints > opponentTotalPoints
                                        ? 'Olympus'
                                        : 'Adversário';
                              }
                            }
                            final finalOlympusSets = olympusSets
                                .where((s) => s != null)
                                .map((s) => s!)
                                .toList();
                            final finalOpponentSets = opponentSets
                                .where((s) => s != null)
                                .map((s) => s!)
                                .toList();
                            try {
                              await _supabase.from('events').update({
                                'score': {
                                  'olympus': finalOlympusSets,
                                  'opponent': finalOpponentSets,
                                  'winner': winner,
                                  'olympus_sets_won': olympusWins,
                                  'opponent_sets_won': opponentWins,
                                },
                              }).eq('id', evento['id']);
                              if (mounted) {
                                Navigator.pop(context);
                                _refreshEventos();
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                        'Placar inserido! Vitória: $winner ($olympusWins x $opponentWins)'),
                                    backgroundColor: winner == 'Olympus'
                                        ? Colors.green
                                        : Colors.orange,
                                  ),
                                );
                              }
                            } catch (e) {
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Erro ao salvar placar: $e'),
                                    backgroundColor: Colors.red,
                                  ),
                                );
                              }
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: olympusGold,
                            foregroundColor: olympusBlue,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 4,
                            shadowColor: olympusGold.withOpacity(0.4),
                          ),
                          child: const Text(
                            'Salvar Placar',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              letterSpacing: 0.5,
                            ),
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
    for (var c in olympusControllers) c.dispose();
    for (var c in opponentControllers) c.dispose();
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

  void _togglePlacarExpandido(String eventId) {
    setState(() {
      if (_placaresExpandidos.contains(eventId)) {
        _placaresExpandidos.remove(eventId);
      } else {
        _placaresExpandidos.add(eventId);
      }
    });
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
        backgroundColor: olympusBlue,
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
          // ✅ FILTROS MODERNOS COM CORES OLYMPUS
          Container(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  olympusBlue,
                  olympusLightBlue,
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(24),
                bottomRight: Radius.circular(24),
              ),
            ),
            child: Column(
              children: [
                // Filtro de Mês e Gênero
                Row(
                  children: [
                    Expanded(
                      child: _buildModernDropdown(
                        icon: Icons.calendar_month,
                        value: _filtroMes,
                        hint: 'Mês',
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
                                    ? olympusBlue
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
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildModernDropdown(
                        icon: Icons.people_outline,
                        value: _filtroGenero == 'Todos' ? null : _filtroGenero,
                        hint: 'Gênero',
                        items: const [
                          DropdownMenuItem(
                              value: 'Todos', child: Text('Todos')),
                          DropdownMenuItem(
                              value: 'masculino', child: Text('Masculino')),
                          DropdownMenuItem(
                              value: 'feminino', child: Text('Feminino')),
                        ],
                        onChanged: (valor) {
                          setState(() {
                            _filtroGenero = valor ?? 'Todos';
                            _aplicarFiltros();
                          });
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Filtro de Tipo com Chips Modernos
                _buildModernChipFilter(
                  label: 'Tipo de Evento',
                  icon: Icons.filter_list,
                  options: const [
                    {'value': 'Todos', 'label': 'Todos'},
                    {'value': 'Treino', 'label': 'Treino'},
                    {'value': 'Amistoso', 'label': 'Amistoso'},
                    {'value': 'Campeonato', 'label': 'Campeonato'},
                  ],
                  selectedValue: _filtroSelecionado,
                  onSelected: (value) {
                    setState(() {
                      _filtroSelecionado = value;
                      _aplicarFiltros();
                    });
                  },
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
                            Text(_error!,
                                style: const TextStyle(color: Colors.red)),
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
                                Text(
                                  'Nenhum evento encontrado',
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
                                final eventId = evento['id']?.toString() ?? '';
                                final quantidades =
                                    _quantidadeConvocados[eventId] ??
                                        {'athletes': 0, 'technicians': 0};
                                // ✅ CORREÇÃO PRINCIPAL: total vem da view (se existir), senão fallback
                                final stats = _convocationStats[eventId];
                                final totalConvocados = stats != null
                                    ? (stats['total_convocados'] ?? 0)
                                    : (quantidades['athletes']! +
                                        quantidades['technicians']!);
                                // ✅ NOVO: dados de convocações para exibição no card
                                final aceitos = stats?['total_aceitos'] ?? 0;
                                final pendentes =
                                    stats?['total_pendentes'] ?? 0;
                                final recusados =
                                    stats?['total_recusados'] ?? 0;
                                final checkinData = _checkinInfo[eventId];
                                final allowCheckin =
                                    evento['allow_checkin'] ?? false;
                                final corTipo = _getCorTipoEvento(
                                    evento['event_type'] ?? '');
                                final eventType = evento['event_type'] ?? '';
                                final hasPlacar = evento['score'] != null;
                                final genero = evento['gender'] ?? '';
                                // ✅ NOVO: Nome do campeonato
                                final championshipName =
                                    evento['championship_name'] ?? '';
                                // ✅ NOVO: montar endereço completo
                                String? enderecoCompleto;
                                if (evento['street'] != null &&
                                    evento['street'].toString().isNotEmpty) {
                                  final rua = evento['street'] ?? '';
                                  final numero = evento['street_number'] ?? '';
                                  final bairro = evento['neighborhood'] ?? '';
                                  final cidade = evento['city'] ?? '';
                                  final estado = evento['state'] ?? '';
                                  enderecoCompleto = '$rua, $numero'
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
                                  color: _getCorFundoCard(genero),
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
                                                (eventType ?? 'Geral')
                                                    .toUpperCase(),
                                                style: TextStyle(
                                                  color: corTipo,
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 12,
                                                ),
                                              ),
                                            ),
                                            const Spacer(),
                                            if (genero.isNotEmpty)
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                  horizontal: 8,
                                                  vertical: 4,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: genero.toLowerCase() ==
                                                          'masculino'
                                                      ? Colors.blue[100]
                                                      : Colors.purple[100],
                                                  borderRadius:
                                                      BorderRadius.circular(12),
                                                ),
                                                child: Text(
                                                  genero[0].toUpperCase() +
                                                      genero.substring(1),
                                                  style: TextStyle(
                                                    color:
                                                        genero.toLowerCase() ==
                                                                'masculino'
                                                            ? Colors.blue[900]
                                                            : Colors
                                                                .purple[900],
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ),
                                            const SizedBox(width: 8),
                                            PopupMenuButton<String>(
                                              icon: Icon(
                                                Icons.more_vert,
                                                color: Colors.grey[600],
                                              ),
                                              onSelected: (value) {
                                                if (value == 'editar') {
                                                  _editarEvento(evento);
                                                } else if (value == 'placar') {
                                                  _inserirPlacar(evento);
                                                } else if (value == 'checkin') {
                                                  _mostrarCheckinDetalhes(
                                                      evento);
                                                } else if (value ==
                                                    'status_checkin') {
                                                  _mostrarStatusCheckin(evento);
                                                } else if (value ==
                                                    'exportar') {
                                                  // ✅ NOVO: Exportar convocados para Excel
                                                  _exportarConvocados(evento);
                                                } else if (value == 'excluir') {
                                                  // ✅ NOVO: Opção excluir
                                                  _excluirEvento(evento);
                                                }
                                              },
                                              itemBuilder: (context) {
                                                final items =
                                                    <PopupMenuItem<String>>[];
                                                items.add(const PopupMenuItem(
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
                                                ));
                                                if (eventType == 'amistoso' ||
                                                    eventType == 'campeonato') {
                                                  items.add(PopupMenuItem(
                                                    value: 'placar',
                                                    child: Row(
                                                      children: [
                                                        Icon(
                                                          Icons.score,
                                                          size: 18,
                                                          color: olympusGold,
                                                        ),
                                                        SizedBox(width: 8),
                                                        Text(hasPlacar
                                                            ? 'Editar placar'
                                                            : 'Inserir placar'),
                                                      ],
                                                    ),
                                                  ));
                                                }
                                                if (allowCheckin) {
                                                  items.add(PopupMenuItem(
                                                    value: 'checkin',
                                                    child: Row(
                                                      children: [
                                                        Icon(
                                                          Icons.people_outline,
                                                          size: 18,
                                                          color: Colors.green,
                                                        ),
                                                        SizedBox(width: 8),
                                                        Text('Ver convocados'),
                                                      ],
                                                    ),
                                                  ));
                                                  items.add(PopupMenuItem(
                                                    value: 'status_checkin',
                                                    child: Row(
                                                      children: [
                                                        Icon(
                                                          Icons
                                                              .check_circle_outline,
                                                          size: 18,
                                                          color: olympusGold,
                                                        ),
                                                        SizedBox(width: 8),
                                                        Text(
                                                            'Ver status check-in'),
                                                      ],
                                                    ),
                                                  ));
                                                }
                                                // ✅ NOVO: Opção exportar para Excel
                                                items.add(PopupMenuItem(
                                                  value: 'exportar',
                                                  child: Row(
                                                    children: [
                                                      Icon(
                                                        Icons.file_download,
                                                        size: 18,
                                                        color: Colors.green,
                                                      ),
                                                      SizedBox(width: 8),
                                                      Text(
                                                          '📤 Exportar para Excel'),
                                                    ],
                                                  ),
                                                ));
                                                // ✅ NOVO: Opção excluir no menu
                                                items.add(PopupMenuItem(
                                                  value: 'excluir',
                                                  child: Row(
                                                    children: [
                                                      Icon(
                                                        Icons.delete_outline,
                                                        size: 18,
                                                        color: Colors.red,
                                                      ),
                                                      SizedBox(width: 8),
                                                      Text(
                                                        'Excluir evento',
                                                        style: TextStyle(
                                                            color: Colors.red),
                                                      ),
                                                    ],
                                                  ),
                                                ));
                                                return items;
                                              },
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 12),
                                        Text(
                                          evento['event_name'] ?? 'Sem nome',
                                          style: const TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        // ✅ NOVO: Exibir nome do campeonato se existir
                                        if (eventType == 'campeonato' &&
                                            championshipName != null &&
                                            championshipName.isNotEmpty) ...[
                                          const SizedBox(height: 4),
                                          Row(
                                            children: [
                                              Icon(
                                                Icons.emoji_events,
                                                size: 16,
                                                color: Colors.amber[700],
                                              ),
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
                                        // ✅ ENDEREÇO MOVIDO PARA ABAIXO DO RELÓGIO
                                        if (enderecoCompleto != null) ...[
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
                                        Row(
                                          children: [
                                            const Icon(
                                              Icons.people_outline,
                                              size: 16,
                                              color: olympusGold,
                                            ),
                                            const SizedBox(width: 8),
                                            Text(
                                              '$totalConvocados convocad${totalConvocados == 1 ? 'o' : 'os'} (${quantidades['athletes']} atletas, ${quantidades['technicians']} técn${quantidades['technicians'] == 1 ? 'ico' : 'icos'})',
                                              style: const TextStyle(
                                                color: olympusBlue,
                                                fontWeight: FontWeight.w600,
                                                fontSize: 14,
                                              ),
                                            ),
                                          ],
                                        ),
                                        // ✅ NOVO: Status das convocações (aceitos, pendentes, recusados)
                                        if (stats != null) ...[
                                          const SizedBox(height: 4),
                                          Row(
                                            children: [
                                              Icon(
                                                Icons.check_circle_outline,
                                                size: 16,
                                                color: Colors.green[600],
                                              ),
                                              const SizedBox(width: 4),
                                              Text(
                                                '$aceitos aceitou',
                                                style: TextStyle(
                                                  color: Colors.green[700],
                                                  fontWeight: FontWeight.w600,
                                                  fontSize: 13,
                                                ),
                                              ),
                                              const SizedBox(width: 12),
                                              Icon(
                                                Icons.hourglass_empty,
                                                size: 16,
                                                color: Colors.orange[600],
                                              ),
                                              const SizedBox(width: 4),
                                              Text(
                                                '$pendentes pendente${pendentes == 1 ? '' : 's'}',
                                                style: TextStyle(
                                                  color: Colors.orange[700],
                                                  fontWeight: FontWeight.w600,
                                                  fontSize: 13,
                                                ),
                                              ),
                                              const SizedBox(width: 12),
                                              Icon(
                                                Icons.cancel_outlined,
                                                size: 16,
                                                color: Colors.red[600],
                                              ),
                                              const SizedBox(width: 4),
                                              Text(
                                                '$recusados recusou',
                                                style: TextStyle(
                                                  color: Colors.red[700],
                                                  fontWeight: FontWeight.w600,
                                                  fontSize: 13,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                        if (allowCheckin &&
                                            checkinData != null) ...[
                                          const SizedBox(height: 4),
                                          Row(
                                            children: [
                                              Icon(
                                                Icons.check_circle,
                                                size: 16,
                                                color: Colors.green[600],
                                              ),
                                              const SizedBox(width: 8),
                                              Text(
                                                'Check-in: ${checkinData['checked_in']} fizeram check-in',
                                                style: TextStyle(
                                                  color: Colors.green[700],
                                                  fontWeight: FontWeight.w600,
                                                  fontSize: 13,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                        if (hasPlacar) ...[
                                          const SizedBox(height: 12),
                                          _buildPlacarCard(evento, eventId),
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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _navegarParaCadastroEvento,
        icon: const Icon(Icons.add),
        label: const Text('Cadastrar Evento'),
        backgroundColor: olympusGold,
        foregroundColor: olympusBlue,
      ),
    );
  }

  Widget _buildPlacarCard(Map<String, dynamic> evento, String eventId) {
    final score = evento['score'] as Map<String, dynamic>?;
    if (score == null) return const SizedBox.shrink();
    final olympusSets = score['olympus'] as List<dynamic>? ?? [];
    final opponentSets = score['opponent'] as List<dynamic>? ?? [];
    final winner = score['winner'] as String?;
    final olympusSetsWon = score['olympus_sets_won'] as int? ?? 0;
    final opponentSetsWon = score['opponent_sets_won'] as int? ?? 0;
    final isVictory = winner == 'Olympus';
    final isExpandido = _placaresExpandidos.contains(eventId);
    return GestureDetector(
      onTap: () => _togglePlacarExpandido(eventId),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isVictory
                ? [Colors.green[50]!, Colors.green[100]!]
                : [Colors.orange[50]!, Colors.orange[100]!],
          ),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isVictory ? Colors.green[700]! : Colors.orange[700]!,
            width: 2,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isVictory ? Icons.emoji_events : Icons.sentiment_dissatisfied,
                  color: isVictory ? Colors.green[700] : Colors.orange[700],
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  isVictory ? 'VITÓRIA' : 'DERROTA',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: isVictory ? Colors.green[700] : Colors.orange[700],
                    fontSize: 14,
                  ),
                ),
                const Spacer(),
                Row(
                  children: [
                    Text(
                      '$olympusSetsWon x $opponentSetsWon em Sets',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.grey[700],
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      isExpandido
                          ? Icons.keyboard_arrow_up
                          : Icons.keyboard_arrow_down,
                      color: Colors.grey[600],
                      size: 20,
                    ),
                  ],
                ),
              ],
            ),
            if (isExpandido) ...[
              const SizedBox(height: 12),
              ...List.generate(olympusSets.length, (index) {
                final olympusScore = olympusSets[index];
                final opponentScore =
                    opponentSets.length > index ? opponentSets[index] : 0;
                final olympusWonSet = olympusScore > opponentScore;
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding:
                      const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                  decoration: BoxDecoration(
                    color: olympusWonSet
                        ? olympusBlue.withOpacity(0.1)
                        : Colors.grey[100],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: olympusWonSet
                          ? olympusBlue.withOpacity(0.3)
                          : Colors.grey[300]!,
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '${index + 1}° Set',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.grey[700],
                          fontSize: 12,
                        ),
                      ),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: olympusWonSet
                                  ? olympusBlue.withOpacity(0.2)
                                  : Colors.grey[200],
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              olympusScore.toString(),
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: olympusWonSet
                                    ? olympusBlue
                                    : Colors.grey[700],
                              ),
                            ),
                          ),
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 8),
                            child: Text(
                              'x',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.grey,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: !olympusWonSet
                                  ? Colors.orange[100]
                                  : Colors.grey[200],
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              opponentScore.toString(),
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: !olympusWonSet
                                    ? Colors.orange[900]
                                    : Colors.grey[700],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              }),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildFiltroButton(String tipo, IconData icone) {
    final bool selecionado = _filtroSelecionado == tipo;
    final Color corBase = tipo == 'Campeonato'
        ? olympusGold
        : tipo == 'Treino'
            ? olympusBlue
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
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        decoration: BoxDecoration(
          color: selecionado ? corBase.withOpacity(0.15) : Colors.grey[100],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selecionado ? corBase : Colors.grey[300]!,
            width: 2,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (selecionado) Icon(Icons.check, size: 14, color: corBase),
            if (selecionado) const SizedBox(width: 2),
            Icon(icone,
                size: 14, color: selecionado ? corBase : Colors.grey[600]),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                tipo,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontWeight: selecionado ? FontWeight.bold : FontWeight.normal,
                  color: selecionado ? corBase : Colors.grey[700],
                  fontSize: 11,
                ),
                overflow: TextOverflow.ellipsis,
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
      shape: const RoundedRectangleBorder(
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
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: olympusBlue,
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
                    if (evento['score'] != null) ...[
                      const SizedBox(height: 8),
                      _buildPlacarCard(evento, evento['id'].toString()),
                    ],
                    if (evento['street'] != null) ...[
                      const Divider(),
                      const Text('Localização',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: olympusBlue,
                          )),
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
                        style: ElevatedButton.styleFrom(
                          backgroundColor: olympusBlue,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text('Fechar'),
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
          Icon(icon, size: 20, color: olympusGold),
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
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: olympusBlue,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ✅ NOVO: Widget de Dropdown Moderno com cores Olympus
  Widget _buildModernDropdown({
    required IconData icon,
    required dynamic value,
    required String hint,
    required List<DropdownMenuItem<dynamic>> items,
    required ValueChanged<dynamic> onChanged,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            spreadRadius: 1,
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 16,
                  color: olympusGold,
                ),
                const SizedBox(width: 6),
                Text(
                  hint,
                  style: TextStyle(
                    fontSize: 11,
                    color: olympusGold.withOpacity(0.8),
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<dynamic>(
                value: value,
                hint: Text(
                  hint,
                  style: TextStyle(color: Colors.grey[600]),
                ),
                isExpanded: true,
                items: items,
                onChanged: onChanged,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF2C3E5A),
                ),
                icon: Icon(
                  Icons.keyboard_arrow_down_rounded,
                  color: olympusGold,
                  size: 20,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  // ✅ NOVO: Widget de Filtro com Chips Modernos
  Widget _buildModernChipFilter({
    required String label,
    required IconData icon,
    required List<Map<String, dynamic>> options,
    required String selectedValue,
    required ValueChanged<String> onSelected,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            spreadRadius: 1,
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 16,
                  color: olympusGold,
                ),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    color: olympusGold.withOpacity(0.8),
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: options.map((option) {
                final value = option['value'] as String;
                final labelText = option['label'] as String;
                final selected = selectedValue == value;

                Color chipColor;
                switch (value) {
                  case 'Campeonato':
                    chipColor = olympusGold;
                    break;
                  case 'Treino':
                    chipColor = olympusBlue;
                    break;
                  case 'Amistoso':
                    chipColor = Colors.green;
                    break;
                  default:
                    chipColor = olympusBlue;
                }

                return ChoiceChip(
                  label: Text(labelText),
                  selected: selected,
                  selectedColor: chipColor.withOpacity(0.2),
                  labelStyle: TextStyle(
                    color: selected ? chipColor : Colors.grey[700],
                    fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                    fontSize: 13,
                  ),
                  onSelected: (_) => onSelected(value),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

enum EventType { treino, amistoso, campeonato }
