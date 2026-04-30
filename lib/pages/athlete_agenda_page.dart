import 'dart:ui';
import 'dart:convert';
import 'dart:math' show sin, cos, sqrt, asin;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/permission_service.dart';

class AthleteAgendaPage extends StatefulWidget {
  const AthleteAgendaPage({Key? key}) : super(key: key);

  @override
  State<AthleteAgendaPage> createState() => _AthleteAgendaPageState();
}

class _AthleteAgendaPageState extends State<AthleteAgendaPage> {
  final SupabaseClient _supabase = Supabase.instance.client;
  final PermissionService _permissionService = PermissionService();

  List<Map<String, dynamic>> _eventos = [];
  List<Map<String, dynamic>> _eventosFiltrados = [];
  Map<String, Map<String, String>> _convocationStatus = {};
  bool _loading = true;
  String? _error;
  String _filtroMes = '';
  String _filtroTipo = 'todos';
  String _filtroStatus = 'todos';
  Map<String, int> _statusCounts = {
    'accepted': 0,
    'rejected': 0,
    'pending': 0,
  };
  Map<String, Map<String, int>> _typeStatusCounts = {
    'treino': {
      'accepted': 0,
      'rejected': 0,
      'pending': 0,
    },
    'amistoso': {
      'accepted': 0,
      'rejected': 0,
      'pending': 0,
    },
    'campeonato': {
      'accepted': 0,
      'rejected': 0,
      'pending': 0,
    },
  };

  bool _hasPermission = false;
  bool _checkingPermission = true;

  bool _showMonthFilter = true;
  bool _showStatusFilter = true;
  List<String> _allowedEventTypes = ['treino', 'amistoso', 'campeonato'];
  bool _canViewConvocados = false;
  bool _canExportDadosJogo = false;

  static const Color olympusBlue = Color(0xFF1E3A5F);
  static const Color olympusGold = Color(0xFFD4AF37);
  static const Color olympusLightBlue = Color(0xFF2C5F8D);
  static const String _geocodeAccessKey = 'pk.5a7a05184e41c916429dceb50cf02718';
  static const String _eventsEmbedFk = 'convocations_event_id_fkey';

  @override
  void initState() {
    super.initState();
    _checkPermission();
  }

  Future<void> _checkPermission() async {
    final user = _supabase.auth.currentUser;
    if (user == null) {
      if (mounted) {
        Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
      }
      return;
    }

    final hasAccess = await _permissionService.hasAccess(user.id, 'agenda');

    if (!mounted) return;

    setState(() {
      _hasPermission = hasAccess;
      _checkingPermission = false;
    });

    if (hasAccess) {
      _loadAgendaFilters();
    }
  }

  Future<void> _loadAgendaFilters() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    final filters = await _permissionService.getAgendaFilters(user.id);

    if (!mounted) return;
    setState(() {
      _showMonthFilter = filters['show_month_filter'] ?? true;
      _showStatusFilter = filters['show_status_filter'] ?? true;
      _allowedEventTypes = filters['allowed_event_types'] != null
          ? List<String>.from(filters['allowed_event_types'])
          : ['treino', 'amistoso', 'campeonato'];
      _canViewConvocados = filters['ver_convocados'] == true;
      _canExportDadosJogo = filters['exportar_dados_jogo'] == true;
    });

