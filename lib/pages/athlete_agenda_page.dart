import 'dart:convert';
import 'dart:math' show sin, cos, sqrt, asin;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AthleteAgendaPage extends StatefulWidget {
  const AthleteAgendaPage({Key? key}) : super(key: key);

  @override
  State<AthleteAgendaPage> createState() => _AthleteAgendaPageState();
}

class _AthleteAgendaPageState extends State<AthleteAgendaPage> {
  final SupabaseClient _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _eventos = [];
  List<Map<String, dynamic>> _eventosFiltrados = [];
  Map<String, Map<String, String>> _convocationStatus = {};
  bool _loading = true;
  String? _error;
  String _filtroMes = '';
  String _filtroTipo = 'todos';
  // ✅ NOVO: Filtro por status da convocação
  String _filtroStatus = 'todos';
  // ✅ NOVO: Contadores de status
  Map<String, int> _statusCounts = {
    'accepted': 0,
    'rejected': 0,
    'pending': 0,
  };
  static const String _geocodeAccessKey = 'pk.5a7a05184e41c916429dceb50cf02718';
  static const String _eventsEmbedFk = 'convocations_event_id_fkey';

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
      map[eid] = (r['check_in_status'] ?? '').toString();
    }
    return map;
  }

  // ✅ NOVO: Calcular contadores de status
  void _calcularStatusCounts() {
    final counts = {'accepted': 0, 'rejected': 0, 'pending': 0};
    for (var evento in _eventos) {
      final status =
          (evento['convocation_status'] ?? 'pending').toString().toLowerCase();
      if (counts.containsKey(status)) {
        counts[status] = counts[status]! + 1;
      }
    }
    setState(() {
      _statusCounts = counts;
    });
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
          longitude
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
        final status =
            (item['status'] ?? 'pending').toString().toLowerCase().trim();
        if (eventData != null) {
          final mapEvento = Map<String, dynamic>.from(eventData);
          final eid = (mapEvento['id'] ?? '').toString();
          if (eid.isEmpty) continue;
          mapEvento['convocation_status'] = status;
          eventosList.add(mapEvento);
          statusMap[eid] = {'status': status};
        }
      }

      // ✅ AUTO-REJECT: Verifica e atualiza pendentes vencidos
      final idsParaAtualizar = <String>[];
      for (final evento in eventosList) {
        final status = (evento['convocation_status'] ?? 'pending')
            .toString()
            .toLowerCase();
        if (status == 'pending') {
          if (!_podeEditar(evento)) {
            final eid = evento['id'].toString();
            evento['convocation_status'] = 'rejected';
            statusMap[eid] = {'status': 'rejected'};
            idsParaAtualizar.add(eid);
          }
        }
      }
      if (idsParaAtualizar.isNotEmpty) {
        await Future.wait(idsParaAtualizar.map((eid) => _supabase
            .from('convocations')
            .update({'status': 'rejected', 'justification': 'Prazo expirado'})
            .eq('event_id', eid)
            .eq('user_id', user.id)));
      }

      final eventIds = eventosList.map((e) => e['id'].toString()).toList();
      final checkinMap = await _buscarCheckinsDoUsuario(user.id, eventIds);
      for (final e in eventosList) {
        final id = e['id'].toString();
        e['check_in_status'] = checkinMap[id];
      }

      eventosList.sort((a, b) {
        final dateA = (a['event_date'] ?? '').toString();
        final dateB = (b['event_date'] ?? '').toString();
        final timeA = (a['event_time'] ?? '').toString();
        final timeB = (b['event_time'] ?? '').toString();
        final compare = dateA.compareTo(dateB);
        if (compare != 0) return compare;
        return timeA.compareTo(timeB);
      });

      if (!mounted) return;
      setState(() {
        _eventos = eventosList;
        _convocationStatus = statusMap;
        _aplicarFiltros();
        _loading = false;
      });
      // ✅ NOVO: Calcular contadores após carregar eventos
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
    var eventosFiltrados = _eventos;
    if (_filtroMes.isNotEmpty) {
      eventosFiltrados = eventosFiltrados.where((evento) {
        final dataEvento = (evento['event_date'] ?? '').toString();
        if (dataEvento.length >= 7) {
          final mesAnoEvento = dataEvento.substring(3);
          return mesAnoEvento == _filtroMes;
        }
        return false;
      }).toList();
    }
    if (_filtroTipo != 'todos') {
      eventosFiltrados = eventosFiltrados.where((evento) {
        final tipo =
            (evento['event_type'] ?? '').toString().toLowerCase().trim();
        return tipo == _filtroTipo;
      }).toList();
    }
    // ✅ NOVO: Filtro por status da convocação
    if (_filtroStatus != 'todos') {
      eventosFiltrados = eventosFiltrados.where((evento) {
        final status = (evento['convocation_status'] ?? 'pending')
            .toString()
            .toLowerCase()
            .trim();
        return status == _filtroStatus;
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
          int.parse(parts[2]),
          int.parse(parts[1]),
          int.parse(parts[0]),
        );
        return DateFormat('dd/MM/yyyy (EEEE)', 'pt_BR').format(date);
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
    } catch (_) {
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
          'mensagem': 'Check-in disponível em $minutosRestantes min',
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

  Future<Map<String, double>> _geocodeCep(String cep) async {
    final cepLimpo = cep.replaceAll(RegExp(r'[^0-9]'), '');
    if (cepLimpo.isEmpty) throw Exception('CEP inválido');
    final uri = Uri.parse('https://api.positionstack.com/v1/forward'
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

      // ✅ CORREÇÃO CRÍTICA: Forçar GPS a obter posição FRESCA (ignorar cache)
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        forceAndroidLocationManager: true, // ✅ FORÇA GPS REAL - ignora cache
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

      // ✅ CORREÇÃO PRINCIPAL: Latitude e longitude na ordem CORRETA
      final res = await _supabase.rpc('do_checkin', params: {
        'p_event_id': evento['id'],
        'p_event_lat': eventLat, // ✅ latitude correta (não longitude)
        'p_event_lng': eventLng, // ✅ longitude correta (não latitude)
        'p_check_lat': pos.latitude, // ✅ latitude correta (não longitude)
        'p_check_lng': pos.longitude, // ✅ longitude correta (não latitude)
      });

      final ok = res?['ok'] == true;
      final st = (res?['status'] ?? '').toString();
      print('📍 Resultado do check-in: ok=$ok, status=$st');
      if (!mounted) return;
      if (ok) {
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

  // ✅ NOVO: Widget para filtro de status com marcador e BADGES
  Widget _buildFiltroStatusButtons() {
    Widget chip(String label, String value, Color badgeColor) {
      final selected = _filtroStatus == value;
      final count = _statusCounts[value] ?? 0;
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
          chipColor = Colors.blue;
      }
      return ChoiceChip(
        label: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label),
            if (count > 0) ...[
              const SizedBox(width: 6),
              // ✅ BADGE estilo imagem
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: badgeColor,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  count.toString(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ],
        ),
        selected: selected,
        selectedColor: chipColor.withOpacity(0.2),
        onSelected: (_) {
          setState(() {
            _filtroStatus = value;
            _aplicarFiltros();
          });
        },
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ✅ MARCADOR/TÍTULO
          const Padding(
            padding: EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              'Status da Convocação',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1E3A5F),
              ),
            ),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              chip('Todos', 'todos', Colors.grey),
              chip('Aceitou', 'accepted', Colors.green),
              chip('Recusou', 'rejected', Colors.red),
              chip('Pendentes', 'pending', Colors.orange),
            ],
          ),
        ],
      ),
    );
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
    return list.isEmpty ? <String>[_filtroMes] : list;
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
                      hint: Text(
                        'Mês',
                        style: TextStyle(color: Colors.grey[600]),
                      ),
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
          _buildFiltroTipoButtons(),
          // ✅ NOVO: Adicionado filtro de status com marcador e badges
          _buildFiltroStatusButtons(),
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
                            Text(
                              _error!,
                              style: const TextStyle(color: Colors.red),
                            ),
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
                                final eventId = evento['id'].toString();
                                final statusData = _convocationStatus[eventId];
                                final status = (statusData?['status'] ??
                                        evento['convocation_status'] ??
                                        'pending')
                                    .toString()
                                    .toLowerCase()
                                    .trim();
                                final eventType =
                                    (evento['event_type'] ?? '').toString();
                                final corTipo = _getCorTipoEvento(eventType);
                                final genero =
                                    (evento['gender'] ?? '').toString();
                                final podeEditar = _podeEditar(evento);
                                final prazoInfo = _getPrazoInfo(evento);
                                final championshipName =
                                    (evento['championship_name'] ?? '')
                                        .toString()
                                        .trim();
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
                                final checkinStatus =
                                    (evento['check_in_status'] ?? '')
                                        .toString()
                                        .trim();
                                final jaFezCheckin = checkinStatus.isNotEmpty;
                                final janelaCheckIn =
                                    _verificarJanelaCheckIn(evento);
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
                                            Icon(Icons.calendar_today,
                                                size: 16,
                                                color: Colors.grey[600]),
                                            const SizedBox(width: 8),
                                            Text(
                                              _formatarData(
                                                (evento['event_date'] ?? '')
                                                    .toString(),
                                              ),
                                              style: TextStyle(
                                                  color: Colors.grey[700]),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        Row(
                                          children: [
                                            Icon(Icons.access_time,
                                                size: 16,
                                                color: Colors.grey[600]),
                                            const SizedBox(width: 8),
                                            Text(
                                              (evento['event_time'] ?? '')
                                                  .toString(),
                                              style: TextStyle(
                                                  color: Colors.grey[700]),
                                            ),
                                          ],
                                        ),
                                        if (enderecoCompleto != null &&
                                            enderecoCompleto.isNotEmpty) ...[
                                          const SizedBox(height: 4),
                                          Row(
                                            children: [
                                              Icon(Icons.location_on,
                                                  size: 16,
                                                  color: Colors.grey[600]),
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
                                        if (prazoInfo.isNotEmpty) ...[
                                          Text(
                                            prazoInfo,
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: Colors.red,
                                              fontStyle: FontStyle.italic,
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                        ],
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
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: podeEditar
                                                    ? Colors.deepPurple
                                                    : Colors.grey,
                                                foregroundColor: Colors.white,
                                              ),
                                            ),
                                          ),
                                        ],
                                        const SizedBox(height: 10),
                                        if (jaFezCheckin)
                                          Row(
                                            children: [
                                              Icon(
                                                checkinStatus == 'ok'
                                                    ? Icons.verified
                                                    : Icons.error,
                                                color: checkinStatus == 'ok'
                                                    ? Colors.green
                                                    : Colors.red,
                                                size: 18,
                                              ),
                                              const SizedBox(width: 8),
                                              Text(
                                                'Check-in: $checkinStatus',
                                                style: TextStyle(
                                                  fontWeight: FontWeight.w600,
                                                  color: checkinStatus == 'ok'
                                                      ? Colors.green
                                                      : Colors.red,
                                                ),
                                              ),
                                            ],
                                          )
                                        else
                                          SizedBox(
                                            width: double.infinity,
                                            child: ElevatedButton.icon(
                                              onPressed: status == 'accepted' &&
                                                      janelaCheckIn[
                                                              'disponivel'] ==
                                                          true
                                                  ? () => _fazerCheckIn(evento)
                                                  : null,
                                              icon:
                                                  const Icon(Icons.my_location),
                                              label: Text(
                                                status == 'accepted'
                                                    ? (janelaCheckIn[
                                                                'disponivel'] ==
                                                            true
                                                        ? 'Fazer Check-in'
                                                        : janelaCheckIn[
                                                            'mensagem'])
                                                    : 'Fazer Check-in (aceite a convocação)',
                                              ),
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: status ==
                                                            'accepted' &&
                                                        janelaCheckIn[
                                                                'disponivel'] ==
                                                            true
                                                    ? Colors.green
                                                    : Colors.grey,
                                                foregroundColor: Colors.white,
                                              ),
                                            ),
                                          ),
                                        if (status == 'accepted' &&
                                            !jaFezCheckin) ...[
                                          const SizedBox(height: 8),
                                          Container(
                                            padding: const EdgeInsets.all(8),
                                            decoration: BoxDecoration(
                                              color: Colors.red[50],
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                              border: Border.all(
                                                  color: Colors.red[200]!),
                                            ),
                                            child: Row(
                                              children: [
                                                Icon(
                                                  Icons.info_outline,
                                                  size: 16,
                                                  color: Colors.red[700],
                                                ),
                                                const SizedBox(width: 8),
                                                Expanded(
                                                  child: Text(
                                                    '📍 Check-in: raio de 200m | Disponível 10 min antes até 30 min após o evento',
                                                    style: TextStyle(
                                                      fontSize: 11,
                                                      color: Colors.red[900],
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
    );
  }
}
