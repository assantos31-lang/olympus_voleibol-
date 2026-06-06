import 'dart:convert';
import 'dart:math' show asin, cos, sin, sqrt;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/permission_service.dart';
import 'coach_championship_scout_page.dart' as championship_scout;

class CoachTrainingSessionsPage extends StatefulWidget {
  final String initialTipoEvento;
  final bool lockTipoEvento;

  const CoachTrainingSessionsPage({
    super.key,
    this.initialTipoEvento = 'treino',
    this.lockTipoEvento = false,
  });

  @override
  State<CoachTrainingSessionsPage> createState() =>
      _CoachTrainingSessionsPageState();
}

class _CoachTrainingSessionsPageState extends State<CoachTrainingSessionsPage> {
  final SupabaseClient _supabase = Supabase.instance.client;

  static const Color olympusBlue = Color(0xFF1E3A5F);
  static const Color olympusGold = Color(0xFFD4AF37);
  static const Color olympusLightBlue = Color(0xFF2C5F8D);
  static const Color olympusBg = Color(0xFFF4F7FB);
  static const Color olympusCard = Colors.white;
  static const Color olympusText = Color(0xFF17324D);
  static const Color olympusMuted = Color(0xFF53657B);
  static const Color olympusSubtle = Color(0xFF6A7E94);
  static const Color olympusBorder = Color(0xFFE4EDF5);
  static const Color olympusSuccess = Color(0xFF16A34A);
  static const Color olympusWarning = Color(0xFFF59E0B);
  static const Color olympusDanger = Color(0xFFDC2626);
  static const Color olympusPurple = Color(0xFF7C3AED);
  static const String _geocodeAccessKey = 'pk.5a7a05184e41c916429dceb50cf02718';

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _treinos = [];
  List<Map<String, dynamic>> _treinosFiltrados = [];

  String _filtroMes = '';
  String _filtroStatus = 'todos';
  late String _filtroTipoEvento;
  Map<String, int> _typeCounts = {
    'treino': 0,
    'campeonato': 0,
    'liga': 0,
  };
  Map<String, int> _statusCounts = {
    'accepted': 0,
    'rejected': 0,
    'pending': 0,
  };

  @override
  void initState() {
    super.initState();
    _filtroTipoEvento = _normalizarTipoEvento(widget.initialTipoEvento);
    if (!_isTipoEventoSuportado(_filtroTipoEvento)) {
      _filtroTipoEvento = 'treino';
    }
    _setMesAtual();
    _buscarTreinosDoTecnico();
  }

  void _setMesAtual() {
    final now = DateTime.now();
    _filtroMes = '${now.month.toString().padLeft(2, '0')}/${now.year}';
  }

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

  bool _isTipoEventoSuportado(dynamic value) {
    final tipo = _normalizarTipoEvento(value);
    return tipo == 'treino' || tipo == 'campeonato' || tipo == 'liga';
  }

  String _labelTipoEvento(dynamic value) {
    final tipo = _normalizarTipoEvento(value);

    switch (tipo) {
      case 'treino':
        return 'Treino';
      case 'campeonato':
        return 'Campeonato';
      case 'liga':
        return 'Liga';
      default:
        return tipo.isEmpty ? 'Evento' : tipo;
    }
  }

  Color _colorTipoEvento(dynamic value) {
    final tipo = _normalizarTipoEvento(value);

    switch (tipo) {
      case 'treino':
        return Colors.blue;
      case 'campeonato':
        return olympusGold;
      case 'liga':
        return olympusPurple;
      default:
        return olympusBlue;
    }
  }

  IconData _iconTipoEvento(dynamic value) {
    final tipo = _normalizarTipoEvento(value);

    switch (tipo) {
      case 'treino':
        return Icons.fitness_center;
      case 'campeonato':
        return Icons.emoji_events_rounded;
      case 'liga':
        return Icons.workspace_premium_rounded;
      default:
        return Icons.event_rounded;
    }
  }

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
        backgroundColor: olympusDanger,
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
        backgroundColor: olympusSuccess,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
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
    for (final row in rows) {
      final eventId = (row['event_id'] ?? '').toString();
      if (eventId.isEmpty) continue;
      map[eventId] = _normalizarCheckInStatus(row['check_in_status']);
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

  Future<void> _sincronizarCheckInStatus(String eventId, String userId) async {
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
      debugPrint('Erro ao sincronizar check-in: $e');
    }
  }

  Future<void> _buscarTreinosDoTecnico() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final user = _supabase.auth.currentUser;
      if (user == null) {
        setState(() {
          _loading = false;
          _error = 'Usuário não autenticado.';
        });
        return;
      }

      final response = await _supabase.from('convocations').select('''
id,
event_id,
status,
justification,
events!convocations_event_id_fkey (
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
  allow_checkin,
  enable_ride_logistics
)
''').eq('user_id', user.id);

      final treinos = <Map<String, dynamic>>[];

      for (final item in response) {
        final rawEvent = item['events'];
        if (rawEvent == null) continue;

        final event = Map<String, dynamic>.from(rawEvent);
        final eventType =
            (event['event_type'] ?? '').toString().toLowerCase().trim();

        if (!_isTipoEventoSuportado(eventType)) continue;

        event['normalized_event_type'] = _normalizarTipoEvento(eventType);
        event['convocation_id'] = item['id'];
        event['convocation_status'] =
            (item['status'] ?? 'pending').toString().toLowerCase().trim();
        event['justification'] = item['justification'];
        treinos.add(event);
      }

      final eventIds = treinos.map((e) => e['id'].toString()).toList();
      final checkinMap = await _buscarCheckinsDoUsuario(user.id, eventIds);

      for (final treino in treinos) {
        final id = treino['id'].toString();
        treino['check_in_status'] = _normalizarCheckInStatus(checkinMap[id]);
      }

      treinos.sort(
        (a, b) => _parseEventDateTime(a).compareTo(_parseEventDateTime(b)),
      );

