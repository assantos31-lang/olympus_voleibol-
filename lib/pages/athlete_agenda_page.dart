import 'dart:ui';
import 'dart:convert';
import 'dart:math' show sin, cos, sqrt, asin;
import 'package:flutter/material.dart';
import '../theme/olympus_theme.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../coach/pages/training_plan_readonly_sheet.dart';
import '../services/permission_service.dart';
import '../widgets/event_address_link.dart';

class AthleteAgendaPage extends StatefulWidget {
  final bool requireAgendaPermission;
  final bool coachMode;
  final String title;

  const AthleteAgendaPage({
    Key? key,
    this.requireAgendaPermission = true,
    this.coachMode = false,
    this.title = 'Minhas Convocações',
  }) : super(key: key);

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
  bool _mostrarEventosPassados = false;
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

    if (!widget.requireAgendaPermission) {
      if (!mounted) return;
      setState(() {
        _hasPermission = true;
        _checkingPermission = false;
        if (widget.coachMode) {
          _showStatusFilter = false;
          _allowedEventTypes = ['treino', 'amistoso', 'campeonato'];
        }
      });
      _setMesAtual();
      _buscarEventos();
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

  DateTime? _parseEventoDateTime(Map<String, dynamic> evento) {
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
    return null;
  }

  String _formatarHora(dynamic rawValue) {
    final value = (rawValue ?? '').toString().trim();
    if (value.isEmpty) return '';
    final match = RegExp(r'^(\d{1,2}):(\d{2})').firstMatch(value);
    if (match == null) return value;
    final hour = int.tryParse(match.group(1)!);
    final minute = int.tryParse(match.group(2)!);
    if (hour == null || minute == null || hour > 23 || minute > 59) {
      return value;
    }
    return '${hour.toString().padLeft(2, '0')}:'
        '${minute.toString().padLeft(2, '0')}';
  }

  bool _isEventoPassado(Map<String, dynamic> evento) {
    final dataHora = _parseEventoDateTime(evento);

    if (dataHora == null) return false;

    final limiteCheckin = dataHora.add(
      const Duration(minutes: 40),
    );

    return DateTime.now().isAfter(limiteCheckin);
  }

  bool _isMesmaData(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  int _getEventosPassadosCount() {
    return _getEventosDoMesAtual()
        .where((evento) => _isEventoPassado(evento))
        .length;
  }

  Map<String, List<Map<String, dynamic>>> _agruparEventosPorPeriodo() {
    final hoje = DateTime.now();
    final amanha = DateTime(hoje.year, hoje.month, hoje.day + 1);
    final grupos = <String, List<Map<String, dynamic>>>{
      'Hoje': <Map<String, dynamic>>[],
      'Amanhã': <Map<String, dynamic>>[],
      'Próximos': <Map<String, dynamic>>[],
      'Passados': <Map<String, dynamic>>[],
    };

    for (final evento in _eventosFiltrados) {
      final dataHora = _parseEventoDateTime(evento);
      if (_mostrarEventosPassados) {
        grupos['Passados']!.add(evento);
      } else if (dataHora != null && _isMesmaData(dataHora, hoje)) {
        grupos['Hoje']!.add(evento);
      } else if (dataHora != null && _isMesmaData(dataHora, amanha)) {
        grupos['Amanhã']!.add(evento);
      } else {
        grupos['Próximos']!.add(evento);
      }
    }

    return grupos;
  }

  Map<String, dynamic>? _getProximoEvento() {
    if (_mostrarEventosPassados) return null;

    final agora = DateTime.now();
    final futuros = _eventosFiltrados.where((evento) {
      final dataHora = _parseEventoDateTime(evento);
      return dataHora != null && !dataHora.isBefore(agora);
    }).toList();

    if (futuros.isEmpty) return null;

    futuros.sort((a, b) {
      final dataA = _parseEventoDateTime(a) ?? DateTime(9999);
      final dataB = _parseEventoDateTime(b) ?? DateTime(9999);
      return dataA.compareTo(dataB);
    });

    return futuros.first;
  }

  String _getCheckInCountdownMessage(Map<String, dynamic> evento) {
    final dataHora = _parseEventoDateTime(evento);
    if (dataHora == null) return '';
    final agora = DateTime.now();
    final inicioJanela = dataHora.subtract(const Duration(minutes: 10));

    if (agora.isBefore(inicioJanela)) {
      final minutos = inicioJanela.difference(agora).inMinutes;
      if (minutos >= 0 && minutos <= 60) {
        return 'Check-in libera em ${minutos <= 0 ? 1 : minutos} min';
      }
    }

    return '';
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
    final eventosDoPeriodo = _filtroMes.isEmpty
        ? List<Map<String, dynamic>>.from(_eventos)
        : _getEventosDoMesAtual();

    return eventosDoPeriodo.where((evento) {
      final passou = _isEventoPassado(evento);
      return _mostrarEventosPassados ? passou : !passou;
    }).toList();
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

  void _alternarEventosPassados() {
    setState(() {
      _mostrarEventosPassados = !_mostrarEventosPassados;
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
event_role,
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
      final scopedResponse = widget.coachMode
          ? response.where((item) {
              final role = (item['event_role'] ?? '').toString().toLowerCase();
              return role == 'coach' ||
                  role == 'treinador' ||
                  role == 'tecnico' ||
                  role == 'técnico';
            }).toList()
          : response;
      if (scopedResponse.isEmpty) {
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
      for (final item in scopedResponse) {
        final eventData = item['events'];
        final status = widget.coachMode
            ? 'accepted'
            : _normalizarConvocationStatus(item['status']);
        if (eventData != null) {
          final mapEvento = Map<String, dynamic>.from(eventData);
          final eid = (mapEvento['id'] ?? '').toString();
          if (eid.isEmpty) continue;
          mapEvento['convocation_status'] = status;
          eventosList.add(mapEvento);
          statusMap[eid] = {'status': status};
        }
      }
      if (!widget.coachMode) {
        final eventIds = eventosList.map((e) => e['id'].toString()).toList();
        final checkinMap = await _buscarCheckinsDoUsuario(user.id, eventIds);
        for (final e in eventosList) {
          final id = e['id'].toString();
          e['check_in_status'] = _normalizarCheckInStatus(checkinMap[id]);
        }
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
      final dataA = _parseEventoDateTime(a) ?? DateTime(9999);
      final dataB = _parseEventoDateTime(b) ?? DateTime(9999);
      if (_mostrarEventosPassados) {
        return dataB.compareTo(dataA);
      }
      return dataA.compareTo(dataB);
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
        return 'Liga / Camp.';
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
      borderRadius: BorderRadius.circular(999),
      onTap: () => _selecionarResumo(tipo, status),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? color.withOpacity(0.18) : color.withOpacity(0.09),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? color : color.withOpacity(0.24),
            width: selected ? 1.2 : 1,
          ),
        ),
        child: Text(
          '$label: $count',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: color,
            fontSize: 10.5,
            fontWeight: FontWeight.w900,
          ),
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
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 2),
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
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.97),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: colorBase.withOpacity(0.18)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.06),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
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
                    size: 14,
                  ),
                ),
                const SizedBox(width: 7),
                Text(
                  _getResumoTipoLabel(tipo),
                  style: TextStyle(
                    color: olympusBlue,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _buildResumoStatusChip(
                          tipo: tipo,
                          status: 'accepted',
                          label: 'Aceitou',
                          count: counts['accepted'] ?? 0,
                          color: Colors.green,
                        ),
                        const SizedBox(width: 5),
                        _buildResumoStatusChip(
                          tipo: tipo,
                          status: 'rejected',
                          label: 'Recusou',
                          count: counts['rejected'] ?? 0,
                          color: Colors.red,
                        ),
                        const SizedBox(width: 5),
                        _buildResumoStatusChip(
                          tipo: tipo,
                          status: 'pending',
                          label: 'Pendentes',
                          count: counts['pending'] ?? 0,
                          color: Colors.orange,
                        ),
                      ],
                    ),
                  ),
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
    final nomeEvento = (evento['event_name'] ?? '').toString().trim();
    final tipoEvento = (evento['event_type'] ?? 'Evento').toString().trim();
    final dataEvento = (evento['event_date'] ?? '').toString().trim();
    final horaEvento = (evento['event_time'] ?? '').toString().trim();
    final statusAtual =
        (evento['convocation_status'] ?? 'pending').toString().toLowerCase();