    _setMesAtual();
    _buscarEventos();
  }

  void _setMesAtual() {
    final now = DateTime.now();
    _filtroMes = '${now.month.toString().padLeft(2, '0')}/${now.year}';
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.red.shade700,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  void _showSuccess(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle_outline, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.green.shade700,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  double _calcularDistanciaMetros(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const double raioTerra = 6371000;
    final dLat = _degToRad(lat2 - lat1);
    final dLon = _degToRad(lon2 - lon1);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_degToRad(lat1)) *
            cos(_degToRad(lat2)) *
            sin(dLon / 2) *
            sin(dLon / 2);
    final c = 2 * asin(sqrt(a));
    return raioTerra * c;
  }

  double _degToRad(double deg) {
    return deg * (3.141592653589793 / 180.0);
  }

  Future<Map<String, String>> _buscarCheckinsDoUsuario(
    String userId,
    List<String> eventIds,
  ) async {
    if (eventIds.isEmpty) return {};
    final rows = await _supabase
        .from('checkins')
        .select('event_id, check_in_status')
        .eq('user_id', userId)
        .inFilter('event_id', eventIds);
    final map = <String, String>{};
    for (final r in rows) {
      final eid = (r['event_id'] ?? '').toString();
      if (eid.isEmpty) continue;
      map[eid] = _normalizarCheckInStatus(r['check_in_status']);
    }
    return map;
  }

  String _normalizarCheckInStatus(dynamic status) {
    final value = (status ?? '').toString().trim().toLowerCase();
    if (value.isEmpty) return '';
    if ([
      'ok',
      'realizado',
      'realizado com sucesso',
      'checked_in',
      'checkin_realizado',
      'success',
      'completed',
      'done',
    ].contains(value)) {
      return 'realizado';
    }
    if (['pending', 'pendente'].contains(value)) {
      return 'pendente';
    }
    return value;
  }

  bool _isCheckInRealizado(dynamic status) {
    return _normalizarCheckInStatus(status) == 'realizado';
  }

  Future<void> _sincronizarCheckInStatus(
    String eventId,
    String userId,
  ) async {
    try {
      final existing = await _supabase
          .from('checkins')
          .select('event_id')
          .eq('event_id', eventId)
          .eq('user_id', userId)
          .limit(1);

      if (existing.isNotEmpty) {
        await _supabase
            .from('checkins')
            .update({'check_in_status': 'realizado'})
            .eq('event_id', eventId)
            .eq('user_id', userId);
      } else {
        await _supabase.from('checkins').insert({
          'event_id': eventId,
          'user_id': userId,
          'check_in_status': 'realizado',
        });
      }
    } catch (e) {
      print('❌ Erro ao sincronizar status do check-in no Supabase: $e');
    }
  }

  String _normalizarTipoResumo(Map<String, dynamic> evento) {
    final tipo = (evento['event_type'] ?? '').toString().toLowerCase().trim();

    if (tipo == 'treino') {
      return 'treino';
    }

    if (tipo == 'amistoso') {
      return 'amistoso';
    }

    if (tipo == 'campeonato') {
      return 'campeonato';
    }

    return '';
  }

  String _normalizarConvocationStatus(dynamic status) {
    final value = (status ?? '').toString().toLowerCase().trim();
    switch (value) {
      case 'accepted':
      case 'rejected':
      case 'pending':
        return value;
      default:
        return 'pending';
    }
  }

  int _statusPriority(String status) {
    switch (_normalizarConvocationStatus(status)) {
      case 'accepted':
        return 3;
      case 'rejected':
        return 2;
      default:
        return 1;
    }
  }

  String _resolverStatusConvocacao(String atual, String novo) {
    return _statusPriority(novo) >= _statusPriority(atual) ? novo : atual;
  }

  List<Map<String, dynamic>> _getEventosDoMesAtual() {
    if (_filtroMes.isEmpty) return List<Map<String, dynamic>>.from(_eventos);
    return _eventos.where((evento) {
      final dataEvento = (evento['event_date'] ?? '').toString();
      if (dataEvento.length >= 7) {
        final mesAnoEvento = dataEvento.substring(3);
        return mesAnoEvento == _filtroMes;
      }
      return false;
    }).toList();
  }

  List<Map<String, dynamic>> _getEventosBaseFiltro() {
    if (_filtroMes.isEmpty) return List<Map<String, dynamic>>.from(_eventos);
    return _getEventosDoMesAtual();
  }

  bool get _isVisaoGeral => _filtroMes.isEmpty;

  String _getMesAtual() {
    final now = DateTime.now();
    return '${now.month.toString().padLeft(2, '0')}/${now.year}';
  }

  void _alternarVisaoGeral() {
    setState(() {
      if (_isVisaoGeral) {
        _filtroMes = _getMesAtual();
      } else {
        _filtroMes = '';
      }
      _filtroTipo = 'todos';
      _filtroStatus = 'todos';
      _aplicarFiltros();
    });
  }

  void _selecionarMes(String mes) {
    setState(() {
      _filtroMes = mes;
      _filtroTipo = 'todos';
      _filtroStatus = 'todos';
      _aplicarFiltros();
    });
  }

  void _atualizarResumoPorTipo() {
    final counts = {'accepted': 0, 'rejected': 0, 'pending': 0};
    final typeCounts = {
      'treino': {'accepted': 0, 'rejected': 0, 'pending': 0},
      'amistoso': {'accepted': 0, 'rejected': 0, 'pending': 0},
      'campeonato': {'accepted': 0, 'rejected': 0, 'pending': 0},
    };

    for (final evento in _getEventosBaseFiltro()) {
      final status =
          (evento['convocation_status'] ?? 'pending').toString().toLowerCase();
      if (counts.containsKey(status)) {
        counts[status] = counts[status]! + 1;
      }

      final tipoResumo = _normalizarTipoResumo(evento);
      if (tipoResumo.isNotEmpty && typeCounts.containsKey(tipoResumo)) {
        typeCounts[tipoResumo]![status] =
            (typeCounts[tipoResumo]![status] ?? 0) + 1;
      }
    }

    _statusCounts = counts;
    _typeStatusCounts = typeCounts;
  }

  void _selecionarResumo(String tipo, String status) {
    final filtroAtivo = _filtroTipo == tipo && _filtroStatus == status;

    setState(() {
      if (filtroAtivo) {
        _filtroTipo = 'todos';
        _filtroStatus = 'todos';
      } else {
        _filtroTipo = tipo;
        _filtroStatus = status;
      }
      _aplicarFiltros();
    });
  }

  void _calcularStatusCounts() {
    setState(() {
      _atualizarResumoPorTipo();
    });
  }

  bool _janelaCheckInEncerrada(Map<String, dynamic> evento) {
    final dataStr = (evento['event_date'] ?? '').toString().trim();
    final horaStr = (evento['event_time'] ?? '').toString().trim();
    if (dataStr.isEmpty || horaStr.isEmpty) return false;
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
      final fimJanela = eventDateTime.add(const Duration(minutes: 30));
      return now.isAfter(fimJanela);
    } catch (_) {
      return false;
    }
  }

  Future<void> _buscarEventos() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) {
        if (!mounted) return;
        setState(() {
          _error = 'Usuário não autenticado';
          _loading = false;
        });
        return;
      }
      final response = await _supabase.from('convocations').select('''
event_id,
status,
events!$_eventsEmbedFk (
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
state,
cep,
latitude,
longitude,
enable_ride_logistics
)
''').eq('user_id', user.id);
      if (response.isEmpty) {
        if (!mounted) return;
        setState(() {
          _eventos = [];
          _eventosFiltrados = [];
          _loading = false;
        });
        return;
      }
      final eventosList = <Map<String, dynamic>>[];
      final statusMap = <String, Map<String, String>>{};
      for (final item in response) {
        final eventData = item['events'];
        final status = _normalizarConvocationStatus(item['status']);
        if (eventData != null) {
          final mapEvento = Map<String, dynamic>.from(eventData);
          final eid = (mapEvento['id'] ?? '').toString();
          if (eid.isEmpty) continue;
          mapEvento['convocation_status'] = status;
          eventosList.add(mapEvento);
          statusMap[eid] = {'status': status};
        }
      }
      final eventIds = eventosList.map((e) => e['id'].toString()).toList();
      final checkinMap = await _buscarCheckinsDoUsuario(user.id, eventIds);
      for (final e in eventosList) {
        final id = e['id'].toString();
        e['check_in_status'] = _normalizarCheckInStatus(checkinMap[id]);
      }
      eventosList.sort((a, b) {
        final dateA = (a['event_date'] ?? '').toString();
        final dateB = (b['event_date'] ?? '').toString();
        final timeA = (a['event_time'] ?? '').toString();
        final timeB = (b['event_time'] ?? '').toString();
        final compare = dateB.compareTo(dateA);
        if (compare != 0) return compare;
        return timeB.compareTo(timeA);
      });
      if (!mounted) return;
      setState(() {
        _eventos = eventosList;
        _convocationStatus = statusMap;
        _aplicarFiltros();
        _loading = false;
      });
      _calcularStatusCounts();
    } catch (e, stackTrace) {
      print('❌ Erro: $e');
      print('❌ Stack: $stackTrace');
      if (!mounted) return;
      setState(() {
        _error = 'Erro ao carregar eventos: $e';
        _loading = false;
      });
    }
  }

  void _aplicarFiltros() {
    var eventosFiltrados = _getEventosBaseFiltro();

    if (_filtroTipo != 'todos') {
      eventosFiltrados = eventosFiltrados.where((evento) {
        final tipo = _normalizarTipoResumo(evento);
        return tipo == _filtroTipo;
      }).toList();
    }

    if (_filtroStatus != 'todos') {
      eventosFiltrados = eventosFiltrados.where((evento) {
        final status = (evento['convocation_status'] ?? 'pending')
            .toString()
            .toLowerCase()
            .trim();
        return status == _filtroStatus;
      }).toList();
    }

    eventosFiltrados.sort((a, b) {
      DateTime parseEvento(Map<String, dynamic> evento) {
        try {
          final data = (evento['event_date'] ?? '').toString().trim();
          final hora = (evento['event_time'] ?? '').toString().trim();
          final dp = data.split('/');
          final tp = hora.split(':');

          if (dp.length == 3 && tp.length >= 2) {
            return DateTime(
              int.parse(dp[2]),
              int.parse(dp[1]),
              int.parse(dp[0]),
              int.parse(tp[0]),
              int.parse(tp[1]),
            );
          }
        } catch (_) {}
        return DateTime(9999);
      }

      return parseEvento(a).compareTo(parseEvento(b));
    });

    _eventosFiltrados = eventosFiltrados;
    _atualizarResumoPorTipo();
  }

  Future<void> _refreshEventos() async {
    await _buscarEventos();
  }

  String _formatarData(String dataStr) {
    try {
      final parts = dataStr.split('/');
      if (parts.length == 3) {
        final date = DateTime(
          int.parse(parts[2]),
          int.parse(parts[1]),
          int.parse(parts[0]),
        );
        final dataFormatada = DateFormat('dd/MM', 'pt_BR').format(date);
        final diaSemana = DateFormat('EEEE', 'pt_BR').format(date);
        final diaSemanaFormatado = diaSemana.isEmpty
            ? ''
            : diaSemana[0].toUpperCase() + diaSemana.substring(1);
        return '$dataFormatada|$diaSemanaFormatado';
      }
      return dataStr;
    } catch (_) {
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

  Color _getCorFundoCard(String genero, String tipo) {
    final t = tipo.toLowerCase().trim();
    if (t == 'treino') return const Color(0xFFE3F2FD);
    if (t == 'amistoso') return const Color(0xFFE8F5E9);
    if (t == 'campeonato') return const Color(0xFFFFF8E1);
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

  String _getResumoTipoLabel(String tipo) {
    switch (tipo) {
      case 'treino':
        return 'Treinos';
      case 'amistoso':
        return 'Amistosos';
      case 'campeonato':
        return 'Liga / Campeonatos';
      default:
        return tipo;
    }
  }

  IconData _getResumoTipoIcon(String tipo) {
    switch (tipo) {
      case 'treino':
        return Icons.fitness_center;
      case 'amistoso':
        return Icons.sports_volleyball;
      case 'campeonato':
        return Icons.emoji_events;
      default:
        return Icons.event;
    }
  }

  Widget _buildResumoStatusChip({
    required String tipo,
    required String status,
    required String label,
    required int count,
    required Color color,
  }) {
    final selected = _filtroTipo == tipo && _filtroStatus == status;

    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => _selecionarResumo(tipo, status),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        constraints: const BoxConstraints(minWidth: 84),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? color.withOpacity(0.18) : color.withOpacity(0.10),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? color : color.withOpacity(0.24),
            width: selected ? 1.2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$label: $count',
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (selected) ...[
              const SizedBox(height: 1),
              const Text(
                'Selecionado',
                style: TextStyle(
                  color: olympusBlue,
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildResumoPorTipoSection() {
    final base = _getEventosBaseFiltro();

    final tiposDisponiveis = ['treino', 'amistoso', 'campeonato'].where((tipo) {
      return base.any((evento) => _normalizarTipoResumo(evento) == tipo);
    }).toList();

    final tipos = _filtroTipo != 'todos' ? [_filtroTipo] : tiposDisponiveis;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Column(
        children: tipos.map((tipo) {
          final counts = _typeStatusCounts[tipo] ??
              const {
                'accepted': 0,
                'rejected': 0,
                'pending': 0,
              };
          final colorBase = _getCorTipoEvento(tipo);

          return Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.96),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: colorBase.withOpacity(0.22)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: colorBase.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        _getResumoTipoIcon(tipo),
                        color: colorBase,
                        size: 15,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _getResumoTipoLabel(tipo),
                        style: const TextStyle(
                          color: olympusBlue,
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _buildResumoStatusChip(
                      tipo: tipo,
                      status: 'accepted',
                      label: 'Aceitou',
                      count: counts['accepted'] ?? 0,
                      color: Colors.green,
                    ),
                    _buildResumoStatusChip(
                      tipo: tipo,
                      status: 'rejected',
                      label: 'Recusou',
                      count: counts['rejected'] ?? 0,
                      color: Colors.red,
                    ),
                    _buildResumoStatusChip(
                      tipo: tipo,
                      status: 'pending',
                      label: 'Pendentes',
                      count: counts['pending'] ?? 0,
                      color: Colors.orange,
                    ),
                  ],
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
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
          horasLimite = 0;
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
    } catch (_) {
      return false;
    }
  }

  String _getPrazoInfo(Map<String, dynamic> evento) {
    final tipo = (evento['event_type'] ?? '').toString().toLowerCase().trim();
    switch (tipo) {
      case 'treino':
        return 'Edição até 3h antes';
      case 'amistoso':
        return 'Edição até 12h antes';
      case 'campeonato':
        return 'Edição até 48h antes';
      default:
        return '';
    }
  }

  Map<String, dynamic> _verificarJanelaCheckIn(Map<String, dynamic> evento) {
    final dataStr = (evento['event_date'] ?? '').toString().trim();
    final horaStr = (evento['event_time'] ?? '').toString().trim();
    if (dataStr.isEmpty || horaStr.isEmpty) {
      return {
        'disponivel': false,
        'mensagem': 'Horário do evento não definido'
      };
    }
    try {
      final dp = dataStr.split('/');
      final tp = horaStr.split(':');
      if (dp.length != 3 || tp.length < 2) {
        return {
          'disponivel': false,
          'mensagem': 'Formato de data/hora inválido'
        };
      }
      final eventDateTime = DateTime(
        int.parse(dp[2]),
        int.parse(dp[1]),
        int.parse(dp[0]),
        int.parse(tp[0]),
        int.parse(tp[1]),
      );
      final now = DateTime.now();
      final inicioJanela = eventDateTime.subtract(const Duration(minutes: 10));
      final fimJanela = eventDateTime.add(const Duration(minutes: 30));
      if (now.isBefore(inicioJanela)) {
        final minutosRestantes = inicioJanela.difference(now).inMinutes;
        return {
          'disponivel': false,
          'mensagem': 'Check-in em $minutosRestantes min',
          'bloqueado': true,
        };
      }
      if (now.isAfter(fimJanela)) {
        return {
          'disponivel': false,
          'mensagem': 'Check-in encerrado',
          'bloqueado': true,
        };
      }
      return {
        'disponivel': true,
        'mensagem': 'Check-in disponível',
        'bloqueado': false,
      };
    } catch (_) {
      return {'disponivel': false, 'mensagem': 'Erro ao verificar horário'};
    }
  }

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
    Map<String, dynamic> evento,
    bool aceitar,
  ) async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;
      final eventId = evento['id'];
      if (aceitar) {
        final tipoEvento =
            (evento['event_type'] ?? '').toString().toLowerCase().trim();
        final rideEnabled = evento['enable_ride_logistics'] == true;
        if (tipoEvento == 'campeonato' && rideEnabled) {
          final rideData = await _showRideDialog();
          if (rideData == null) return;
          await _supabase.from('event_rides').insert({
            'event_id': eventId,
            'user_id': user.id,
            'ride_type': 'ida',
            ...Map<String, dynamic>.from(rideData['ida'] as Map),
          });
          await _supabase.from('event_rides').insert({
            'event_id': eventId,
            'user_id': user.id,
            'ride_type': 'volta',
            ...Map<String, dynamic>.from(rideData['volta'] as Map),
          });
        }
        await _supabase
            .from('convocations')
            .update({'status': 'accepted', 'justification': null})
            .eq('event_id', eventId)
            .eq('user_id', user.id);
        if (!mounted) return;
        _showSuccess('Convocação aceita!');
        _refreshEventos();
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
      if (!mounted) return;
      _showError('Convocação recusada');
      _refreshEventos();
    } catch (e) {
      if (!mounted) return;
      _showError('Erro: $e');
    }
  }

  Future<void> _mostrarConvocadosDoEvento(Map<String, dynamic> evento) async {
    final eventIdRaw = evento['id'];
    if (eventIdRaw == null) return;

    try {
      final response = await _supabase.rpc(
        'get_agenda_event_convocados',
        params: {'p_event_id': eventIdRaw},
      );

      final participantes = (response as List<dynamic>)
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();

      String formatBirthDate(dynamic rawDate) {
        if (rawDate == null || rawDate.toString().trim().isEmpty) return '-';
        try {
          final date = DateTime.parse(rawDate.toString());
          return '${date.day.toString().padLeft(2, '0')}/'
              '${date.month.toString().padLeft(2, '0')}/'
              '${date.year}';
        } catch (_) {
          return rawDate.toString();
        }
      }

      if (!mounted) return;

      showDialog(
        context: context,
        builder: (context) => Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: Container(
            padding: const EdgeInsets.all(24),
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.75,
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
                            'Convocados: ${(evento['event_name'] ?? '').toString()}',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: olympusBlue,
                            ),
                          ),
                          Text(
                            '${participantes.where((p) => (p['status'] ?? '').toString() == 'accepted').length} aceitaram de ${participantes.length}',
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
                        children: participantes.map((participante) {
                          final status =
                              (participante['status'] ?? 'pending').toString();
                          final isAceitou = status == 'accepted';
                          final isRecusou = status == 'rejected';
                          final isAtleta =
                              (participante['user_type'] ?? '').toString() ==
                                  'athlete';
                          final labelStatus = isAceitou
                              ? 'Aceitou'
                              : (isRecusou ? 'Recusou' : 'Pendente');
                          final colorStatus = isAceitou
                              ? Colors.green[700]
                              : (isRecusou
                                  ? Colors.red[700]
                                  : Colors.grey[600]);
                          final birthDate =
                              formatBirthDate(participante['birth_date']);
                          final rg = (participante['rg'] ?? '-').toString();

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
                                            (participante['full_name'] ??
                                                    'Sem nome')
                                                .toString(),
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
                                const SizedBox(height: 8),
                                Text(
                                  'Data de nascimento: $birthDate',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[800],
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'RG: $rg',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[800],
                                  ),
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
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao carregar convocações: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _exportarDadosDoJogo(Map<String, dynamic> evento) async {
    final eventIdRaw = evento['id'];
    if (eventIdRaw == null) return;

    try {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('📋 Preparando dados do jogo para copiar...'),
            backgroundColor: Colors.blue,
            duration: Duration(seconds: 2),
          ),
        );
      }

      final response = await _supabase.rpc(
        'get_agenda_event_convocados',
        params: {'p_event_id': eventIdRaw},
      );

      final convocados = (response as List<dynamic>)
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();

      String formatBirthDate(dynamic rawDate) {
        if (rawDate == null || rawDate.toString().trim().isEmpty) return '-';
        try {
          final date = DateTime.parse(rawDate.toString());
          return '${date.day.toString().padLeft(2, '0')}/'
              '${date.month.toString().padLeft(2, '0')}/'
              '${date.year}';
        } catch (_) {
          return rawDate.toString();
        }
      }

      final championshipName =
          (evento['championship_name'] ?? '-').toString().trim().isEmpty
              ? '-'
              : (evento['championship_name'] ?? '-').toString().trim();
      final dataJogo = (evento['event_date'] ?? '-').toString().trim();
      final horarioJogo = (evento['event_time'] ?? '-').toString().trim();
      final nomeJogo = (evento['event_name'] ?? '-').toString().trim();
      final street = (evento['street'] ?? '').toString().trim();
      final number = (evento['street_number'] ?? '').toString().trim();
      final neighborhood = (evento['neighborhood'] ?? '').toString().trim();
      final city = (evento['city'] ?? '').toString().trim();
      final state = (evento['state'] ?? '').toString().trim();

      final endereco = street.isEmpty
          ? '-'
          : '$street'
              '${number.isNotEmpty ? ', $number' : ''}'
              '${neighborhood.isNotEmpty ? ' - $neighborhood' : ''}'
              '${city.isNotEmpty ? ' - $city' : ''}'
              '${state.isNotEmpty ? '/$state' : ''}';

      final aceitosLines = <String>[
        'CAMPEONATO/LIGA: $championshipName',
        'DATA: $dataJogo - HORÁRIO: $horarioJogo',
        nomeJogo,
        'ENDEREÇO: $endereco',
        '',
        'ACEITARAM',
        '',
      ];

      final pendentesLines = <String>[
        '',
        'PENDENTES',
        '',
      ];

      final recusadosLines = <String>[
        '',
        'RECUSARAM',
        '',
      ];

      convocados.sort((a, b) {
        final nomeA = (a['full_name'] ?? '').toString().toLowerCase();
        final nomeB = (b['full_name'] ?? '').toString().toLowerCase();
        return nomeA.compareTo(nomeB);
      });

      for (final convocado in convocados) {
        final nome = (convocado['full_name'] ?? '-').toString();
        final dataNascimento = formatBirthDate(convocado['birth_date']);
        final rg = (convocado['rg'] ?? '-').toString();
        final userType = (convocado['user_type'] ?? '').toString();
        final cargo = userType == 'coach'
            ? 'Técnico'
            : userType == 'athlete'
                ? 'Atleta'
                : userType;
        final status = (convocado['status'] ?? 'pending').toString();

        if (status == 'accepted') {
          aceitosLines.add(
            'Nome: $nome\n'
            'Tipo: ${cargo.isEmpty ? '-' : cargo}\n'
            'Data de nascimento: $dataNascimento\n'
            'RG: $rg\n'
            'Status: Aceitou\n',
          );
        } else if (status == 'rejected') {
          final justificativa =
              (convocado['justification'] ?? '-').toString().trim();

          recusadosLines.add(
            'Nome: $nome\n'
            'Tipo: ${cargo.isEmpty ? '-' : cargo}\n'
            'Data de nascimento: $dataNascimento\n'
            'RG: $rg\n'
            'Status: Recusou\n'
            'Justificativa: ${justificativa.isEmpty ? '-' : justificativa}\n',
          );
        } else {
          pendentesLines.add(
            'Nome: $nome\n'
            'Tipo: ${cargo.isEmpty ? '-' : cargo}\n'
            'Data de nascimento: $dataNascimento\n'
            'RG: $rg\n'
            'Status: Pendente\n',
          );
        }
      }

      final lines = <String>[
        ...aceitosLines,
        ...pendentesLines,
        ...recusadosLines,
      ];

      final formattedContent = lines.join('\n');

      await Clipboard.setData(ClipboardData(text: formattedContent));

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Dados do jogo copiados! Agora é só colar'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 3),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Erro ao exportar: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<Map<String, dynamic>?> _showRideDialog() async {
    bool needsRideIda = false;
    int? seatsIda;
    bool idaConfirmed = false;
    bool needsRideVolta = false;
    int? seatsVolta;
    bool voltaConfirmed = false;

    Widget buildSeatChip({
      required String label,
      required bool selected,
      required VoidCallback onTap,
    }) {
      return ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onTap(),
        showCheckmark: false,
        selectedColor: olympusGold,
        backgroundColor: Colors.white.withOpacity(0.16),
        disabledColor: Colors.white.withOpacity(0.16),
        color: WidgetStateProperty.resolveWith<Color?>((states) {
          if (states.contains(WidgetState.selected)) {
            return olympusGold;
          }
          return Colors.white.withOpacity(0.16);
        }),
        labelStyle: const TextStyle(
          color: olympusBlue,
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(
            color: selected ? olympusGold : Colors.white.withOpacity(0.24),
            width: selected ? 1.6 : 1,
          ),
        ),
      );
    }

    Widget buildSection({
      required String title,
      required bool needsRide,
      required int? seats,
      required bool confirmed,
      required ValueChanged<bool> onNeedsRideChanged,
      required ValueChanged<int> onSeatsChanged,
    }) {
      return Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: Colors.white.withOpacity(0.08),
          border: Border.all(
            color: Colors.white.withOpacity(0.10),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Precisa de carona?',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ),
                Transform.scale(
                  scale: 1.08,
                  child: Checkbox(
                    value: needsRide,
                    onChanged: (value) => onNeedsRideChanged(value ?? false),
                    activeColor: olympusGold,
                    checkColor: olympusBlue,
                    side: BorderSide(
                      color: Colors.white.withOpacity(0.55),
                      width: 1.4,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Ou informe quantas vagas você tem no carro:',
              style: TextStyle(
                color: Colors.white.withOpacity(0.72),
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                buildSeatChip(
                  label: '4 vagas',
                  selected: seats == 4,
                  onTap: () => onSeatsChanged(4),
                ),
                buildSeatChip(
                  label: '3 vagas',
                  selected: seats == 3,
                  onTap: () => onSeatsChanged(3),
                ),
                buildSeatChip(
                  label: '2 vagas',
                  selected: seats == 2,
                  onTap: () => onSeatsChanged(2),
                ),
                buildSeatChip(
                  label: '1 vaga',
                  selected: seats == 1,
                  onTap: () => onSeatsChanged(1),
                ),
                buildSeatChip(
                  label: 'Sem vagas',
                  selected: seats == 0,
                  onTap: () => onSeatsChanged(0),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(
                  confirmed ? Icons.check_circle : Icons.info_outline,
                  size: 15,
                  color: confirmed ? olympusGold : Colors.white70,
                ),
                const SizedBox(width: 6),
                Text(
                  confirmed
                      ? 'Opção confirmada'
                      : 'Escolha uma opção para continuar',
                  style: TextStyle(
                    color: confirmed ? olympusGold : Colors.white70,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    return showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withOpacity(0.55),
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            final canConfirm = idaConfirmed && voltaConfirmed;
            return Dialog(
              backgroundColor: Colors.transparent,
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 18,
                vertical: 24,
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: 520,
                  maxHeight: MediaQuery.of(dialogContext).size.height * 0.86,
                ),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(
                      color: olympusGold.withOpacity(0.60),
                      width: 1.3,
                    ),
                    gradient: const LinearGradient(
                      colors: [
                        olympusBlue,
                        olympusLightBlue,
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.28),
                        blurRadius: 24,
                        offset: const Offset(0, 10),
                      ),
                      BoxShadow(
                        color: olympusGold.withOpacity(0.14),
                        blurRadius: 24,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: Stack(
                      children: [
                        Positioned(
                          top: -26,
                          right: -12,
                          child: Container(
                            width: 110,
                            height: 110,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white.withOpacity(0.05),
                            ),
                          ),
                        ),
                        Positioned(
                          bottom: -28,
                          left: -16,
                          child: Container(
                            width: 96,
                            height: 96,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: olympusGold.withOpacity(0.06),
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    width: 42,
                                    height: 42,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      gradient: const LinearGradient(
                                        colors: [
                                          Color(0xFFF0D771),
                                          Color(0xFFB48A23),
                                        ],
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                      ),
                                    ),
                                    child: const Icon(
                                      Icons.directions_car_filled_rounded,
                                      color: olympusBlue,
                                      size: 22,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  const Expanded(
                                    child: Text(
                                      'Logística de Carona',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 20,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    onPressed: () =>
                                        Navigator.pop(dialogContext, null),
                                    icon: const Icon(Icons.close_rounded),
                                    color: Colors.white70,
                                    splashRadius: 20,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Como este evento é um campeonato, informe sua disponibilidade de ida e volta.',
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.74),
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w500,
                                  height: 1.3,
                                ),
                              ),
                              const SizedBox(height: 16),
                              Flexible(
                                child: SingleChildScrollView(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      buildSection(
                                        title: 'Carona de ida',
                                        needsRide: needsRideIda,
                                        seats: seatsIda,
                                        confirmed: idaConfirmed,
                                        onNeedsRideChanged: (value) {
                                          setDialogState(() {
                                            needsRideIda = value;
                                            seatsIda = null;
                                            idaConfirmed = true;
                                          });
                                        },
                                        onSeatsChanged: (value) {
                                          setDialogState(() {
                                            seatsIda = value;
                                            needsRideIda = false;
                                            idaConfirmed = true;
                                          });
                                        },
                                      ),
                                      buildSection(
                                        title: 'Carona de volta',
                                        needsRide: needsRideVolta,
                                        seats: seatsVolta,
                                        confirmed: voltaConfirmed,
                                        onNeedsRideChanged: (value) {
                                          setDialogState(() {
                                            needsRideVolta = value;
                                            seatsVolta = null;
                                            voltaConfirmed = true;
                                          });
                                        },
                                        onSeatsChanged: (value) {
                                          setDialogState(() {
                                            seatsVolta = value;
                                            needsRideVolta = false;
                                            voltaConfirmed = true;
                                          });
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton(
                                      onPressed: () =>
                                          Navigator.pop(dialogContext, null),
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: Colors.white,
                                        side: BorderSide(
                                          color: Colors.white.withOpacity(0.22),
                                        ),
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 13,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(12),
                                        ),
                                      ),
                                      child: const Text('Cancelar'),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: ElevatedButton(
                                      onPressed: canConfirm
                                          ? () {
                                              Navigator.pop(dialogContext, {
                                                'ida': {
                                                  'needs_ride': needsRideIda,
                                                  'has_car':
                                                      (seatsIda ?? 0) > 0,
                                                  'available_seats':
                                                      seatsIda ?? 0,
                                                },
                                                'volta': {
                                                  'needs_ride': needsRideVolta,
                                                  'has_car':
                                                      (seatsVolta ?? 0) > 0,
                                                  'available_seats':
                                                      seatsVolta ?? 0,
                                                },
                                              });
                                            }
                                          : null,
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: olympusGold,
                                        foregroundColor: olympusBlue,
                                        disabledBackgroundColor:
                                            Colors.white.withOpacity(0.20),
                                        disabledForegroundColor:
                                            Colors.white.withOpacity(0.60),
                                        elevation: 0,
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 13,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(12),
                                        ),
                                      ),
                                      child: const Text(
                                        'Confirmar',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
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
          },
        );
      },
    );
  }

  Future<Map<String, double>> _geocodeCep(String cep) async {
    final cepLimpo = cep.replaceAll(RegExp(r'[^0-9]'), '');
    if (cepLimpo.isEmpty) throw Exception('CEP inválido');
    final uri = Uri.parse('https://api.positionstack.com/v1/forward  '
        '?access_key=$_geocodeAccessKey'
        '&query=$cepLimpo'
        '&country=BR'
        '&limit=1');
    final resp = await http.get(uri);
    if (resp.statusCode != 200) {
      throw Exception('Erro geocode (${resp.statusCode})');
    }
    final body = json.decode(resp.body) as Map<String, dynamic>;
    final data = (body['data'] as List?) ?? const [];
    if (data.isEmpty) throw Exception('CEP não encontrado no geocode');
    final first = data.first as Map<String, dynamic>;
    final lat = (first['latitude'] as num?)?.toDouble();
    final lng = (first['longitude'] as num?)?.toDouble();
    if (lat == null || lng == null) throw Exception('Geocode inválido');
    return {'lat': lat, 'lng': lng};
  }

  Future<void> _fazerCheckIn(Map<String, dynamic> evento) async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) {
        _showError('Usuário não autenticado');
        return;
      }
      final eventLat = (evento['latitude'] as num?)?.toDouble();
      final eventLng = (evento['longitude'] as num?)?.toDouble();
      print('📍 Coordenadas do evento: lat=$eventLat, lng=$eventLng');
      if (eventLat == null || eventLng == null) {
        _showError('⚠️ Evento sem coordenadas! '
            'O administrador precisa geocodificar o endereço ao criar o evento.');
        return;
      }
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) {
        _showError('Ative o GPS para fazer check-in.');
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever ||
          permission == LocationPermission.denied) {
        _showError('Permissão de localização negada.');
        return;
      }
      if (!mounted) return;
      _showSuccess('📡 Obtendo sua localização...');
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        forceAndroidLocationManager: true,
        timeLimit: const Duration(seconds: 15),
      );
      print('📍 Sua posição: lat=${pos.latitude}, lng=${pos.longitude}');
      print('📍 Precisão do GPS: ${pos.accuracy}m');
      final distancia = _calcularDistanciaMetros(
        pos.latitude,
        pos.longitude,
        eventLat,
        eventLng,
      );
      print('📍 Distância calculada: ${distancia.toStringAsFixed(0)}m');
      const raioMaximo = 200.0;
      if (distancia > raioMaximo) {
        _showError('❌ Você está muito longe do local! '
            'Distância: ${distancia.toStringAsFixed(0)}m '
            'Máximo permitido: ${raioMaximo.toStringAsFixed(0)}m '
            'Aproxime-se mais do local do evento.');
        return;
      }
      print('✅ Dentro do raio de ${raioMaximo}m. Chamando stored procedure...');
      final res = await _supabase.rpc('do_checkin', params: {
        'p_event_id': evento['id'],
        'p_event_lat': eventLat,
        'p_event_lng': eventLng,
        'p_check_lat': pos.latitude,
        'p_check_lng': pos.longitude,
      });
      final ok = res?['ok'] == true;
      final st = (res?['status'] ?? '').toString();
      print('📍 Resultado do check-in: ok=$ok, status=$st');
      if (!mounted) return;
      if (ok) {
        await _sincronizarCheckInStatus(evento['id'].toString(), user.id);
        if (mounted) {
          setState(() {
            evento['check_in_status'] = 'realizado';
          });
        }
        _showSuccess('✅ Check-in confirmado com sucesso!');
        await _refreshEventos();
      } else {
        _showError('❌ Check-in não permitido: $st');
      }
    } catch (e) {
      print('❌ Erro no check-in: $e');
      if (!mounted) return;
      _showError('Erro no check-in: $e');
    }
  }

  List<String> _getMesesDisponiveis() {
    final meses = <String>{};
    for (final e in _eventos) {
      final data = (e['event_date'] ?? '').toString();
      if (data.length >= 7) meses.add(data.substring(3));
    }
    final list = meses.toList();
    list.sort((a, b) {
      final ap = a.split('/');
      final bp = b.split('/');
      if (ap.length != 2 || bp.length != 2) return a.compareTo(b);
      final ay = int.tryParse(ap[1]) ?? 0;
      final by = int.tryParse(bp[1]) ?? 0;
      if (ay != by) return ay.compareTo(by);
      final am = int.tryParse(ap[0]) ?? 0;
      final bm = int.tryParse(bp[0]) ?? 0;
      return am.compareTo(bm);
    });
    if (list.isEmpty) return <String>[];
    return list;
  }

  String _formatarNomeMes(String mesAno) {
    final p = mesAno.split('/');
    if (p.length != 2) return mesAno;
    final m = int.tryParse(p[0]) ?? 1;
    final y = int.tryParse(p[1]) ?? 2000;
    const nomes = [
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
    final nome = (m >= 1 && m <= 12) ? nomes[m - 1] : 'Mês';
    return '$nome/$y';
  }

  Widget _buildPremiumAgendaBackground() {
    return Stack(
      children: [
        Positioned.fill(
          child: Image.asset(
            'assets/images/monte_olimpo_v2.png',
            fit: BoxFit.cover,
            alignment: Alignment.center,
            errorBuilder: (context, error, stackTrace) {
              return Container(color: const Color(0xFF102845));
            },
          ),
        ),
        Positioned.fill(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 2, sigmaY: 2),
            child: Container(color: Colors.transparent),
          ),
        ),
        Positioned.fill(
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  const Color(0xFF102845).withOpacity(0.55),
                  const Color(0xFF1E3A5F).withOpacity(0.30),
                  Colors.black.withOpacity(0.60),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAccessDeniedScreen() {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Agenda',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: olympusBlue,
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 2,
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: _buildPremiumAgendaBackground(),
          ),
          Center(
            child: Container(
              margin: const EdgeInsets.all(20),
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.10),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: Colors.white.withOpacity(0.14),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.lock_outline,
                    size: 80,
                    color: olympusGold.withOpacity(0.8),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Acesso Restrito',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Você não tem permissão para acessar a agenda.\nContate o administrador.',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.8),
                      fontSize: 14,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pushNamedAndRemoveUntil(
                        context,
                        '/dashboard',
                        (route) => false,
                      );
                    },
                    icon: const Icon(Icons.dashboard),
                    label: const Text('Ir para Dashboard'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: olympusGold,
                      foregroundColor: olympusBlue,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPermissionCheckingScreen() {
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: _buildPremiumAgendaBackground(),
          ),
          const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(olympusGold),
                ),
                SizedBox(height: 16),
                Text(
                  'Verificando permissões...',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_checkingPermission) {
      return _buildPermissionCheckingScreen();
    }

    if (!_hasPermission) {
      return _buildAccessDeniedScreen();
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Minhas Convocações',
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
      body: Stack(
        children: [
          Positioned.fill(
            child: _buildPremiumAgendaBackground(),
          ),
          Column(
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
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
                    bottomLeft: Radius.circular(16),
                    bottomRight: Radius.circular(16),
                  ),
                ),
                child: Column(
                  children: [
                    if (_showMonthFilter) ...[
                      _buildVisaoGeralButton(),
                      const SizedBox(height: 10),
                      _buildModernDropdown(
                        icon: Icons.calendar_month,
                        value: _filtroMes.isEmpty ? null : _filtroMes,
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
                            _selecionarMes(valor.toString());
                          }
                        },
                      ),
                    ],
                  ],
                ),
              ),
              _buildResumoPorTipoSection(),
              Expanded(
                child: _loading
                    ? const Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            CircularProgressIndicator(
                              valueColor:
                                  AlwaysStoppedAnimation<Color>(olympusGold),
                            ),
                            SizedBox(height: 16),
                            Text(
                              'Carregando convocações...',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      )
                    : _error != null
                        ? Center(
                            child: Container(
                              margin: const EdgeInsets.all(20),
                              padding: const EdgeInsets.all(18),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.10),
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(
                                  color: Colors.white.withOpacity(0.14),
                                ),
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.error_outline,
                                      size: 48, color: Colors.red[300]),
                                  const SizedBox(height: 16),
                                  Text(
                                    _error!,
                                    style: const TextStyle(color: Colors.white),
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 16),
                                  ElevatedButton(
                                    onPressed: _buscarEventos,
                                    child: const Text('Tentar Novamente'),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : _eventosFiltrados.isEmpty
                            ? Center(
                                child: Container(
                                  margin: const EdgeInsets.all(20),
                                  padding: const EdgeInsets.all(18),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.10),
                                    borderRadius: BorderRadius.circular(18),
                                    border: Border.all(
                                      color: Colors.white.withOpacity(0.14),
                                    ),
                                  ),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.event_busy,
                                          size: 64, color: Colors.white70),
                                      const SizedBox(height: 16),
                                      const Text(
                                        'Nenhuma convocação encontrada',
                                        style: TextStyle(
                                          fontSize: 18,
                                          color: Colors.white,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                    ],
                                  ),
                                ),
                              )
                            : RefreshIndicator(
                                onRefresh: _refreshEventos,
                                child: ListView.builder(
                                  padding: const EdgeInsets.all(12),
                                  itemCount: _eventosFiltrados.length,
                                  itemBuilder: (context, index) {
                                    final evento = _eventosFiltrados[index];
                                    final eventId = evento['id'].toString();
                                    final statusData =
                                        _convocationStatus[eventId];
                                    final status = (statusData?['status'] ??
                                            evento['convocation_status'] ??
                                            'pending')
                                        .toString()
                                        .toLowerCase()
                                        .trim();
                                    final eventType =
                                        (evento['event_type'] ?? '').toString();
                                    final nomeEvento =
                                        (evento['event_name'] ?? '')
                                            .toString()
                                            .trim();
                                    final tipoNormalizado =
                                        eventType.toLowerCase().trim();
                                    final nomeNormalizado =
                                        nomeEvento.toLowerCase().trim();
                                    final mostrarNomeEvento = nomeEvento
                                            .isNotEmpty &&
                                        nomeNormalizado != tipoNormalizado &&
                                        nomeNormalizado !=
                                            'evento ' + tipoNormalizado;
                                    final corTipo =
                                        _getCorTipoEvento(eventType);
                                    final genero =
                                        (evento['gender'] ?? '').toString();
                                    final podeEditar = _podeEditar(evento);
                                    final prazoInfo = _getPrazoInfo(evento);
                                    final championshipName =
                                        (evento['championship_name'] ?? '')
                                            .toString()
                                            .trim();
                                    String? enderecoCompleto;
                                    final street = (evento['street'] ?? '')
                                        .toString()
                                        .trim();
                                    if (street.isNotEmpty) {
                                      final numero =
                                          (evento['street_number'] ?? '')
                                              .toString()
                                              .trim();
                                      final bairro =
                                          (evento['neighborhood'] ?? '')
                                              .toString()
                                              .trim();
                                      final cidade = (evento['city'] ?? '')
                                          .toString()
                                          .trim();
                                      final estado = (evento['state'] ?? '')
                                          .toString()
                                          .trim();
                                      enderecoCompleto = '$street'
                                          '${numero.isNotEmpty ? ', $numero' : ''}'
                                          '${bairro.isNotEmpty ? ' - $bairro' : ''}'
                                          '${cidade.isNotEmpty ? ' - $cidade' : ''}'
                                          '${estado.isNotEmpty ? '/$estado' : ''}';
                                    }
                                    final checkinStatus =
                                        _normalizarCheckInStatus(
                                      evento['check_in_status'],
                                    );
                                    final jaFezCheckin =
                                        _isCheckInRealizado(checkinStatus);
                                    final janelaCheckIn =
                                        _verificarJanelaCheckIn(evento);
                                    final podeFazerCheckin =
                                        status == 'accepted' &&
                                            !jaFezCheckin &&
                                            janelaCheckIn['disponivel'] == true;
                                    return Card(
                                      margin: const EdgeInsets.only(bottom: 10),
                                      elevation: 3,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                      color:
                                          _getCorFundoCard(genero, eventType),
                                      child: Padding(
                                        padding: const EdgeInsets.all(14),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Container(
                                                  padding: const EdgeInsets
                                                      .symmetric(
                                                    horizontal: 12,
                                                    vertical: 7,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    color: corTipo
                                                        .withOpacity(0.14),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            16),
                                                    border: Border.all(
                                                      color: corTipo,
                                                      width: 1.4,
                                                    ),
                                                  ),
                                                  child: Text(
                                                    (evento['event_type'] ??
                                                            'Geral')
                                                        .toString()
                                                        .toUpperCase(),
                                                    style: TextStyle(
                                                      color: corTipo,
                                                      fontWeight:
                                                          FontWeight.w900,
                                                      fontSize: 14,
                                                      letterSpacing: 0.7,
                                                    ),
                                                  ),
                                                ),
                                                const Spacer(),
                                                Container(
                                                  padding: const EdgeInsets
                                                      .symmetric(
                                                    horizontal: 10,
                                                    vertical: 6,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    color:
                                                        _getStatusColor(status)
                                                            .withOpacity(0.12),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            14),
                                                    border: Border.all(
                                                      color: _getStatusColor(
                                                          status),
                                                      width: 1.2,
                                                    ),
                                                  ),
                                                  child: Text(
                                                    _getStatusLabel(status),
                                                    style: TextStyle(
                                                      color: _getStatusColor(
                                                          status),
                                                      fontWeight:
                                                          FontWeight.w800,
                                                      fontSize: 11.5,
                                                    ),
                                                  ),
                                                ),
                                                if (_canViewConvocados ||
                                                    _canExportDadosJogo) ...[
                                                  const SizedBox(width: 4),
                                                  PopupMenuButton<String>(
                                                    icon: Icon(
                                                      Icons.more_vert,
                                                      color: Colors.grey[700],
                                                      size: 20,
                                                    ),
                                                    onSelected: (value) {
                                                      if (value ==
                                                          'ver_convocados') {
                                                        _mostrarConvocadosDoEvento(
                                                            evento);
                                                      } else if (value ==
                                                          'exportar_dados_jogo') {
                                                        _exportarDadosDoJogo(
                                                            evento);
                                                      }
                                                    },
                                                    itemBuilder: (context) {
                                                      final items =
                                                          <PopupMenuItem<
                                                              String>>[];
                                                      if (_canViewConvocados) {
                                                        items.add(
                                                          const PopupMenuItem(
                                                            value:
                                                                'ver_convocados',
                                                            child: Row(
                                                              children: [
                                                                Icon(
                                                                  Icons
                                                                      .people_outline,
                                                                  size: 18,
                                                                  color: Colors
                                                                      .green,
                                                                ),
                                                                SizedBox(
                                                                    width: 8),
                                                                Text(
                                                                    'Ver convocados'),
                                                              ],
                                                            ),
                                                          ),
                                                        );
                                                      }
                                                      if (_canExportDadosJogo) {
                                                        items.add(
                                                          const PopupMenuItem(
                                                            value:
                                                                'exportar_dados_jogo',
                                                            child: Row(
                                                              children: [
                                                                Icon(
                                                                  Icons
                                                                      .file_download,
                                                                  size: 18,
                                                                  color: Colors
                                                                      .green,
                                                                ),
                                                                SizedBox(
                                                                    width: 8),
                                                                Text(
                                                                    'Exportar dados do jogo'),
                                                              ],
                                                            ),
                                                          ),
                                                        );
                                                      }
                                                      return items;
                                                    },
                                                  ),
                                                ],
                                              ],
                                            ),
                                            const SizedBox(height: 8),
                                            if (mostrarNomeEvento) ...[
                                              Text(
                                                nomeEvento,
                                                style: const TextStyle(
                                                  fontSize: 17,
                                                  fontWeight: FontWeight.w800,
                                                  height: 1.2,
                                                ),
                                              ),
                                            ],
                                            if (eventType
                                                        .toLowerCase()
                                                        .trim() ==
                                                    'campeonato' &&
                                                championshipName
                                                    .isNotEmpty) ...[
                                              const SizedBox(height: 4),
                                              Row(
                                                children: [
                                                  Icon(Icons.emoji_events,
                                                      size: 14,
                                                      color: Colors.amber[700]),
                                                  const SizedBox(width: 6),
                                                  Expanded(
                                                    child: Text(
                                                      championshipName,
                                                      style: TextStyle(
                                                        fontSize: 13,
                                                        color:
                                                            Colors.amber[900],
                                                        fontWeight:
                                                            FontWeight.w700,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ],
                                            const SizedBox(height: 6),
                                            Row(
                                              children: [
                                                Icon(Icons.calendar_today,
                                                    size: 16,
                                                    color: Colors.grey[600]),
                                                const SizedBox(width: 6),
                                                Expanded(
                                                  child: Builder(
                                                    builder: (context) {
                                                      final dataParts =
                                                          _formatarData(
                                                        (evento['event_date'] ??
                                                                '')
                                                            .toString(),
                                                      ).split('|');
                                                      final dataFormatada =
                                                          dataParts.isNotEmpty
                                                              ? dataParts[0]
                                                              : '';
                                                      final diaSemana =
                                                          dataParts.length > 1
                                                              ? dataParts[1]
                                                              : '';

                                                      return RichText(
                                                        text: TextSpan(
                                                          style: TextStyle(
                                                            color: Colors
                                                                .grey[700],
                                                            fontSize: 13,
                                                            fontWeight:
                                                                FontWeight.w600,
                                                          ),
                                                          children: [
                                                            TextSpan(
                                                              text:
                                                                  dataFormatada,
                                                            ),
                                                            if (diaSemana
                                                                .isNotEmpty)
                                                              TextSpan(
                                                                text:
                                                                    ' ($diaSemana)',
                                                                style:
                                                                    const TextStyle(
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w900,
                                                                ),
                                                              ),
                                                          ],
                                                        ),
                                                      );
                                                    },
                                                  ),
                                                ),
                                              ],
                                            ),
                                            Row(
                                              children: [
                                                Icon(Icons.access_time,
                                                    size: 16,
                                                    color: Colors.grey[600]),
                                                const SizedBox(width: 6),
                                                Text(
                                                  (evento['event_time'] ?? '')
                                                      .toString(),
                                                  style: TextStyle(
                                                    color: Colors.grey[700],
                                                    fontSize: 13,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              ],
                                            ),
                                            if (enderecoCompleto != null &&
                                                enderecoCompleto
                                                    .isNotEmpty) ...[
                                              const SizedBox(height: 2),
                                              Row(
                                                children: [
                                                  Icon(Icons.location_on,
                                                      size: 15,
                                                      color: Colors.grey[600]),
                                                  const SizedBox(width: 6),
                                                  Expanded(
                                                    child: Text(
                                                      enderecoCompleto,
                                                      style: TextStyle(
                                                        color: Colors.grey[700],
                                                        fontSize: 12,
                                                        fontWeight:
                                                            FontWeight.w500,
                                                      ),
                                                      maxLines: 1,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ],
                                            const SizedBox(height: 8),
                                            if (prazoInfo.isNotEmpty) ...[
                                              Text(
                                                prazoInfo,
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  color: Colors.red[700],
                                                  fontStyle: FontStyle.italic,
                                                ),
                                              ),
                                              const SizedBox(height: 6),
                                            ],
                                            if (status == 'pending')
                                              Row(
                                                children: [
                                                  Expanded(
                                                    child: SizedBox(
                                                      height: 32,
                                                      child:
                                                          ElevatedButton.icon(
                                                        onPressed: podeEditar
                                                            ? () =>
                                                                _responderConvocacao(
                                                                    evento,
                                                                    false)
                                                            : null,
                                                        icon: const Icon(
                                                          Icons.close,
                                                          size: 16,
                                                        ),
                                                        label: const Text(
                                                          'Recusar',
                                                          style: TextStyle(
                                                            fontSize: 11,
                                                          ),
                                                        ),
                                                        style: ElevatedButton
                                                            .styleFrom(
                                                          backgroundColor:
                                                              podeEditar
                                                                  ? Colors.red
                                                                  : Colors.grey,
                                                          foregroundColor:
                                                              Colors.white,
                                                          padding:
                                                              EdgeInsets.zero,
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                  const SizedBox(width: 8),
                                                  Expanded(
                                                    child: SizedBox(
                                                      height: 32,
                                                      child:
                                                          ElevatedButton.icon(
                                                        onPressed: podeEditar
                                                            ? () =>
                                                                _responderConvocacao(
                                                                    evento,
                                                                    true)
                                                            : null,
                                                        icon: const Icon(
                                                          Icons.check,
                                                          size: 16,
                                                        ),
                                                        label: const Text(
                                                          'Aceitar',
                                                          style: TextStyle(
                                                            fontSize: 11,
                                                          ),
                                                        ),
                                                        style: ElevatedButton
                                                            .styleFrom(
                                                          backgroundColor:
                                                              podeEditar
                                                                  ? Colors.green
                                                                  : Colors.grey,
                                                          foregroundColor:
                                                              Colors.white,
                                                          padding:
                                                              EdgeInsets.zero,
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            if (status != 'pending') ...[
                                              const SizedBox(height: 6),
                                              SizedBox(
                                                height: 32,
                                                width: double.infinity,
                                                child: ElevatedButton.icon(
                                                  onPressed: podeEditar
                                                      ? () => _editarResposta(
                                                          evento)
                                                      : null,
                                                  icon: const Icon(
                                                    Icons.edit,
                                                    size: 16,
                                                  ),
                                                  label: const Text(
                                                    'Editar resposta',
                                                    style:
                                                        TextStyle(fontSize: 11),
                                                  ),
                                                  style:
                                                      ElevatedButton.styleFrom(
                                                    backgroundColor: podeEditar
                                                        ? Colors.deepPurple
                                                        : Colors.grey,
                                                    foregroundColor:
                                                        Colors.white,
                                                    padding: EdgeInsets.zero,
                                                  ),
                                                ),
                                              ),
                                            ],
                                            if (jaFezCheckin ||
                                                podeFazerCheckin) ...[
                                              const SizedBox(height: 8),
                                              if (jaFezCheckin)
                                                Row(
                                                  children: [
                                                    const Icon(
                                                      Icons.verified,
                                                      color: Colors.green,
                                                      size: 16,
                                                    ),
                                                    const SizedBox(width: 6),
                                                    const Text(
                                                      'Check-in realizado',
                                                      style: TextStyle(
                                                        fontWeight:
                                                            FontWeight.w600,
                                                        fontSize: 11,
                                                        color: Colors.green,
                                                      ),
                                                    ),
                                                  ],
                                                )
                                              else
                                                SizedBox(
                                                  height: 32,
                                                  width: double.infinity,
                                                  child: ElevatedButton.icon(
                                                    onPressed: () =>
                                                        _fazerCheckIn(evento),
                                                    icon: const Icon(
                                                      Icons.my_location,
                                                      size: 16,
                                                    ),
                                                    label: const Text(
                                                      'Fazer Check-in',
                                                      style: TextStyle(
                                                        fontSize: 11,
                                                      ),
                                                    ),
                                                    style: ElevatedButton
                                                        .styleFrom(
                                                      backgroundColor:
                                                          Colors.green,
                                                      foregroundColor:
                                                          Colors.white,
                                                      padding: EdgeInsets.zero,
                                                    ),
                                                  ),
                                                ),
                                            ],
                                            if (podeFazerCheckin) ...[
                                              const SizedBox(height: 6),
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                  horizontal: 8,
                                                  vertical: 4,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: Colors.red[50],
                                                  borderRadius:
                                                      BorderRadius.circular(6),
                                                  border: Border.all(
                                                    color: Colors.red[200]!,
                                                  ),
                                                ),
                                                child: Row(
                                                  children: [
                                                    Icon(
                                                      Icons.info_outline,
                                                      size: 14,
                                                      color: Colors.red[700],
                                                    ),
                                                    const SizedBox(width: 6),
                                                    Expanded(
                                                      child: Text(
                                                        '📍 Raio 200m | 10min antes até 30min após',
                                                        style: TextStyle(
                                                          fontSize: 10,
                                                          color:
                                                              Colors.red[900],
                                                          fontWeight:
                                                              FontWeight.w500,
                                                        ),
                                                      ),
                                                    ),
                                                  ],
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
        ],
      ),
    );
  }

  Widget _buildVisaoGeralButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: _alternarVisaoGeral,
        icon: Icon(
          _isVisaoGeral
              ? Icons.calendar_month_rounded
              : Icons.dashboard_customize_rounded,
          size: 18,
        ),
        label: Text(
          _isVisaoGeral ? 'Voltar para o mês atual' : 'Ativar visão geral',
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: _isVisaoGeral ? olympusGold : Colors.white,
          foregroundColor: olympusBlue,
          elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }

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
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            spreadRadius: 1,
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 2),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 14,
                  color: olympusGold,
                ),
                const SizedBox(width: 4),
                Text(
                  hint,
                  style: TextStyle(
                    fontSize: 10,
                    color: olympusGold.withOpacity(0.8),
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<dynamic>(
                value: value,
                hint: Text(
                  hint,
                  style: TextStyle(color: Colors.grey[600], fontSize: 13),
                ),
                isExpanded: true,
                items: items,
                onChanged: onChanged,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF2C3E5A),
                ),
                icon: Icon(
                  Icons.keyboard_arrow_down_rounded,
                  color: olympusGold,
                  size: 18,
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
        ],
      ),
    );
  }

  Widget _buildModernChipFilter({
    required String label,
    required IconData icon,
    required List<Map<String, dynamic>> options,
    required String selectedValue,
    required ValueChanged<String> onSelected,
    bool showBadges = false,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            spreadRadius: 1,
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 14,
                  color: olympusGold,
                ),
                const SizedBox(width: 4),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 10,
                    color: olympusGold.withOpacity(0.8),
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: options.map((option) {
                final value = option['value'] as String;
                final labelText = option['label'] as String;
                final count = option['count'] as int?;
                final selected = selectedValue == value;
                Color chipColor;
                switch (value) {
                  case 'accepted':
                    chipColor = Colors.green;
                    break;
                  case 'rejected':
                    chipColor = Colors.red;
                    break;
                  case 'pending':
                    chipColor = Colors.orange;
                    break;
                  default:
                    chipColor = olympusBlue;
                }
                return ChoiceChip(
                  label: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(labelText, style: const TextStyle(fontSize: 11)),
                      if (showBadges && count != null && count > 0) ...[
                        const SizedBox(width: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: chipColor,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            count.toString(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  selected: selected,
                  selectedColor: chipColor.withOpacity(0.2),
                  labelStyle: TextStyle(
                    color: selected ? chipColor : Colors.grey[700],
                    fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                    fontSize: 11,
                  ),
                  onSelected: (_) => onSelected(value),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 6),
        ],
      ),
    );
  }
}