      if (!mounted) return;
      setState(() {
        _treinos = treinos;
        _aplicarFiltros();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Erro ao carregar treinos: $e';
      });
    }
  }

  DateTime _parseEventDateTime(Map<String, dynamic> evento) {
    try {
      final data = (evento['event_date'] ?? '').toString().trim();
      final hora = (evento['event_time'] ?? '').toString().trim();

      final dataPartes = data.split('/');
      final horaPartes = hora.split(':');

      if (dataPartes.length == 3 && horaPartes.length >= 2) {
        return DateTime(
          int.parse(dataPartes[2]),
          int.parse(dataPartes[1]),
          int.parse(dataPartes[0]),
          int.parse(horaPartes[0]),
          int.parse(horaPartes[1]),
        );
      }
    } catch (_) {}

    return DateTime(2100);
  }

  String _formatarDataHora(Map<String, dynamic> evento) {
    final data = (evento['event_date'] ?? '').toString().trim();
    final hora = (evento['event_time'] ?? '').toString().trim();

    if (data.isEmpty && hora.isEmpty) return 'Sem data definida';
    if (data.isEmpty) return hora;
    if (hora.isEmpty) return data;
    return '$data • $hora';
  }

  String _formatarEndereco(Map<String, dynamic> evento) {
    final street = (evento['street'] ?? '').toString().trim();
    final number = (evento['street_number'] ?? '').toString().trim();
    final neighborhood = (evento['neighborhood'] ?? '').toString().trim();
    final city = (evento['city'] ?? '').toString().trim();
    final state = (evento['state'] ?? '').toString().trim();

    if (street.isEmpty) return '';

    return '$street${number.isNotEmpty ? ', $number' : ''}'
        '${neighborhood.isNotEmpty ? ' - $neighborhood' : ''}'
        '${city.isNotEmpty ? ' - $city' : ''}'
        '${state.isNotEmpty ? '/$state' : ''}';
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
      _filtroStatus = 'todos';
      _aplicarFiltros();
    });
  }

  void _selecionarMes(String mes) {
    setState(() {
      _filtroMes = mes;
      _filtroStatus = 'todos';
      _aplicarFiltros();
    });
  }

  List<Map<String, dynamic>> _getTreinosBaseFiltro() {
    if (_filtroMes.isEmpty) return List<Map<String, dynamic>>.from(_treinos);

    return _treinos.where((evento) {
      final dataEvento = (evento['event_date'] ?? '').toString();
      if (dataEvento.length >= 7) {
        final mesAnoEvento = dataEvento.substring(3);
        return mesAnoEvento == _filtroMes;
      }
      return false;
    }).toList();
  }

  List<Map<String, dynamic>> _getEventosDoTipoSelecionado() {
    return _getTreinosBaseFiltro().where((evento) {
      final tipo = _normalizarTipoEvento(
        evento['normalized_event_type'] ?? evento['event_type'],
      );
      return tipo == _filtroTipoEvento;
    }).toList();
  }

  void _atualizarResumoStatus() {
    final typeCounts = {
      'treino': 0,
      'campeonato': 0,
      'liga': 0,
    };

    for (final evento in _getTreinosBaseFiltro()) {
      final tipo = _normalizarTipoEvento(
        evento['normalized_event_type'] ?? evento['event_type'],
      );

      if (typeCounts.containsKey(tipo)) {
        typeCounts[tipo] = typeCounts[tipo]! + 1;
      }
    }

    final counts = {'accepted': 0, 'rejected': 0, 'pending': 0};

    for (final evento in _getEventosDoTipoSelecionado()) {
      final status =
          (evento['convocation_status'] ?? 'pending').toString().toLowerCase();
      if (counts.containsKey(status)) {
        counts[status] = counts[status]! + 1;
      }
    }

    _typeCounts = typeCounts;
    _statusCounts = counts;
  }

  void _selecionarTipoEvento(String tipo) {
    if (widget.lockTipoEvento) return;
    if (_filtroTipoEvento == tipo) return;

    setState(() {
      _filtroTipoEvento = tipo;
      _filtroStatus = 'todos';
      _aplicarFiltros();
    });
  }

  void _selecionarResumo(String status) {
    final filtroAtivo = _filtroStatus == status;

    setState(() {
      _filtroStatus = filtroAtivo ? 'todos' : status;
      _aplicarFiltros();
    });
  }

  void _aplicarFiltros() {
    var lista = _getEventosDoTipoSelecionado();

    if (_filtroStatus != 'todos') {
      lista = lista.where((treino) {
        final status = (treino['convocation_status'] ?? 'pending')
            .toString()
            .toLowerCase()
            .trim();
        return status == _filtroStatus;
      }).toList();
    }

    lista.sort(
      (a, b) => _parseEventDateTime(a).compareTo(_parseEventDateTime(b)),
    );

    _treinosFiltrados = lista;
    _atualizarResumoStatus();
  }

  List<String> _getMesesDisponiveis() {
    final meses = <String>{};
    for (final e in _treinos) {
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

      return eventDateTime.difference(now).inMinutes >= 0;
    } catch (_) {
      return false;
    }
  }

  String _getPrazoInfo(Map<String, dynamic> evento) {
    final tipo = (evento['event_type'] ?? '').toString().toLowerCase().trim();
    switch (tipo) {
      case 'treino':
        return 'Edição até o horário do treino';
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
        'mensagem': 'Horário do evento não definido',
      };
    }

    try {
      final dp = dataStr.split('/');
      final tp = horaStr.split(':');
      if (dp.length != 3 || tp.length < 2) {
        return {
          'disponivel': false,
          'mensagem': 'Formato de data/hora inválido',
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
      return {
        'disponivel': false,
        'mensagem': 'Erro ao verificar horário',
      };
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
          border: Border.all(color: Colors.white.withOpacity(0.10)),
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
                const Expanded(
                  child: Text(
                    'Precisa de carona?',
                    style: TextStyle(
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
                      colors: [olympusBlue, olympusLightBlue],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 42,
                                height: 42,
                                decoration: const BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: LinearGradient(
                                    colors: [
                                      Color(0xFFF0D771),
                                      Color(0xFFB48A23),
                                    ],
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
                            'Informe sua disponibilidade de ida e volta.',
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
                                              'has_car': (seatsIda ?? 0) > 0,
                                              'available_seats': seatsIda ?? 0,
                                            },
                                            'volta': {
                                              'needs_ride': needsRideVolta,
                                              'has_car': (seatsVolta ?? 0) > 0,
                                              'available_seats':
                                                  seatsVolta ?? 0,
                                            },
                                          });
                                        }
                                      : null,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: olympusGold,
                                    foregroundColor: olympusBlue,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 13,
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

    final uri = Uri.parse(
      'https://api.positionstack.com/v1/forward'
      '?access_key=$_geocodeAccessKey'
      '&query=$cepLimpo'
      '&country=BR'
      '&limit=1',
    );

    final response = await http.get(uri);
    if (response.statusCode != 200) {
      throw Exception('Erro geocode (${response.statusCode})');
    }

    final body = json.decode(response.body) as Map<String, dynamic>;
    final data = (body['data'] as List?) ?? const [];
    if (data.isEmpty) {
      throw Exception('CEP não encontrado no geocode');
    }

    final first = data.first as Map<String, dynamic>;
    final lat = (first['latitude'] as num?)?.toDouble();
    final lng = (first['longitude'] as num?)?.toDouble();
    if (lat == null || lng == null) {
      throw Exception('Geocode inválido');
    }

    return {'lat': lat, 'lng': lng};
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
        await _buscarTreinosDoTecnico();
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
      await _buscarTreinosDoTecnico();
    } catch (e) {
      if (!mounted) return;
      _showError('Erro: $e');
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
    } else {
      await _responderConvocacao(evento, false);
    }
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

  Future<void> _fazerCheckIn(Map<String, dynamic> evento) async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) {
        _showError('Usuário não autenticado');
        return;
      }

      double? eventLat = (evento['latitude'] as num?)?.toDouble();
      double? eventLng = (evento['longitude'] as num?)?.toDouble();

      if (eventLat == null || eventLng == null) {
        final cep = (evento['cep'] ?? '').toString().trim();
        if (cep.isNotEmpty) {
          try {
            final geocoded = await _geocodeCep(cep);
            eventLat = geocoded['lat'];
            eventLng = geocoded['lng'];
          } catch (_) {}
        }
      }

      if (eventLat == null || eventLng == null) {
        _showError(
          'Evento sem coordenadas. O administrador precisa geocodificar o endereço.',
        );
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

      _showSuccess('Obtendo sua localização...');

      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        forceAndroidLocationManager: true,
        timeLimit: const Duration(seconds: 15),
      );

      final distancia = _calcularDistanciaMetros(
        pos.latitude,
        pos.longitude,
        eventLat,
        eventLng,
      );

      const raioMaximo = 200.0;
      if (distancia > raioMaximo) {
        _showError(
          'Você está muito longe do local. Distância: ${distancia.toStringAsFixed(0)}m. Máximo permitido: ${raioMaximo.toStringAsFixed(0)}m.',
        );
        return;
      }

      final res = await _supabase.rpc('do_checkin', params: {
        'p_event_id': evento['id'],
        'p_event_lat': eventLat,
        'p_event_lng': eventLng,
        'p_check_lat': pos.latitude,
        'p_check_lng': pos.longitude,
      });

      final ok = res?['ok'] == true;
      final st = (res?['status'] ?? '').toString();

      if (!mounted) return;

      if (ok) {
        await _sincronizarCheckInStatus(evento['id'].toString(), user.id);
        setState(() {
          evento['check_in_status'] = 'realizado';
        });
        _showSuccess('Check-in confirmado com sucesso!');
        await _buscarTreinosDoTecnico();
      } else {
        _showError('Check-in não permitido: $st');
      }
    } catch (e) {
      if (!mounted) return;
      _showError('Erro no check-in: $e');
    }
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
    final seenValues = <dynamic>{};
    final safeItems = <DropdownMenuItem<dynamic>>[];

    for (final item in items) {
      final itemValue = item.value;
      if (itemValue == null) continue;
      if (seenValues.add(itemValue)) {
        safeItems.add(item);
      }
    }

    final valueMatches = value == null
        ? 0
        : safeItems.where((item) => item.value == value).length;
    final safeValue = valueMatches == 1 ? value : null;

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
                value: safeValue,
                hint: Text(
                  hint,
                  style: TextStyle(color: Colors.grey[600], fontSize: 13),
                ),
                isExpanded: true,
                items: safeItems,
                onChanged: safeItems.isEmpty ? null : onChanged,
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

  Widget _buildResumoStatusChip({
    required String status,
    required String label,
    required int count,
    required Color color,
  }) {
    final selected = _filtroStatus == status;

    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => _selecionarResumo(status),
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

  Widget _buildTipoEventoChip({
    required String tipo,
    required String label,
    required int count,
    required Color color,
    required IconData icon,
  }) {
    final selected = _filtroTipoEvento == tipo;

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => _selecionarTipoEvento(tipo),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        constraints: const BoxConstraints(minWidth: 104),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? color.withOpacity(0.18) : color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? color : color.withOpacity(0.24),
            width: selected ? 1.4 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 16),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                '$label: $count',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: color,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResumoTreinosSection() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.96),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.blue.withOpacity(0.22)),
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
                    color: Colors.blue.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.fitness_center,
                    color: Colors.blue,
                    size: 15,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.lockTipoEvento
                        ? '${_labelTipoEvento(_filtroTipoEvento)}'
                        : 'Eventos separados',
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
            if (widget.lockTipoEvento)
              _buildTipoEventoChip(
                tipo: _filtroTipoEvento,
                label: _labelTipoEvento(_filtroTipoEvento),
                count: _typeCounts[_filtroTipoEvento] ?? 0,
                color: _colorTipoEvento(_filtroTipoEvento),
                icon: _iconTipoEvento(_filtroTipoEvento),
              )
            else
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  _buildTipoEventoChip(
                    tipo: 'treino',
                    label: 'Treinos',
                    count: _typeCounts['treino'] ?? 0,
                    color: Colors.blue,
                    icon: Icons.fitness_center,
                  ),
                  _buildTipoEventoChip(
                    tipo: 'campeonato',
                    label: 'Campeonatos',
                    count: _typeCounts['campeonato'] ?? 0,
                    color: olympusGold,
                    icon: Icons.emoji_events_rounded,
                  ),
                  _buildTipoEventoChip(
                    tipo: 'liga',
                    label: 'Liga',
                    count: _typeCounts['liga'] ?? 0,
                    color: olympusPurple,
                    icon: Icons.workspace_premium_rounded,
                  ),
                ],
              ),
            const SizedBox(height: 10),
            Text(
              'Status em ${_labelTipoEvento(_filtroTipoEvento)}',
              style: const TextStyle(
                color: olympusMuted,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _buildResumoStatusChip(
                  status: 'accepted',
                  label: 'Aceitou',
                  count: _statusCounts['accepted'] ?? 0,
                  color: olympusSuccess,
                ),
                _buildResumoStatusChip(
                  status: 'rejected',
                  label: 'Recusou',
                  count: _statusCounts['rejected'] ?? 0,
                  color: olympusDanger,
                ),
                _buildResumoStatusChip(
                  status: 'pending',
                  label: 'Pendentes',
                  count: _statusCounts['pending'] ?? 0,
                  color: olympusWarning,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFiltersAndSummary() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [olympusBlue, olympusLightBlue],
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
                        color: _filtroMes == mes ? olympusBlue : Colors.black,
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
          ),
        ),
        _buildResumoTreinosSection(),
      ],
    );
  }

  void _abrirDetalheTreino(Map<String, dynamic> treino) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CoachTrainingPlanDetailPage(treino: treino),
      ),
    );
  }

  void _abrirAvaliacaoRapida(Map<String, dynamic> treino) {
    final tipoEvento = _normalizarTipoEvento(
      treino['normalized_event_type'] ?? treino['event_type'],
    );

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => tipoEvento == 'campeonato'
            ? championship_scout.CoachChampionshipScoutEvaluationPage(
                treino: treino)
            : CoachQuickAthleteEvaluationPage(treino: treino),
      ),
    );
  }

  Widget _buildTreinoCard(Map<String, dynamic> treino) {
    final isMobile = _isMobile(context);
    final tipoEvento = _normalizarTipoEvento(
      treino['normalized_event_type'] ?? treino['event_type'],
    );
    final tipoLabel = _labelTipoEvento(tipoEvento);
    final tipoColor = _colorTipoEvento(tipoEvento);
    final tipoIcon = _iconTipoEvento(tipoEvento);
    final genero = (treino['gender'] ?? '').toString();
    final endereco = _formatarEndereco(treino);
    final status =
        (treino['convocation_status'] ?? 'pending').toString().toLowerCase();
    final allowCheckin = treino['allow_checkin'] == true;
    final podeEditar = _podeEditar(treino);
    final prazoInfo = _getPrazoInfo(treino);
    final janelaCheckIn = _verificarJanelaCheckIn(treino);
    final jaFezCheckin = _isCheckInRealizado(treino['check_in_status']);
    final canFazerCheckIn = status == 'accepted' &&
        allowCheckin &&
        janelaCheckIn['disponivel'] == true &&
        !jaFezCheckin;
    final justification = (treino['justification'] ?? '').toString().trim();

    Color statusColor;
    String statusLabel;

    switch (status) {
      case 'accepted':
        statusColor = olympusSuccess;
        statusLabel = 'Aceitou';
        break;
      case 'rejected':
        statusColor = olympusDanger;
        statusLabel = 'Recusou';
        break;
      default:
        statusColor = olympusWarning;
        statusLabel = 'Pendente';
    }

    return Container(
      margin:
          EdgeInsets.fromLTRB(isMobile ? 12 : 16, 0, isMobile ? 12 : 16, 12),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: EdgeInsets.all(isMobile ? 14 : 16),
          decoration: BoxDecoration(
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: tipoColor.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(tipoIcon, color: tipoColor, size: 13),
                        const SizedBox(width: 5),
                        Text(
                          tipoLabel.toUpperCase(),
                          style: TextStyle(
                            color: tipoColor,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  Flexible(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: statusColor.withOpacity(0.10),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        statusLabel,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: statusColor,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                (treino['event_name'] ?? 'Treino').toString(),
                style: TextStyle(
                  color: olympusText,
                  fontSize: isMobile ? 16 : 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _formatarDataHora(treino),
                style: TextStyle(
                  color: olympusMuted,
                  fontSize: isMobile ? 12 : 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (endereco.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  endereco,
                  style: TextStyle(
                    color: olympusSubtle,
                    fontSize: isMobile ? 12 : 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              if (genero.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  'Categoria/Gênero: $genero',
                  style: TextStyle(
                    color: olympusSubtle,
                    fontSize: isMobile ? 12 : 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              if (prazoInfo.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  prazoInfo,
                  style: TextStyle(
                    fontSize: isMobile ? 10 : 11,
                    color: Colors.red[700],
                    fontStyle: FontStyle.italic,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              if (justification.isNotEmpty && status == 'rejected') ...[
                const SizedBox(height: 8),
                Text(
                  'Justificativa: $justification',
                  style: TextStyle(
                    fontSize: isMobile ? 11 : 12,
                    color: Colors.red[700],
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              const SizedBox(height: 14),
              if (status == 'pending' && podeEditar) ...[
                _responsiveActionRow(
                  children: [
                    ElevatedButton.icon(
                      onPressed: podeEditar
                          ? () => _responderConvocacao(treino, false)
                          : null,
                      icon: const Icon(Icons.close, size: 16),
                      label: const Text('Recusar'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor:
                            podeEditar ? olympusDanger : Colors.grey,
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.symmetric(
                          vertical: isMobile ? 11 : 12,
                        ),
                      ),
                    ),
                    ElevatedButton.icon(
                      onPressed: podeEditar
                          ? () => _responderConvocacao(treino, true)
                          : null,
                      icon: const Icon(Icons.check, size: 16),
                      label: const Text('Aceitar'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor:
                            podeEditar ? olympusSuccess : Colors.grey,
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.symmetric(
                          vertical: isMobile ? 11 : 12,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
              ],
              if (status != 'pending' && podeEditar) ...[
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () => _editarResposta(treino),
                    icon: const Icon(Icons.edit, size: 16),
                    label: const Text('Editar resposta'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: olympusPurple,
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.symmetric(
                        vertical: isMobile ? 11 : 12,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
              ],
              if (jaFezCheckin) ...[
                Container(
                  width: double.infinity,
                  padding: EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: isMobile ? 10 : 12,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.green.withOpacity(0.25)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.verified,
                          color: olympusSuccess, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Check-in realizado',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: isMobile ? 11 : 12,
                            color: olympusSuccess,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ] else if (canFazerCheckIn) ...[
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () => _fazerCheckIn(treino),
                    icon: const Icon(Icons.my_location, size: 16),
                    label: const Text('Fazer Check-in'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: olympusSuccess,
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.symmetric(
                        vertical: isMobile ? 11 : 12,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.red[50],
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.red[200]!),
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
                          'Raio 200m | 10min antes até 30min após',
                          style: TextStyle(
                            fontSize: isMobile ? 9.5 : 10,
                            color: Colors.red[900],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => _abrirAvaliacaoRapida(treino),
                  icon: Icon(
                    tipoEvento == 'campeonato'
                        ? Icons.analytics_outlined
                        : Icons.fact_check_outlined,
                  ),
                  label: Text(
                    tipoEvento == 'campeonato'
                        ? 'Avaliar Campeonato (Scout)'
                        : 'Avaliação rápida de $tipoLabel',
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: tipoEvento == 'campeonato'
                        ? olympusGold
                        : olympusPurple,
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(
                      vertical: isMobile ? 11 : 12,
                    ),
                  ),
                ),
              ),
              if (tipoEvento == 'treino') ...[
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () => _abrirDetalheTreino(treino),
                    icon: const Icon(Icons.menu_book_outlined),
                    label: const Text('Abrir planejamento'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: olympusBlue,
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.symmetric(
                        vertical: isMobile ? 11 : 12,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: olympusBg,
      appBar: AppBar(
        title: Text(
          widget.lockTipoEvento
              ? 'Avaliar ${_labelTipoEvento(_filtroTipoEvento)}'
              : 'Eventos e avaliações',
        ),
        backgroundColor: olympusBlue,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            onPressed: _buscarTreinosDoTecnico,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          _buildFiltersAndSummary(),
          Expanded(
            child: _loading
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
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      )
                    : _treinosFiltrados.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Text(
                                widget.lockTipoEvento
                                    ? 'Nenhum ${_labelTipoEvento(_filtroTipoEvento).toLowerCase()} encontrado para os filtros atuais.'
                                    : 'Nenhum evento encontrado para os filtros atuais.',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Color(0xFF53657B),
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          )
                        : RefreshIndicator(
                            onRefresh: _buscarTreinosDoTecnico,
                            child: ListView.builder(
                              padding: const EdgeInsets.only(bottom: 24),
                              itemCount: _treinosFiltrados.length,
                              itemBuilder: (context, index) {
                                return _buildTreinoCard(
                                  _treinosFiltrados[index],
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

class CoachTrainingPlanDetailPage extends StatefulWidget {
  const CoachTrainingPlanDetailPage({
    super.key,
    required this.treino,
  });

  final Map<String, dynamic> treino;

  @override
  State<CoachTrainingPlanDetailPage> createState() =>
      _CoachTrainingPlanDetailPageState();
}

class _CoachTrainingPlanDetailPageState
    extends State<CoachTrainingPlanDetailPage> {
  final SupabaseClient _supabase = Supabase.instance.client;

  static const Color olympusBlue = Color(0xFF1E3A5F);
  static const Color olympusGold = Color(0xFFD4AF37);
  static const Color olympusBg = Color(0xFFF4F7FB);
  static const Color olympusCard = Colors.white;
  static const Color olympusText = Color(0xFF17324D);
  static const Color olympusMuted = Color(0xFF53657B);
  static const Color olympusSubtle = Color(0xFF6A7E94);
  static const Color olympusBorder = Color(0xFFE4EDF5);
  static const Color olympusDanger = Color(0xFFDC2626);
  static const Color olympusSuccess = Color(0xFF16A34A);

  final TextEditingController _observacoesController = TextEditingController();

  final Map<String, List<String>> _opcoesPorCategoria = const {
    'Fundamentos': [
      'Aquecimento',
      'Saque',
      'Recepção',
      'Toque',
      'Ataque',
      'Bloqueio',
      'Defesa',
      'Levantamento',
      'Passe',
    ],
    'Tático': [
      'Sistema defensivo',
      'Sistema ofensivo',
      'Transição',
      'Cobertura',
      'Posicionamento',
      'Rodízio',
      'Leitura de jogo',
      'Simulação de jogo',
    ],
    'Físico': [
      'Mobilidade',
      'Agilidade',
      'Velocidade',
      'Força',
      'Potência',
      'Resistência',
      'Core',
      'Prevenção',
    ],
  };

  late List<Map<String, dynamic>> _blocos;
  bool _loadingPlan = true;
  bool _savingPlan = false;

  String get _eventId => (widget.treino['id'] ?? '').toString();

  @override
  void initState() {
    super.initState();

    final inicio = _getHorarioInicialTreino();
    _blocos = [
      {
        'id': null,
        'categoria': '',
        'tipo': '',
        'inicio': inicio,
        'fim': _calcularHorarioFimPadrao(inicio),
        'observacao': '',
      },
    ];

    _carregarPlanejamentoDoSupabase();
  }

  @override
  void dispose() {
    _observacoesController.dispose();
    super.dispose();
  }

  bool _isMobile(BuildContext context) {
    return MediaQuery.of(context).size.width < 600;
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: olympusDanger,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showSuccess(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: olympusSuccess,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

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

  DateTime? _parseHorario(String value) {
    final clean = _normalizarHorario(value);
    final parts = clean.split(':');
    if (parts.length != 2) return null;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return null;
    return DateTime(2000, 1, 1, hour, minute);
  }

  String _formatHorario(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  String _normalizarHorario(dynamic value) {
    final raw = (value ?? '').toString().trim();
    if (raw.isEmpty) return '';

    final parts = raw.split(':');
    if (parts.length >= 2) {
      final h = int.tryParse(parts[0]);
      final m = int.tryParse(parts[1]);

      if (h != null && m != null) {
        return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
      }
    }

    return raw;
  }

  String _getHorarioInicialTreino() {
    return _normalizarHorario(widget.treino['event_time']);
  }

  String _calcularHorarioFimPadrao(String inicio) {
    final parsed = _parseHorario(inicio);
    if (parsed == null) return '';
    return _formatHorario(parsed.add(const Duration(minutes: 10)));
  }

  Map<String, dynamic> _blocoVazioPadrao() {
    final inicio = _getHorarioInicialTreino();

    return {
      'id': null,
      'categoria': '',
      'tipo': '',
      'inicio': inicio,
      'fim': _calcularHorarioFimPadrao(inicio),
      'observacao': '',
    };
  }

  Map<String, dynamic> _mapBlocoFromDb(Map<String, dynamic> row) {
    return {
      'id': row['id'],
      'categoria': (row['category'] ?? '').toString(),
      'tipo': (row['type'] ?? '').toString(),
      'inicio': _normalizarHorario(row['start_time']),
      'fim': _normalizarHorario(row['end_time']),
      'observacao': (row['observation'] ?? '').toString(),
    };
  }

  Future<void> _carregarPlanejamentoDoSupabase() async {
    setState(() {
      _loadingPlan = true;
    });

    try {
      final user = _supabase.auth.currentUser;
      if (user == null) {
        throw Exception('Usuário não autenticado.');
      }

      if (_eventId.isEmpty) {
        throw Exception('Evento inválido.');
      }

      final blocosResponse = await _supabase
          .from('training_plan_blocks')
          .select(
              'id, category, type, start_time, end_time, observation, position')
          .eq('event_id', _eventId)
          .eq('coach_id', user.id)
          .order('position', ascending: true);

      final blocosRows =
          List<Map<String, dynamic>>.from(blocosResponse as List);

      final notesResponse = await _supabase
          .from('training_plan_notes')
          .select('notes')
          .eq('event_id', _eventId)
          .eq('coach_id', user.id)
          .maybeSingle();

      if (!mounted) return;

      setState(() {
        if (blocosRows.isEmpty) {
          _blocos = [_blocoVazioPadrao()];
        } else {
          _blocos = blocosRows.map(_mapBlocoFromDb).toList();
        }

        if (notesResponse != null) {
          _observacoesController.text =
              (notesResponse['notes'] ?? '').toString();
        }

        _loadingPlan = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingPlan = false;
      });
      _showError('Erro ao carregar planejamento: $e');
    }
  }

  bool _blocoEstaCompleto(Map<String, dynamic> bloco) {
    return (bloco['categoria'] ?? '').toString().trim().isNotEmpty &&
        (bloco['tipo'] ?? '').toString().trim().isNotEmpty &&
        (bloco['inicio'] ?? '').toString().trim().isNotEmpty &&
        (bloco['fim'] ?? '').toString().trim().isNotEmpty;
  }

  bool get _podeAdicionarNovoBloco {
    if (_blocos.isEmpty) return true;
    return _blocoEstaCompleto(_blocos.last);
  }

  String _proximoHorarioInicial() {
    if (_blocos.isEmpty) return _getHorarioInicialTreino();
    final ultimoFim = (_blocos.last['fim'] ?? '').toString().trim();
    final parsed = _parseHorario(ultimoFim);
    if (parsed == null) return _getHorarioInicialTreino();
    return _formatHorario(parsed.add(const Duration(minutes: 1)));
  }

  Future<String?> _selecionarHorario(String valorInicial) async {
    final initialParsed = _parseHorario(valorInicial);
    final picked = await showTimePicker(
      context: context,
      initialTime: initialParsed != null
          ? TimeOfDay(hour: initialParsed.hour, minute: initialParsed.minute)
          : TimeOfDay.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: olympusBlue,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked == null) return null;
    final dt = DateTime(2000, 1, 1, picked.hour, picked.minute);
    return _formatHorario(dt);
  }

  Future<void> _salvarNotasNoSupabase() async {
    final user = _supabase.auth.currentUser;
    if (user == null) {
      throw Exception('Usuário não autenticado.');
    }

    await _supabase.from('training_plan_notes').upsert(
      {
        'event_id': _eventId,
        'coach_id': user.id,
        'notes': _observacoesController.text.trim(),
        'updated_at': DateTime.now().toIso8601String(),
      },
      onConflict: 'event_id,coach_id',
    );
  }

  Future<void> _salvarBlocoNoSupabase(int index) async {
    final user = _supabase.auth.currentUser;
    if (user == null) {
      throw Exception('Usuário não autenticado.');
    }

    if (_eventId.isEmpty) {
      throw Exception('Evento inválido.');
    }

    final bloco = _blocos[index];

    if (!_blocoEstaCompleto(bloco)) {
      return;
    }

    final payload = {
      'event_id': _eventId,
      'coach_id': user.id,
      'category': (bloco['categoria'] ?? '').toString().trim(),
      'type': (bloco['tipo'] ?? '').toString().trim(),
      'start_time': _normalizarHorario(bloco['inicio']),
      'end_time': _normalizarHorario(bloco['fim']),
      'observation': (bloco['observacao'] ?? '').toString().trim(),
      'position': index,
      'updated_at': DateTime.now().toIso8601String(),
    };

    final blocoId = (bloco['id'] ?? '').toString();

    if (blocoId.isEmpty || blocoId == 'null') {
      final inserted = await _supabase
          .from('training_plan_blocks')
          .insert(payload)
          .select('id')
          .single();

      if (!mounted) return;

      setState(() {
        _blocos[index]['id'] = inserted['id'];
      });
    } else {
      await _supabase
          .from('training_plan_blocks')
          .update(payload)
          .eq('id', blocoId);
    }
  }

  Future<void> _reordenarBlocosNoSupabase() async {
    for (int i = 0; i < _blocos.length; i++) {
      final blocoId = (_blocos[i]['id'] ?? '').toString();
      if (blocoId.isEmpty || blocoId == 'null') continue;

      await _supabase.from('training_plan_blocks').update({
        'position': i,
        'updated_at': DateTime.now().toIso8601String()
      }).eq('id', blocoId);
    }
  }

  Future<void> _removerBlocoDoSupabase(Map<String, dynamic> bloco) async {
    final blocoId = (bloco['id'] ?? '').toString();
    if (blocoId.isEmpty || blocoId == 'null') return;

    await _supabase.from('training_plan_blocks').delete().eq('id', blocoId);
  }

  Future<void> _adicionarBloco() async {
    if (!_podeAdicionarNovoBloco) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Preencha o bloco atual antes de habilitar o próximo.',
          ),
        ),
      );
      return;
    }

    final horarioInicial = _blocos.length == 1 &&
            (_blocos.first['inicio'] ?? '').toString().trim().isEmpty
        ? _getHorarioInicialTreino()
        : _proximoHorarioInicial();

    final novoBloco = {
      'id': null,
      'categoria': '',
      'tipo': '',
      'inicio': horarioInicial,
      'fim': _calcularHorarioFimPadrao(horarioInicial),
      'observacao': '',
    };

    setState(() {
      _blocos.add(novoBloco);
    });

    await _editarBloco(_blocos.length - 1);
  }

  Future<void> _editarBloco(int index) async {
    final bloco = Map<String, dynamic>.from(_blocos[index]);
    String categoriaSelecionada =
        (bloco['categoria'] ?? '').toString().trim().isEmpty
            ? 'Fundamentos'
            : (bloco['categoria'] ?? 'Fundamentos').toString();
    String tipoSelecionado = (bloco['tipo'] ?? '').toString();

    String horarioInicio = index == 0
        ? ((bloco['inicio'] ?? '').toString().trim().isNotEmpty
            ? _normalizarHorario(bloco['inicio'])
            : _getHorarioInicialTreino())
        : ((bloco['inicio'] ?? '').toString().trim().isNotEmpty
            ? _normalizarHorario(bloco['inicio'])
            : _proximoHorarioInicial());

    String horarioFim = (bloco['fim'] ?? '').toString().trim().isNotEmpty
        ? _normalizarHorario(bloco['fim'])
        : _calcularHorarioFimPadrao(horarioInicio);

    final observacaoController =
        TextEditingController(text: (bloco['observacao'] ?? '').toString());

    final salvo = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final opcoesTipos =
                _opcoesPorCategoria[categoriaSelecionada] ?? const <String>[];

            if (!opcoesTipos.contains(tipoSelecionado) &&
                opcoesTipos.isNotEmpty) {
              tipoSelecionado = opcoesTipos.first;
            }

            if (horarioFim.trim().isEmpty && horarioInicio.trim().isNotEmpty) {
              horarioFim = _calcularHorarioFimPadrao(horarioInicio);
            }

            Widget buildCategoriaChip(String categoria) {
              final selected = categoriaSelecionada == categoria;
              return ChoiceChip(
                label: Text(categoria),
                selected: selected,
                onSelected: (_) {
                  setModalState(() {
                    categoriaSelecionada = categoria;
                    tipoSelecionado = _opcoesPorCategoria[categoria]!.first;
                  });
                },
                selectedColor: const Color(0xFFD4AF37),
                backgroundColor: Colors.white,
                labelStyle: TextStyle(
                  color: selected ? olympusBlue : olympusMuted,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
                side: BorderSide(
                  color: selected ? const Color(0xFFD4AF37) : olympusBorder,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(999),
                ),
              );
            }

            Widget buildTipoChip(String tipo) {
              final selected = tipoSelecionado == tipo;
              return ChoiceChip(
                label: Text(tipo),
                selected: selected,
                onSelected: (_) {
                  setModalState(() {
                    tipoSelecionado = tipo;
                  });
                },
                selectedColor: olympusBlue,
                backgroundColor: Colors.white,
                labelStyle: TextStyle(
                  color: selected ? Colors.white : olympusMuted,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
                side: BorderSide(
                  color: selected ? olympusBlue : olympusBorder,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(999),
                ),
              );
            }

            Widget buildHorarioBox({
              required String label,
              required String valor,
              required VoidCallback onTap,
            }) {
              return Expanded(
                child: InkWell(
                  onTap: onTap,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFD6DEE8)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          label,
                          style: const TextStyle(
                            color: Color(0xFF53657B),
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            const Icon(
                              Icons.access_time_rounded,
                              size: 16,
                              color: olympusBlue,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              valor.isEmpty ? '--:--' : valor,
                              style: const TextStyle(
                                color: olympusBlue,
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }

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
                          'Bloco ${index + 1}',
                          style: const TextStyle(
                            color: olympusBlue,
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Tipo de treino',
                          style: TextStyle(
                            color: olympusBlue,
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            buildCategoriaChip('Fundamentos'),
                            buildCategoriaChip('Tático'),
                            buildCategoriaChip('Físico'),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          categoriaSelecionada == 'Fundamentos'
                              ? 'Selecione o fundamento'
                              : categoriaSelecionada == 'Tático'
                                  ? 'Selecione a opção tática'
                                  : 'Selecione a opção física',
                          style: const TextStyle(
                            color: olympusBlue,
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: opcoesTipos
                              .map((tipo) => buildTipoChip(tipo))
                              .toList(),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            buildHorarioBox(
                              label: 'Horário início',
                              valor: horarioInicio,
                              onTap: () async {
                                final escolhido =
                                    await _selecionarHorario(horarioInicio);
                                if (escolhido != null) {
                                  setModalState(() {
                                    horarioInicio = escolhido;
                                    horarioFim =
                                        _calcularHorarioFimPadrao(escolhido);
                                  });
                                }
                              },
                            ),
                            const SizedBox(width: 10),
                            buildHorarioBox(
                              label: 'Horário fim',
                              valor: horarioFim,
                              onTap: () async {
                                final escolhido =
                                    await _selecionarHorario(horarioFim);
                                if (escolhido != null) {
                                  setModalState(() {
                                    horarioFim = escolhido;
                                  });
                                }
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: observacaoController,
                          maxLines: 3,
                          decoration: const InputDecoration(
                            labelText: 'Observação',
                            hintText: 'Detalhes do bloco',
                          ),
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _savingPlan
                                ? null
                                : () async {
                                    if (tipoSelecionado.trim().isEmpty ||
                                        horarioInicio.trim().isEmpty ||
                                        horarioFim.trim().isEmpty) {
                                      return;
                                    }

                                    final inicioParsed =
                                        _parseHorario(horarioInicio);
                                    final fimParsed = _parseHorario(horarioFim);

                                    if (inicioParsed == null ||
                                        fimParsed == null ||
                                        !fimParsed.isAfter(inicioParsed)) {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            'O horário final precisa ser maior que o horário inicial.',
                                          ),
                                        ),
                                      );
                                      return;
                                    }

                                    setState(() {
                                      _savingPlan = true;
                                      _blocos[index] = {
                                        'id': bloco['id'],
                                        'categoria': categoriaSelecionada,
                                        'tipo': tipoSelecionado,
                                        'inicio': horarioInicio.trim(),
                                        'fim': horarioFim.trim(),
                                        'observacao':
                                            observacaoController.text.trim(),
                                      };
                                    });

                                    try {
                                      await _salvarBlocoNoSupabase(index);

                                      if (context.mounted) {
                                        Navigator.pop(context, true);
                                      }
                                    } catch (e) {
                                      if (mounted) {
                                        _showError(
                                          'Erro ao salvar bloco no Supabase: $e',
                                        );
                                      }
                                    } finally {
                                      if (mounted) {
                                        setState(() {
                                          _savingPlan = false;
                                        });
                                      }
                                    }
                                  },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: olympusBlue,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                            child: _savingPlan
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        Colors.white,
                                      ),
                                    ),
                                  )
                                : const Text('Salvar bloco'),
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

    observacaoController.dispose();

    if (salvo == true && mounted) {
      _showSuccess('Bloco salvo no Supabase');
    }
  }

  Future<void> _removerBloco(int index) async {
    final blocoRemovido = Map<String, dynamic>.from(_blocos[index]);

    try {
      await _removerBlocoDoSupabase(blocoRemovido);

      setState(() {
        if (_blocos.length == 1) {
          _blocos[0] = _blocoVazioPadrao();
        } else {
          _blocos.removeAt(index);
        }
      });

      await _reordenarBlocosNoSupabase();

      if (mounted) {
        _showSuccess('Bloco removido');
      }
    } catch (e) {
      _showError('Erro ao remover bloco: $e');
    }
  }

  Future<void> _salvarPlanejamento() async {
    setState(() {
      _savingPlan = true;
    });

    try {
      for (int i = 0; i < _blocos.length; i++) {
        if (_blocoEstaCompleto(_blocos[i])) {
          await _salvarBlocoNoSupabase(i);
        }
      }

      await _salvarNotasNoSupabase();

      if (!mounted) return;
      _showSuccess('Planejamento salvo no Supabase');
    } catch (e) {
      if (!mounted) return;
      _showError('Erro ao salvar planejamento: $e');
    } finally {
      if (mounted) {
        setState(() {
          _savingPlan = false;
        });
      }
    }
  }

  Widget _buildBlocoCard(int index, bool isMobile) {
    final bloco = _blocos[index];
    final categoria = (bloco['categoria'] ?? '').toString();
    final tipo = (bloco['tipo'] ?? '').toString();
    final inicio =
        ((bloco['inicio'] ?? '').toString().trim().isEmpty && index == 0)
            ? _getHorarioInicialTreino()
            : _normalizarHorario(bloco['inicio']);
    final fim = (bloco['fim'] ?? '').toString().trim().isEmpty
        ? _calcularHorarioFimPadrao(inicio)
        : _normalizarHorario(bloco['fim']);
    final observacao = (bloco['observacao'] ?? '').toString();

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: EdgeInsets.all(isMobile ? 12 : 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: olympusBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: isMobile ? 34 : 38,
                height: isMobile ? 34 : 38,
                decoration: BoxDecoration(
                  color: olympusBlue.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Center(
                  child: Text(
                    '${index + 1}',
                    style: const TextStyle(
                      color: olympusBlue,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  tipo.isEmpty ? 'Bloco ${index + 1}' : tipo,
                  style: TextStyle(
                    color: olympusBlue,
                    fontSize: isMobile ? 14 : 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              IconButton(
                onPressed: _savingPlan ? null : () => _editarBloco(index),
                icon: const Icon(Icons.edit_outlined),
                color: olympusBlue,
                tooltip: 'Editar',
              ),
              IconButton(
                onPressed: _savingPlan ? null : () => _removerBloco(index),
                icon: const Icon(Icons.delete_outline),
                color: olympusDanger,
                tooltip: 'Remover',
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (categoria.trim().isNotEmpty)
            Text(
              categoria,
              style: TextStyle(
                color: olympusMuted,
                fontSize: isMobile ? 11 : 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          const SizedBox(height: 4),
          Text(
            '${inicio.isEmpty ? '--:--' : inicio} às ${fim.isEmpty ? '--:--' : fim}',
            style: TextStyle(
              color: olympusMuted,
              fontSize: isMobile ? 12 : 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (observacao.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              observacao,
              style: TextStyle(
                color: olympusSubtle,
                fontSize: isMobile ? 12 : 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = _isMobile(context);

    return Scaffold(
      backgroundColor: olympusBg,
      appBar: AppBar(
        title: const Text('Planejamento do treino'),
        backgroundColor: olympusBlue,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            onPressed: _loadingPlan || _savingPlan ? null : _salvarPlanejamento,
            icon: _savingPlan
                ? const SizedBox(
                    width: 19,
                    height: 19,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : const Icon(Icons.save_outlined),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _loadingPlan || _savingPlan ? null : _adicionarBloco,
        backgroundColor: olympusBlue,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Novo bloco'),
      ),
      body: _loadingPlan
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _carregarPlanejamentoDoSupabase,
              child: ListView(
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
                        if ((widget.treino['gender'] ?? '')
                            .toString()
                            .trim()
                            .isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            'Categoria/Gênero: ${(widget.treino['gender'] ?? '').toString()}',
                            style: TextStyle(
                              color: olympusMuted,
                              fontSize: isMobile ? 12 : 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
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
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Planejamento por blocos',
                          style: TextStyle(
                            color: olympusBlue,
                            fontSize: isMobile ? 15 : 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Cada bloco é salvo no Supabase ao tocar em Salvar bloco.',
                          style: TextStyle(
                            color: olympusMuted,
                            fontSize: isMobile ? 12 : 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 12),
                        ...List.generate(
                          _blocos.length,
                          (index) => _buildBlocoCard(index, isMobile),
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
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Observações do treino',
                          style: TextStyle(
                            color: olympusBlue,
                            fontSize: isMobile ? 15 : 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _observacoesController,
                          maxLines: 4,
                          decoration: const InputDecoration(
                            hintText:
                                'Ex: foco em regularidade de passe e tomada de decisão.',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: _savingPlan ? null : _salvarPlanejamento,
                            icon: const Icon(Icons.save_outlined),
                            label: const Text('Salvar observações e blocos'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: olympusBlue,
                              side: const BorderSide(color: olympusBlue),
                              padding: const EdgeInsets.symmetric(vertical: 13),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 80),
                ],
              ),
            ),
    );
  }
}

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