    final escolha = await showDialog<String>(
      context: context,
      barrierColor: Colors.black.withOpacity(0.58),
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 520),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: LinearGradient(
              colors: [
                olympusBlue,
                olympusLightBlue,
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            border: Border.all(
              color: olympusGold.withOpacity(0.55),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.30),
                blurRadius: 28,
                offset: const Offset(0, 12),
              ),
              BoxShadow(
                color: olympusGold.withOpacity(0.12),
                blurRadius: 24,
                spreadRadius: 1,
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: Stack(
              children: [
                Positioned(
                  top: -34,
                  right: -20,
                  child: Container(
                    width: 126,
                    height: 126,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withOpacity(0.06),
                    ),
                  ),
                ),
                Positioned(
                  bottom: -38,
                  left: -22,
                  child: Container(
                    width: 118,
                    height: 118,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: olympusGold.withOpacity(0.08),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 46,
                            height: 46,
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
                              boxShadow: [
                                BoxShadow(
                                  color: olympusGold.withOpacity(0.28),
                                  blurRadius: 14,
                                  offset: const Offset(0, 6),
                                ),
                              ],
                            ),
                            child: Icon(
                              Icons.edit_note_rounded,
                              color: olympusBlue,
                              size: 25,
                            ),
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Editar resposta',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 20,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                SizedBox(height: 2),
                                Text(
                                  'Atualize sua decisão para esta convocação',
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.pop(dialogContext, null),
                            icon: const Icon(Icons.close_rounded),
                            color: Colors.white70,
                            splashRadius: 20,
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.10),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.13),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: olympusGold.withOpacity(0.16),
                                    borderRadius: BorderRadius.circular(999),
                                    border: Border.all(
                                      color: olympusGold.withOpacity(0.50),
                                    ),
                                  ),
                                  child: Text(
                                    tipoEvento.toUpperCase(),
                                    style: TextStyle(
                                      color: olympusGold,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: _getStatusColor(statusAtual)
                                        .withOpacity(0.16),
                                    borderRadius: BorderRadius.circular(999),
                                    border: Border.all(
                                      color: _getStatusColor(statusAtual)
                                          .withOpacity(0.55),
                                    ),
                                  ),
                                  child: Text(
                                    'Atual: ${_getStatusLabel(statusAtual)}',
                                    style: TextStyle(
                                      color: _getStatusColor(statusAtual),
                                      fontSize: 11,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            if (nomeEvento.isNotEmpty) ...[
                              const SizedBox(height: 12),
                              Text(
                                nomeEvento,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  height: 1.2,
                                ),
                              ),
                            ],
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                const Icon(
                                  Icons.calendar_today_rounded,
                                  color: Colors.white70,
                                  size: 15,
                                ),
                                const SizedBox(width: 7),
                                Expanded(
                                  child: Text(
                                    '$dataEvento às $horaEvento',
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'Escolha abaixo se deseja aceitar ou recusar esta convocação.',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.75),
                          fontSize: 12.5,
                          height: 1.35,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () =>
                                  Navigator.pop(dialogContext, 'rejected'),
                              icon: const Icon(Icons.close_rounded, size: 18),
                              label: const Text('Recusar'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.white,
                                side: BorderSide(
                                  color: Colors.redAccent.withOpacity(0.78),
                                  width: 1.2,
                                ),
                                backgroundColor:
                                    Colors.redAccent.withOpacity(0.14),
                                padding:
                                    const EdgeInsets.symmetric(vertical: 13),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                textStyle: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () =>
                                  Navigator.pop(dialogContext, 'accepted'),
                              icon: const Icon(Icons.check_rounded, size: 18),
                              label: const Text('Aceitar'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: olympusGold,
                                foregroundColor: olympusBlue,
                                elevation: 0,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 13),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                textStyle: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: TextButton(
                          onPressed: () => Navigator.pop(dialogContext, null),
                          child: const Text(
                            'Cancelar',
                            style: TextStyle(
                              color: Colors.white70,
                              fontWeight: FontWeight.w700,
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
        await _notifyAdminsEventResponse(eventId, 'accepted');
        if (!mounted) return;
        _showSuccess('Convocação aceita!');
        _refreshEventos();
        return;
      }
      final controller = TextEditingController();
      final justification = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        barrierColor: Colors.black.withOpacity(0.58),
        builder: (dialogContext) {
          return Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 18,
              vertical: 24,
            ),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 520),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                gradient: LinearGradient(
                  colors: [
                    olympusBlue,
                    olympusLightBlue,
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                border: Border.all(
                  color: olympusGold.withOpacity(0.55),
                  width: 1.2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.30),
                    blurRadius: 28,
                    offset: const Offset(0, 12),
                  ),
                  BoxShadow(
                    color: olympusGold.withOpacity(0.12),
                    blurRadius: 24,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: Stack(
                  children: [
                    Positioned(
                      top: -34,
                      right: -20,
                      child: Container(
                        width: 126,
                        height: 126,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withOpacity(0.06),
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: -38,
                      left: -22,
                      child: Container(
                        width: 118,
                        height: 118,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: olympusGold.withOpacity(0.08),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 46,
                                height: 46,
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
                                  boxShadow: [
                                    BoxShadow(
                                      color: olympusGold.withOpacity(0.28),
                                      blurRadius: 14,
                                      offset: const Offset(0, 6),
                                    ),
                                  ],
                                ),
                                child: Icon(
                                  Icons.rate_review_rounded,
                                  color: olympusBlue,
                                  size: 24,
                                ),
                              ),
                              const SizedBox(width: 12),
                              const Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Justificativa obrigatória',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 19,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                    SizedBox(height: 3),
                                    Text(
                                      'Informe o motivo da recusa',
                                      style: TextStyle(
                                        color: Colors.white70,
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
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
                          const SizedBox(height: 16),
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.96),
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(
                                color: olympusGold.withOpacity(0.35),
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.10),
                                  blurRadius: 14,
                                  offset: const Offset(0, 6),
                                ),
                              ],
                            ),
                            child: TextField(
                              controller: controller,
                              maxLines: 4,
                              minLines: 3,
                              textCapitalization: TextCapitalization.sentences,
                              style: TextStyle(
                                color: olympusBlue,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                              decoration: InputDecoration(
                                hintText: 'Digite o motivo da recusa...',
                                hintStyle: TextStyle(
                                  color: Colors.grey[500],
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                ),
                                prefixIcon: Padding(
                                  padding: const EdgeInsets.only(
                                    left: 12,
                                    right: 8,
                                    bottom: 54,
                                  ),
                                  child: Icon(
                                    Icons.notes_rounded,
                                    color: olympusGold.withOpacity(0.95),
                                    size: 20,
                                  ),
                                ),
                                border: InputBorder.none,
                                contentPadding: const EdgeInsets.fromLTRB(
                                  4,
                                  16,
                                  14,
                                  16,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.10),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: Colors.white.withOpacity(0.12),
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.info_outline_rounded,
                                  color: Colors.white.withOpacity(0.80),
                                  size: 15,
                                ),
                                const SizedBox(width: 7),
                                Expanded(
                                  child: Text(
                                    'A justificativa será enviada junto com sua resposta.',
                                    style: TextStyle(
                                      color: Colors.white.withOpacity(0.76),
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: () =>
                                      Navigator.pop(dialogContext, null),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.white,
                                    side: BorderSide(
                                      color: Colors.white.withOpacity(0.26),
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 13,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    textStyle: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  child: const Text('Cancelar'),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: () {
                                    final text = controller.text.trim();
                                    if (text.isEmpty) return;
                                    Navigator.pop(dialogContext, text);
                                  },
                                  icon: const Icon(
                                    Icons.check_rounded,
                                    size: 18,
                                  ),
                                  label: const Text('Confirmar'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: olympusGold,
                                    foregroundColor: olympusBlue,
                                    elevation: 0,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 13,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    textStyle: const TextStyle(
                                      fontWeight: FontWeight.w900,
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
          );
        },
      );
      if (justification == null) return;
      await _supabase
          .from('convocations')
          .update({'status': 'rejected', 'justification': justification})
          .eq('event_id', eventId)
          .eq('user_id', user.id);
      await _notifyAdminsEventResponse(eventId, 'rejected');
      if (!mounted) return;
      _showError('Convocação recusada');
      _refreshEventos();
    } catch (e) {
      if (!mounted) return;
      _showError('Erro: $e');
    }
  }

  Future<void> _notifyAdminsEventResponse(
    dynamic eventId,
    String status,
  ) async {
    if (eventId == null) return;
    try {
      await _supabase.rpc(
        'notify_admins_event_response_v1',
        params: {
          'p_event_id': eventId,
          'p_status': status,
        },
      );
    } catch (e) {
      // A resposta do atleta é a ação principal e nunca deve ser desfeita
      // caso o aviso administrativo esteja temporariamente indisponível.
      debugPrint('Erro ao avisar administradores sobre convocação: $e');
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

      String buildRideText(Map<String, dynamic>? ride) {
        if (ride == null) return 'Não respondeu';

        final needsRide = ride['needs_ride'] == true;
        final hasCar = ride['has_car'] == true;
        final seatsRaw = ride['available_seats'];
        final seats =
            seatsRaw is int ? seatsRaw : int.tryParse('$seatsRaw') ?? 0;

        if (needsRide) return 'Precisa de carona';
        if (hasCar && seats > 0) {
          return 'Vou de carro e tenho $seats vaga${seats > 1 ? 's' : ''}';
        }
        if (hasCar && seats == 0) return 'Vou de carro e não tenho vagas';
        if (!needsRide && seats == 0) return 'Vou de carro e não tenho vagas';

        return 'Não respondeu';
      }

      final ridesByUser = <String, Map<String, Map<String, dynamic>>>{};
      try {
        final ridesResponse = await _supabase
            .from('event_rides')
            .select('user_id, ride_type, needs_ride, has_car, available_seats')
            .eq('event_id', eventIdRaw.toString());

        for (final rawRide in ridesResponse as List) {
          final ride = Map<String, dynamic>.from(rawRide);
          final userId = (ride['user_id'] ?? '').toString();
          final rideType =
              (ride['ride_type'] ?? '').toString().toLowerCase().trim();
          if (userId.isEmpty || rideType.isEmpty) continue;
          ridesByUser.putIfAbsent(userId, () => {})[rideType] = ride;
        }
      } catch (e) {
        debugPrint('Erro ao carregar caronas para exportação: $e');
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
                            style: TextStyle(
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

      String buildRideText(Map<String, dynamic>? ride) {
        if (ride == null) return 'Não respondeu';

        final needsRide = ride['needs_ride'] == true;
        final hasCar = ride['has_car'] == true;
        final seatsRaw = ride['available_seats'];
        final seats =
            seatsRaw is int ? seatsRaw : int.tryParse('$seatsRaw') ?? 0;

        if (needsRide) return 'Precisa de carona';
        if (hasCar && seats > 0) {
          return 'Vou de carro e tenho $seats vaga${seats > 1 ? 's' : ''}';
        }
        if (hasCar && seats == 0) return 'Vou de carro e não tenho vagas';
        if (!needsRide && seats == 0) return 'Vou de carro e não tenho vagas';

        return 'Não respondeu';
      }

      final ridesByUser = <String, Map<String, Map<String, dynamic>>>{};
      try {
        final ridesResponse = await _supabase
            .from('event_rides')
            .select('user_id, ride_type, needs_ride, has_car, available_seats')
            .eq('event_id', eventIdRaw.toString());

        for (final rawRide in ridesResponse as List) {
          final ride = Map<String, dynamic>.from(rawRide);
          final userId = (ride['user_id'] ?? '').toString();
          final rideType =
              (ride['ride_type'] ?? '').toString().toLowerCase().trim();
          if (userId.isEmpty || rideType.isEmpty) continue;
          ridesByUser.putIfAbsent(userId, () => {})[rideType] = ride;
        }
      } catch (e) {
        debugPrint('Erro ao carregar caronas para exportação: $e');
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
        final userId = (convocado['user_id'] ??
                convocado['id'] ??
                convocado['profile_id'] ??
                '')
            .toString();
        final userType = (convocado['user_type'] ?? '').toString();
        final cargo = userType == 'coach'
            ? 'Técnico'
            : userType == 'athlete'
                ? 'Atleta'
                : userType;
        final status = (convocado['status'] ?? 'pending').toString();

        if (status == 'accepted') {
          final userRides =
              ridesByUser[userId] ?? <String, Map<String, dynamic>>{};
          final idaRide = userRides['ida'];
          final voltaRide = userRides['volta'];
          final precisaCarona = (idaRide?['needs_ride'] == true) ||
                  (voltaRide?['needs_ride'] == true)
              ? 'Sim'
              : 'Não';

          aceitosLines.add(
            'Nome: $nome\n'
            'Tipo: ${cargo.isEmpty ? '-' : cargo}\n'
            'Data de nascimento: $dataNascimento\n'
            'RG: $rg\n'
            'Status: Aceitou\n'
            'Preciso de Carona: $precisaCarona\n'
            'Ida: ${buildRideText(idaRide)}\n'
            'Volta: ${buildRideText(voltaRide)}\n',
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
        labelStyle: TextStyle(
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
                    gradient: LinearGradient(
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
                                    child: Icon(
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
    meses.add(_getMesAtual());
    if (_filtroMes.isNotEmpty) meses.add(_filtroMes);
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
          child: OlympusBrandBackgroundImage(
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
                  olympusBlue.withOpacity(0.55),
                  olympusBlue.withOpacity(0.30),
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
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Agenda',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: colors.primary,
        foregroundColor: colors.onPrimary,
        iconTheme: IconThemeData(color: colors.onPrimary),
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
          Center(
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
    final branding = OlympusBrandingController.instance.branding;
    final colors = Theme.of(context).colorScheme;
    if (_checkingPermission) {
      return _buildPermissionCheckingScreen();
    }

    if (!_hasPermission) {
      return _buildAccessDeniedScreen();
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.title,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: colors.primary,
        foregroundColor: colors.onPrimary,
        iconTheme: IconThemeData(color: colors.onPrimary),
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
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      colors.primary,
                      Color.lerp(
                        colors.primary,
                        branding.backgroundColor,
                        0.18,
                      )!,
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
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 104,
                            child: _buildVisaoGeralButton(),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _buildModernDropdown(
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
                          ),
                          const SizedBox(width: 8),
                          SizedBox(
                            width: 104,
                            child: _buildEventosPassadosButton(),
                          ),
                        ],
                      ),
                    ] else ...[
                      _buildEventosPassadosButton(),
                    ],
                  ],
                ),
              ),
              _buildResumoPorTipoSection(),
              Expanded(
                child: _loading
                    ? Center(
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
                                      Text(
                                        _mostrarEventosPassados
                                            ? 'Nenhum evento passado encontrado'
                                            : 'Nenhuma convocação futura encontrada',
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
                                child: ListView(
                                  padding: const EdgeInsets.all(12),
                                  children: [
                                    ..._agruparEventosPorPeriodo()
                                        .entries
                                        .expand(
                                      (entry) {
                                        if (entry.value.isEmpty) {
                                          return <Widget>[];
                                        }
                                        return <Widget>[
                                          _buildPeriodoHeader(
                                            entry.key,
                                            entry.value.length,
                                          ),
                                          ...entry.value.map((evento) {
                                            final eventId =
                                                evento['id'].toString();
                                            final statusData =
                                                _convocationStatus[eventId];
                                            final status = (statusData?[
                                                        'status'] ??
                                                    evento[
                                                        'convocation_status'] ??
                                                    'pending')
                                                .toString()
                                                .toLowerCase()
                                                .trim();
                                            final eventType =
                                                (evento['event_type'] ?? '')
                                                    .toString();
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
                                                nomeNormalizado !=
                                                    tipoNormalizado &&
                                                nomeNormalizado !=
                                                    'evento ' + tipoNormalizado;
                                            final corTipo =
                                                _getCorTipoEvento(eventType);
                                            final genero =
                                                (evento['gender'] ?? '')
                                                    .toString();
                                            final podeEditar =
                                                _podeEditar(evento);
                                            final prazoInfo =
                                                _getPrazoInfo(evento);
                                            final championshipName =
                                                (evento['championship_name'] ??
                                                        '')
                                                    .toString()
                                                    .trim();
                                            String? enderecoCompleto;
                                            final street =
                                                (evento['street'] ?? '')
                                                    .toString()
                                                    .trim();
                                            if (street.isNotEmpty) {
                                              final numero =
                                                  (evento['street_number'] ??
                                                          '')
                                                      .toString()
                                                      .trim();
                                              final bairro =
                                                  (evento['neighborhood'] ?? '')
                                                      .toString()
                                                      .trim();
                                              final cidade =
                                                  (evento['city'] ?? '')
                                                      .toString()
                                                      .trim();
                                              final estado =
                                                  (evento['state'] ?? '')
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
                                                _isCheckInRealizado(
                                                    checkinStatus);
                                            final janelaCheckIn =
                                                _verificarJanelaCheckIn(evento);
                                            final podeFazerCheckin = status ==
                                                    'accepted' &&
                                                !jaFezCheckin &&
                                                janelaCheckIn['disponivel'] ==
                                                    true;
                                            final avisoCheckIn = status ==
                                                        'accepted' &&
                                                    !jaFezCheckin
                                                ? _getCheckInCountdownMessage(
                                                    evento)
                                                : '';
                                            return Card(
                                              margin: const EdgeInsets.only(
                                                  bottom: 10),
                                              elevation: 3,
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(14),
                                              ),
                                              color: _getCorFundoCard(
                                                  genero, eventType),
                                              child: Padding(
                                                padding:
                                                    const EdgeInsets.all(14),
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Row(
                                                      children: [
                                                        Container(
                                                          padding:
                                                              const EdgeInsets
                                                                  .symmetric(
                                                            horizontal: 12,
                                                            vertical: 7,
                                                          ),
                                                          decoration:
                                                              BoxDecoration(
                                                            color: corTipo
                                                                .withOpacity(
                                                                    0.14),
                                                            borderRadius:
                                                                BorderRadius
                                                                    .circular(
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
                                                                  FontWeight
                                                                      .w900,
                                                              fontSize: 14,
                                                              letterSpacing:
                                                                  0.7,
                                                            ),
                                                          ),
                                                        ),
                                                        const Spacer(),
                                                        Container(
                                                          padding:
                                                              const EdgeInsets
                                                                  .symmetric(
                                                            horizontal: 10,
                                                            vertical: 6,
                                                          ),
                                                          decoration:
                                                              BoxDecoration(
                                                            color:
                                                                _getStatusColor(
                                                                        status)
                                                                    .withOpacity(
                                                                        0.12),
                                                            borderRadius:
                                                                BorderRadius
                                                                    .circular(
                                                                        14),
                                                            border: Border.all(
                                                              color:
                                                                  _getStatusColor(
                                                                      status),
                                                              width: 1.2,
                                                            ),
                                                          ),
                                                          child: Text(
                                                            _getStatusLabel(
                                                                status),
                                                            style: TextStyle(
                                                              color:
                                                                  _getStatusColor(
                                                                      status),
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w800,
                                                              fontSize: 11.5,
                                                            ),
                                                          ),
                                                        ),
                                                        if (_canViewConvocados ||
                                                            _canExportDadosJogo) ...[
                                                          const SizedBox(
                                                              width: 4),
                                                          PopupMenuButton<
                                                              String>(
                                                            icon: Icon(
                                                              Icons.more_vert,
                                                              color: Colors
                                                                  .grey[700],
                                                              size: 20,
                                                            ),
                                                            onSelected:
                                                                (value) {
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
                                                            itemBuilder:
                                                                (context) {
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
                                                                          size:
                                                                              18,
                                                                          color:
                                                                              Colors.green,
                                                                        ),
                                                                        SizedBox(
                                                                            width:
                                                                                8),
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
                                                                          size:
                                                                              18,
                                                                          color:
                                                                              Colors.green,
                                                                        ),
                                                                        SizedBox(
                                                                            width:
                                                                                8),
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
                                                          fontWeight:
                                                              FontWeight.w800,
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
                                                          Icon(
                                                              Icons
                                                                  .emoji_events,
                                                              size: 14,
                                                              color: Colors
                                                                  .amber[700]),
                                                          const SizedBox(
                                                              width: 6),
                                                          Expanded(
                                                            child: Text(
                                                              championshipName,
                                                              style: TextStyle(
                                                                fontSize: 13,
                                                                color: Colors
                                                                    .amber[900],
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w700,
                                                              ),
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ],
                                                    const SizedBox(height: 6),
                                                    Row(
                                                      children: [
                                                        Icon(
                                                            Icons
                                                                .calendar_today,
                                                            size: 16,
                                                            color: Colors
                                                                .grey[600]),
                                                        const SizedBox(
                                                            width: 6),
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
                                                                  dataParts
                                                                          .isNotEmpty
                                                                      ? dataParts[
                                                                          0]
                                                                      : '';
                                                              final diaSemana =
                                                                  dataParts.length >
                                                                          1
                                                                      ? dataParts[
                                                                          1]
                                                                      : '';

                                                              return RichText(
                                                                text: TextSpan(
                                                                  style:
                                                                      TextStyle(
                                                                    color: Colors
                                                                            .grey[
                                                                        700],
                                                                    fontSize:
                                                                        13,
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .w600,
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
                                                                              FontWeight.w900,
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
                                                            color: Colors
                                                                .grey[600]),
                                                        const SizedBox(
                                                            width: 6),
                                                        Text(
                                                          _formatarHora(
                                                            evento[
                                                                'event_time'],
                                                          ),
                                                          style: TextStyle(
                                                            color: Colors
                                                                .grey[700],
                                                            fontSize: 13,
                                                            fontWeight:
                                                                FontWeight.w600,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                    if (enderecoCompleto !=
                                                            null &&
                                                        enderecoCompleto
                                                            .isNotEmpty) ...[
                                                      const SizedBox(height: 2),
                                                      EventAddressLink(
                                                        event: evento,
                                                        address:
                                                            enderecoCompleto,
                                                        iconColor:
                                                            Colors.grey[700],
                                                        iconSize: 15,
                                                        maxLines: 1,
                                                        style: TextStyle(
                                                          color:
                                                              Colors.grey[700],
                                                          fontSize: 12,
                                                          fontWeight:
                                                              FontWeight.w500,
                                                        ),
                                                      ),
                                                    ],
                                                    const SizedBox(height: 8),
                                                    if (prazoInfo
                                                        .isNotEmpty) ...[
                                                      Text(
                                                        prazoInfo,
                                                        style: TextStyle(
                                                          fontSize: 10,
                                                          color:
                                                              Colors.red[700],
                                                          fontStyle:
                                                              FontStyle.italic,
                                                        ),
                                                      ),
                                                      const SizedBox(height: 6),
                                                    ],
                                                    if (tipoNormalizado ==
                                                        'treino') ...[
                                                      SizedBox(
                                                        height: 34,
                                                        width: double.infinity,
                                                        child:
                                                            ElevatedButton.icon(
                                                          onPressed: () =>
                                                              TrainingPlanReadonlySheet
                                                                  .show(
                                                            context,
                                                            event: evento,
                                                            emptyMessage:
                                                                'Este treino ainda não tem planejamento publicado.',
                                                          ),
                                                          icon: const Icon(
                                                            Icons
                                                                .menu_book_rounded,
                                                            size: 16,
                                                          ),
                                                          label: const Text(
                                                            'Ver planejamento',
                                                            style: TextStyle(
                                                              fontSize: 11,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w900,
                                                            ),
                                                          ),
                                                          style: ElevatedButton
                                                              .styleFrom(
                                                            backgroundColor:
                                                                olympusBlue,
                                                            foregroundColor:
                                                                Colors.white,
                                                            elevation: 0,
                                                            padding:
                                                                EdgeInsets.zero,
                                                            shape:
                                                                RoundedRectangleBorder(
                                                              borderRadius:
                                                                  BorderRadius
                                                                      .circular(
                                                                          12),
                                                            ),
                                                          ),
                                                        ),
                                                      ),
                                                      const SizedBox(height: 8),
                                                    ],
                                                    if (!widget.coachMode &&
                                                        status == 'pending')
                                                      Row(
                                                        children: [
                                                          Expanded(
                                                            child: SizedBox(
                                                              height: 32,
                                                              child:
                                                                  ElevatedButton
                                                                      .icon(
                                                                onPressed: podeEditar
                                                                    ? () => _responderConvocacao(
                                                                        evento,
                                                                        false)
                                                                    : null,
                                                                icon:
                                                                    const Icon(
                                                                  Icons.close,
                                                                  size: 16,
                                                                ),
                                                                label:
                                                                    const Text(
                                                                  'Recusar',
                                                                  style:
                                                                      TextStyle(
                                                                    fontSize:
                                                                        11,
                                                                  ),
                                                                ),
                                                                style: ElevatedButton
                                                                    .styleFrom(
                                                                  backgroundColor:
                                                                      podeEditar
                                                                          ? Colors
                                                                              .red
                                                                          : Colors
                                                                              .grey,
                                                                  foregroundColor:
                                                                      Colors
                                                                          .white,
                                                                  padding:
                                                                      EdgeInsets
                                                                          .zero,
                                                                ),
                                                              ),
                                                            ),
                                                          ),
                                                          const SizedBox(
                                                              width: 8),
                                                          Expanded(
                                                            child: SizedBox(
                                                              height: 32,
                                                              child:
                                                                  ElevatedButton
                                                                      .icon(
                                                                onPressed: podeEditar
                                                                    ? () => _responderConvocacao(
                                                                        evento,
                                                                        true)
                                                                    : null,
                                                                icon:
                                                                    const Icon(
                                                                  Icons.check,
                                                                  size: 16,
                                                                ),
                                                                label:
                                                                    const Text(
                                                                  'Aceitar',
                                                                  style:
                                                                      TextStyle(
                                                                    fontSize:
                                                                        11,
                                                                  ),
                                                                ),
                                                                style: ElevatedButton
                                                                    .styleFrom(
                                                                  backgroundColor: podeEditar
                                                                      ? Colors
                                                                          .green
                                                                      : Colors
                                                                          .grey,
                                                                  foregroundColor:
                                                                      Colors
                                                                          .white,
                                                                  padding:
                                                                      EdgeInsets
                                                                          .zero,
                                                                ),
                                                              ),
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    if (!widget.coachMode &&
                                                        status !=
                                                            'pending') ...[
                                                      const SizedBox(height: 6),
                                                      SizedBox(
                                                        height: 32,
                                                        width: double.infinity,
                                                        child:
                                                            ElevatedButton.icon(
                                                          onPressed: podeEditar
                                                              ? () =>
                                                                  _editarResposta(
                                                                      evento)
                                                              : null,
                                                          icon: const Icon(
                                                            Icons.edit,
                                                            size: 16,
                                                          ),
                                                          label: const Text(
                                                            'Editar resposta',
                                                            style: TextStyle(
                                                                fontSize: 11),
                                                          ),
                                                          style: ElevatedButton
                                                              .styleFrom(
                                                            backgroundColor:
                                                                podeEditar
                                                                    ? Colors
                                                                        .deepPurple
                                                                    : Colors
                                                                        .grey,
                                                            foregroundColor:
                                                                Colors.white,
                                                            padding:
                                                                EdgeInsets.zero,
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                    if (!widget.coachMode &&
                                                        avisoCheckIn
                                                            .isNotEmpty) ...[
                                                      const SizedBox(height: 8),
                                                      Container(
                                                        padding:
                                                            const EdgeInsets
                                                                .symmetric(
                                                          horizontal: 10,
                                                          vertical: 7,
                                                        ),
                                                        decoration:
                                                            BoxDecoration(
                                                          color:
                                                              Colors.orange[50],
                                                          borderRadius:
                                                              BorderRadius
                                                                  .circular(10),
                                                          border: Border.all(
                                                            color: Colors
                                                                .orange[200]!,
                                                          ),
                                                        ),
                                                        child: Row(
                                                          children: [
                                                            Icon(
                                                              Icons
                                                                  .timer_outlined,
                                                              size: 16,
                                                              color: Colors
                                                                  .orange[800],
                                                            ),
                                                            const SizedBox(
                                                                width: 7),
                                                            Expanded(
                                                              child: Text(
                                                                avisoCheckIn,
                                                                style:
                                                                    TextStyle(
                                                                  fontSize: 11,
                                                                  color: Colors
                                                                          .orange[
                                                                      900],
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w800,
                                                                ),
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                    ],
                                                    if (!widget.coachMode &&
                                                        (jaFezCheckin ||
                                                            podeFazerCheckin)) ...[
                                                      const SizedBox(height: 8),
                                                      if (jaFezCheckin)
                                                        Row(
                                                          children: [
                                                            const Icon(
                                                              Icons.verified,
                                                              color:
                                                                  Colors.green,
                                                              size: 16,
                                                            ),
                                                            const SizedBox(
                                                                width: 6),
                                                            const Text(
                                                              'Check-in realizado',
                                                              style: TextStyle(
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w600,
                                                                fontSize: 11,
                                                                color: Colors
                                                                    .green,
                                                              ),
                                                            ),
                                                          ],
                                                        )
                                                      else
                                                        SizedBox(
                                                          height: 32,
                                                          width:
                                                              double.infinity,
                                                          child: ElevatedButton
                                                              .icon(
                                                            onPressed: () =>
                                                                _fazerCheckIn(
                                                                    evento),
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
                                                            style:
                                                                ElevatedButton
                                                                    .styleFrom(
                                                              backgroundColor:
                                                                  Colors.green,
                                                              foregroundColor:
                                                                  Colors.white,
                                                              padding:
                                                                  EdgeInsets
                                                                      .zero,
                                                            ),
                                                          ),
                                                        ),
                                                    ],
                                                    if (podeFazerCheckin) ...[
                                                      const SizedBox(height: 6),
                                                      Container(
                                                        padding:
                                                            const EdgeInsets
                                                                .symmetric(
                                                          horizontal: 8,
                                                          vertical: 4,
                                                        ),
                                                        decoration:
                                                            BoxDecoration(
                                                          color: Colors.red[50],
                                                          borderRadius:
                                                              BorderRadius
                                                                  .circular(6),
                                                          border: Border.all(
                                                            color: Colors
                                                                .red[200]!,
                                                          ),
                                                        ),
                                                        child: Row(
                                                          children: [
                                                            Icon(
                                                              Icons
                                                                  .info_outline,
                                                              size: 14,
                                                              color: Colors
                                                                  .red[700],
                                                            ),
                                                            const SizedBox(
                                                                width: 6),
                                                            Expanded(
                                                              child: Text(
                                                                '📍 Raio 200m | 10min antes até 30min após',
                                                                style:
                                                                    TextStyle(
                                                                  fontSize: 10,
                                                                  color: Colors
                                                                      .red[900],
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w500,
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
                                          }).toList(),
                                        ];
                                      },
                                    ),
                                  ],
                                ),
                              ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPeriodoHeader(String titulo, int count) {
    IconData icon;
    Color color;

    switch (titulo) {
      case 'Hoje':
        icon = Icons.today_rounded;
        color = olympusGold;
        break;
      case 'Amanhã':
        icon = Icons.wb_sunny_outlined;
        color = Colors.orange;
        break;
      case 'Passados':
        icon = Icons.history_rounded;
        color = Colors.grey;
        break;
      default:
        icon = Icons.event_available_rounded;
        color = Colors.lightBlue;
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 10, 2, 8),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: color.withOpacity(0.16),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: color.withOpacity(0.35)),
            ),
            child: Icon(icon, size: 16, color: color),
          ),
          const SizedBox(width: 8),
          Text(
            '$titulo ($count)',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Container(
              height: 1,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.white.withOpacity(0.28),
                    Colors.white.withOpacity(0.02),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProximoEventoDestaque(Map<String, dynamic> evento) {
    final eventType = (evento['event_type'] ?? 'Evento').toString();
    final nomeEvento = (evento['event_name'] ?? '').toString().trim();
    final dataFormatada =
        _formatarData((evento['event_date'] ?? '').toString()).split('|');
    final data = dataFormatada.isNotEmpty ? dataFormatada[0] : '';
    final diaSemana = dataFormatada.length > 1 ? dataFormatada[1] : '';
    final hora = _formatarHora(evento['event_time']);
    final corTipo = _getCorTipoEvento(eventType);
    final avisoCheckIn = _getCheckInCountdownMessage(evento);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          colors: [
            olympusGold.withOpacity(0.96),
            const Color(0xFFF4D96A).withOpacity(0.92),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(
          color: Colors.white.withOpacity(0.45),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: olympusGold.withOpacity(0.24),
            blurRadius: 18,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: olympusBlue.withOpacity(0.12),
              shape: BoxShape.circle,
              border: Border.all(color: olympusBlue.withOpacity(0.22)),
            ),
            child: Icon(
              Icons.star_rounded,
              color: olympusBlue,
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Próximo evento',
                  style: TextStyle(
                    color: olympusBlue,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.7,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  nomeEvento.isNotEmpty ? nomeEvento : eventType.toUpperCase(),
                  style: TextStyle(
                    color: olympusBlue,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    height: 1.1,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    _buildMiniInfoPill(
                      icon: Icons.calendar_today_rounded,
                      label: diaSemana.isNotEmpty ? '$data • $diaSemana' : data,
                      color: olympusBlue,
                    ),
                    _buildMiniInfoPill(
                      icon: Icons.access_time_rounded,
                      label: hora,
                      color: olympusBlue,
                    ),
                    _buildMiniInfoPill(
                      icon: Icons.local_activity_rounded,
                      label: eventType.toUpperCase(),
                      color: corTipo,
                    ),
                    if (avisoCheckIn.isNotEmpty)
                      _buildMiniInfoPill(
                        icon: Icons.timer_outlined,
                        label: avisoCheckIn.replaceFirst('Check-in ', ''),
                        color: Colors.deepOrange,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMiniInfoPill({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    if (label.trim().isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.58),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVisaoGeralButton() {
    final label = _isVisaoGeral ? 'Mês atual' : 'Geral';
    return SizedBox(
      height: 56,
      child: ElevatedButton.icon(
        onPressed: _alternarVisaoGeral,
        icon: Icon(
          _isVisaoGeral
              ? Icons.calendar_month_rounded
              : Icons.dashboard_customize_rounded,
          size: 16,
        ),
        label: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: _isVisaoGeral ? olympusGold : Colors.white,
          foregroundColor: olympusBlue,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }

  Widget _buildEventosPassadosButton() {
    final count = _getEventosPassadosCount();

    return SizedBox(
      height: 56,
      child: ElevatedButton(
        onPressed: _alternarEventosPassados,
        style: ElevatedButton.styleFrom(
          backgroundColor: _mostrarEventosPassados ? olympusGold : Colors.white,
          foregroundColor: olympusBlue,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              _mostrarEventosPassados
                  ? Icons.upcoming_rounded
                  : Icons.history_rounded,
              size: 16,
            ),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                _mostrarEventosPassados ? 'Futuros' : 'Passados',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            if (!_mostrarEventosPassados) ...[
              const SizedBox(width: 5),
              Container(
                constraints: const BoxConstraints(
                  minWidth: 20,
                  minHeight: 20,
                ),
                padding: const EdgeInsets.symmetric(horizontal: 5),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: olympusGold,
                  borderRadius: BorderRadius.circular(999),
                  boxShadow: [
                    BoxShadow(
                      color: olympusGold.withOpacity(0.28),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Text(
                  count.toString(),
                  style: TextStyle(
                    color: olympusBlue,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ],
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
            padding: const EdgeInsets.fromLTRB(10, 5, 10, 0),
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
          const SizedBox(height: 2),
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
