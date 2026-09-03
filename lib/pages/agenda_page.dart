import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../pages/add_event_page.dart';
import '../services/permission_service.dart'; // ✅ NOVO
import '../services/role_service.dart';
import '../services/olympus_memory_cache.dart';
import '../theme/olympus_theme.dart';
import '../widgets/event_address_link.dart';

class AgendaPage extends StatefulWidget {
  const AgendaPage({Key? key}) : super(key: key);

  @override
  State<AgendaPage> createState() => _AgendaPageState();
}

class _AgendaPageState extends State<AgendaPage> {
  final SupabaseClient _supabase = Supabase.instance.client;
  final PermissionService _permissionService = PermissionService(); // ✅ NOVO
  final RoleService _roleService = RoleService();

  // ✅ NOVO: Variáveis de controle de permissão
  bool _hasPermission = true;
  bool _checkingPermission = true;
  bool _isAdmin = false; // ✅ NOVO: controla ações exclusivas de admin
  RealtimeChannel? _eventsRealtimeChannel;
  Map<String, bool> _agendaActionPermissions = const {
    'edit_event': true,
    'insert_score': true,
    'view_called_up': true,
    'export_game_data': true,
    'delete_event': true,
  };

  List<Map<String, dynamic>> _eventos = [];
  List<Map<String, dynamic>> _eventosFiltrados = [];
  Map<String, Map<String, int>> _quantidadeConvocados =
      {}; // {eventId: {'athletes': n, 'technicians': n}}
  Map<String, Map<String, int>> _checkinInfo =
      {}; // {eventId: {'checked_in': n, 'pending': n}}
  // ✅ NOVO (cirúrgico): cache da view event_convocation_stats
  // {eventId: {'total_convocados': n, 'total_aceitos': n, 'total_pendentes': n, 'total_recusados': n}}
  Map<String, Map<String, int>> _convocationStats = {};
  final Map<String, List<Map<String, dynamic>>> _convocadosDetailsCache = {};
  final Map<String, DateTime> _convocadosDetailsCacheTime = {};
  static const Duration _convocadosDetailsCacheTtl = Duration(seconds: 45);
  static const int _eventQueryBatchSize = 100;
  bool _loading = true;
  bool _loadingEvents = false;
  bool _openingAgendaPage = false;
  static const int _eventPageSize = 30;
  int _visibleEventLimit = _eventPageSize;
  String? _error;
  String _filtroSelecionado = 'Todos';
  String _filtroMes = '';
  String _filtroGenero = 'Todos';
  bool _mostrarEventosPassados = false;
  Set<String> _placaresExpandidos = {}; // IDs dos placares expandidos
  // ✅ Cores do logo Olympus Voleibol

  @override
  void initState() {
    super.initState();
    _setMesAtual();
    _initializeAgenda();
  }

  Future<void> _initializeAgenda() async {
    await _checkPermission();
    if (!mounted || !_hasPermission) return;
    _restoreAgendaCache();
    await _buscarEventos();
    _listenForEventChanges();
  }

  String get _agendaCacheKey =>
      'agenda:${_supabase.auth.currentUser?.id ?? 'guest'}:${_isAdmin ? 'admin' : 'user'}';

  void _restoreAgendaCache() {
    final cached = OlympusMemoryCache.read<Map<String, dynamic>>(
      _agendaCacheKey,
    );
    if (cached == null) return;
    final events = List<Map<String, dynamic>>.from(
      (cached['events'] as List?) ?? const [],
    );
    if (events.isEmpty) return;

    Map<String, Map<String, int>> restoreIntMap(dynamic raw) {
      if (raw is! Map) return <String, Map<String, int>>{};
      final restored = <String, Map<String, int>>{};
      raw.forEach((key, value) {
        if (value is! Map) return;
        restored[key.toString()] = value.map<String, int>(
          (innerKey, innerValue) => MapEntry(
            innerKey.toString(),
            innerValue is num
                ? innerValue.toInt()
                : int.tryParse(innerValue.toString()) ?? 0,
          ),
        );
      });
      return restored;
    }

    setState(() {
      _eventos = events;
      _quantidadeConvocados = restoreIntMap(cached['called']);
      _checkinInfo = restoreIntMap(cached['checkin']);
      _convocationStats = restoreIntMap(cached['stats']);
      _loading = false;
    });
    _aplicarFiltros();
  }

  void _saveAgendaCache() {
    OlympusMemoryCache.write<Map<String, dynamic>>(_agendaCacheKey, {
      'events': List<Map<String, dynamic>>.from(_eventos),
      'called': Map<String, Map<String, int>>.from(_quantidadeConvocados),
      'checkin': Map<String, Map<String, int>>.from(_checkinInfo),
      'stats': Map<String, Map<String, int>>.from(_convocationStats),
    });
  }

  void _listenForEventChanges() {
    if (_eventsRealtimeChannel != null) return;
    _eventsRealtimeChannel = _supabase
        .channel('agenda_events_${_supabase.auth.currentUser?.id ?? 'guest'}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'events',
          callback: (_) => _buscarEventos(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'convocations',
          callback: (_) => _buscarEventos(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'checkins',
          callback: (_) => _buscarEventos(),
        )
        .subscribe();
  }

  Iterable<List<String>> _eventIdBatches(List<String> eventIds) sync* {
    for (var start = 0;
        start < eventIds.length;
        start += _eventQueryBatchSize) {
      final end = (start + _eventQueryBatchSize < eventIds.length)
          ? start + _eventQueryBatchSize
          : eventIds.length;
      yield eventIds.sublist(start, end);
    }
  }

  @override
  void dispose() {
    if (_eventsRealtimeChannel != null) {
      _supabase.removeChannel(_eventsRealtimeChannel!);
    }
    super.dispose();
  }

  // ✅ NOVO: Verifica se usuário tem permissão para acessar a Agenda
  Future<void> _checkPermission() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) {
        setState(() {
          _hasPermission = false;
          _checkingPermission = false;
          _isAdmin = false;
        });
        return;
      }

      // Busca o perfil do usuário
      final hasAdminRole = await _roleService.isCurrentUserAdmin();

      // Admins SEMPRE têm acesso
      if (hasAdminRole) {
        setState(() {
          _hasPermission = true;
          _checkingPermission = false;
          _isAdmin = true;
          _agendaActionPermissions = const {
            'edit_event': true,
            'insert_score': true,
            'view_called_up': true,
            'export_game_data': true,
            'delete_event': true,
          };
        });
        return;
      }

      // Verifica permissão na tabela page_permissions
      final hasAccess = await _permissionService.hasAccess(user.id, 'agenda');
      final actionPermissions =
          await _permissionService.getAgendaActionPermissions(user.id);

      setState(() {
        _hasPermission = hasAccess;
        _checkingPermission = false;
        _isAdmin = false;
        _agendaActionPermissions = actionPermissions;
      });
    } catch (e) {
      print('❌ Erro ao verificar permissão da Agenda: $e');
      // Em caso de erro, permite acesso (fail-safe)
      setState(() {
        _hasPermission = true;
        _checkingPermission = false;
        _isAdmin = false;
        _agendaActionPermissions = const {
          'edit_event': true,
          'insert_score': true,
          'view_called_up': true,
          'export_game_data': true,
          'delete_event': true,
        };
      });
    }
  }

  void _setMesAtual() {
    final now = DateTime.now();
    _filtroMes = '${now.month.toString().padLeft(2, '0')}/${now.year}';
  }

  bool _canUseAgendaAction(String actionKey) {
    return _agendaActionPermissions[actionKey] ?? true;
  }

  Future<void> _buscarEventos() async {
    if (_loadingEvents) return;
    _loadingEvents = true;
    setState(() {
      _loading = _eventos.isEmpty;
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
      var query = _supabase.from('events').select();
      if (!_isAdmin) {
        query = query.eq('user_id', user.id);
      }
      final response = await query
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
      _saveAgendaCache();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _eventos.isEmpty ? 'Erro ao buscar eventos: $e' : null;
        _loading = false;
      });
      if (_eventos.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Não foi possível atualizar. Dados anteriores mantidos.',
            ),
          ),
        );
      }
    } finally {
      _loadingEvents = false;
    }
  }

  // Totais dos cards consideram somente atletas. Integrantes da comissão
  // técnica continuam visíveis na lista, mas não alteram os indicadores.
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
      final map = <String, Map<String, int>>{
        for (final id in ids)
          id: {
            'total_convocados': 0,
            'total_aceitos': 0,
            'total_pendentes': 0,
            'total_recusados': 0,
          },
      };
      for (final batch in _eventIdBatches(ids)) {
        final resp = await _supabase
            .from('convocations')
            .select('event_id, status, event_role')
            .inFilter('event_id', batch);
        for (final row in resp) {
          final eventId = row['event_id']?.toString();
          if (eventId == null || !map.containsKey(eventId)) continue;
          final role =
              (row['event_role'] ?? 'athlete').toString().trim().toLowerCase();
          if (role == 'coach') continue;
          final status =
              (row['status'] ?? 'pending').toString().trim().toLowerCase();
          final data = map[eventId]!;
          data['total_convocados'] = (data['total_convocados'] ?? 0) + 1;
          if (status == 'accepted') {
            data['total_aceitos'] = (data['total_aceitos'] ?? 0) + 1;
          } else if (status == 'rejected') {
            data['total_recusados'] = (data['total_recusados'] ?? 0) + 1;
          } else {
            data['total_pendentes'] = (data['total_pendentes'] ?? 0) + 1;
          }
        }
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
      final eventIds = _eventos
          .map((evento) => (evento['id'] ?? '').toString())
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList();
      for (final eventId in eventIds) {
        quantidades[eventId] = {'athletes': 0, 'technicians': 0};
      }
      if (eventIds.isNotEmpty) {
        for (final batch in _eventIdBatches(eventIds)) {
          final response = await _supabase
              .from('convocations')
              .select('event_id, event_role')
              .inFilter('event_id', batch);
          for (final row in List<Map<String, dynamic>>.from(response as List)) {
            final eventId = (row['event_id'] ?? '').toString();
            if (!quantidades.containsKey(eventId)) continue;
            final role = (row['event_role'] ?? 'athlete').toString();
            final key = role == 'coach' ? 'technicians' : 'athletes';
            quantidades[eventId]![key] = (quantidades[eventId]![key] ?? 0) + 1;
          }
        }
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
      final eventIds = _eventos
          .where((evento) => evento['allow_checkin'] == true)
          .map((evento) => (evento['id'] ?? '').toString())
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList();
      final acceptedAthletesByEvent = <String, Set<String>>{};
      final checkedInByEvent = <String, int>{};
      if (eventIds.isNotEmpty) {
        for (final batch in _eventIdBatches(eventIds)) {
          final convocations = await _supabase
              .from('convocations')
              .select('event_id, user_id, status, event_role')
              .inFilter('event_id', batch);
          for (final row
              in List<Map<String, dynamic>>.from(convocations as List)) {
            final role = (row['event_role'] ?? 'athlete')
                .toString()
                .trim()
                .toLowerCase();
            final status =
                (row['status'] ?? '').toString().trim().toLowerCase();
            final eventId = (row['event_id'] ?? '').toString();
            final userId = (row['user_id'] ?? '').toString();
            if (role == 'coach' || status != 'accepted' || userId.isEmpty) {
              continue;
            }
            acceptedAthletesByEvent
                .putIfAbsent(eventId, () => <String>{})
                .add(userId);
          }
          final response = await _supabase
              .from('checkins')
              .select('event_id, user_id')
              .inFilter('event_id', batch);
          for (final row in List<Map<String, dynamic>>.from(response as List)) {
            final eventId = (row['event_id'] ?? '').toString();
            final userId = (row['user_id'] ?? '').toString();
            if (!(acceptedAthletesByEvent[eventId] ?? const <String>{})
                .contains(userId)) {
              continue;
            }
            checkedInByEvent[eventId] = (checkedInByEvent[eventId] ?? 0) + 1;
          }
        }
      }
      for (final eventId in eventIds) {
        final checkedIn = checkedInByEvent[eventId] ?? 0;
        final totalAceitos = acceptedAthletesByEvent[eventId]?.length ?? 0;
        final pending = totalAceitos - checkedIn;
        checkinData[eventId] = {
          'checked_in': checkedIn,
          'pending': pending < 0 ? 0 : pending,
        };
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

  DateTime? _parseEventoDateTime(Map<String, dynamic> evento) {
    try {
      final dataStr = (evento['event_date'] ?? '').toString().trim();
      final horaStr = (evento['event_time'] ?? '').toString().trim();

      if (dataStr.isEmpty || horaStr.isEmpty) return null;

      final dp = dataStr.split('/');
      final tp = horaStr.split(':');

      if (dp.length != 3 || tp.length < 2) return null;

      return DateTime(
        int.parse(dp[2]),
        int.parse(dp[1]),
        int.parse(dp[0]),
        int.parse(tp[0]),
        int.parse(tp[1]),
      );
    } catch (_) {
      return null;
    }
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

    // Mantém o evento em FUTURO durante a janela de check-in
    final limiteCheckin = dataHora.add(const Duration(minutes: 40));

    return DateTime.now().isAfter(limiteCheckin);
  }

  int _getEventosPassadosCount() {
    return _eventos.where((evento) {
      if (!_isEventoPassado(evento)) return false;

      if (_filtroSelecionado != 'Todos' &&
          (evento['event_type'] ?? '').toString().toLowerCase() !=
              _filtroSelecionado.toLowerCase()) {
        return false;
      }

      if (_filtroMes.isNotEmpty) {
        final dataEvento = evento['event_date'] ?? '';
        if (dataEvento.toString().length < 7) return false;
        if (dataEvento.toString().substring(3) != _filtroMes) return false;
      }

      if (_filtroGenero != 'Todos' &&
          (evento['gender'] ?? evento['category'] ?? '')
                  .toString()
                  .toLowerCase() !=
              _filtroGenero.toLowerCase()) {
        return false;
      }

      return true;
    }).length;
  }

  void _alternarEventosPassados() {
    setState(() {
      _mostrarEventosPassados = !_mostrarEventosPassados;
      _aplicarFiltros();
    });
  }

  void _aplicarFiltros() {
    List<Map<String, dynamic>> eventosFiltrados = _eventos.where((evento) {
      final passou = _isEventoPassado(evento);
      return _mostrarEventosPassados ? passou : !passou;
    }).toList();

    if (_filtroSelecionado != 'Todos') {
      eventosFiltrados = eventosFiltrados
          .where(
            (evento) =>
                (evento['event_type'] ?? '').toLowerCase() ==
                _filtroSelecionado.toLowerCase(),
          )
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
          .where(
            (evento) =>
                (evento['gender'] ?? evento['category'] ?? '')
                    .toString()
                    .toLowerCase() ==
                _filtroGenero.toLowerCase(),
          )
          .toList();
    }
    eventosFiltrados.sort((a, b) {
      final dataA = _parseEventoDateTime(a) ?? DateTime(9999);
      final dataB = _parseEventoDateTime(b) ?? DateTime(9999);

      if (_mostrarEventosPassados) {
        return dataB.compareTo(dataA);
      }

      return dataA.compareTo(dataB);
    });

    setState(() {
      _eventosFiltrados = eventosFiltrados;
      _visibleEventLimit = _eventPageSize;
    });
  }

  int get _eventosVisiveisCount => _eventosFiltrados.length < _visibleEventLimit
      ? _eventosFiltrados.length
      : _visibleEventLimit;

  bool get _temMaisEventos => _eventosFiltrados.length > _visibleEventLimit;

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

  Future<void> _mostrarPlanejamentoTreino(Map<String, dynamic> evento) async {
    final eventId = evento['id']?.toString();

    if (eventId == null || eventId.isEmpty) {
      return;
    }

    try {
      final blocksResponse = await _supabase
          .from('training_plan_blocks')
          .select(
            'id, event_id, coach_id, category, type, start_time, end_time, observation, position, updated_at',
          )
          .eq('event_id', eventId)
          .order('position', ascending: true);

      final notesResponse = await _supabase
          .from('training_plan_notes')
          .select('event_id, coach_id, notes, updated_at')
          .eq('event_id', eventId);

      final blocks = List<Map<String, dynamic>>.from(blocksResponse as List);
      final notes = List<Map<String, dynamic>>.from(notesResponse as List);

      final coachIds = <String>{};

      for (final block in blocks) {
        final coachId = (block['coach_id'] ?? '').toString();
        if (coachId.isNotEmpty) coachIds.add(coachId);
      }

      for (final note in notes) {
        final coachId = (note['coach_id'] ?? '').toString();
        if (coachId.isNotEmpty) coachIds.add(coachId);
      }

      final profilesById = <String, Map<String, dynamic>>{};

      if (coachIds.isNotEmpty) {
        final profilesResponse = await _supabase
            .from('profiles')
            .select('id, full_name, avatar_url')
            .inFilter('id', coachIds.toList());

        for (final profile in List<Map<String, dynamic>>.from(
          profilesResponse as List,
        )) {
          final id = (profile['id'] ?? '').toString();
          if (id.isNotEmpty) {
            profilesById[id] = profile;
          }
        }
      }

      final blocksByCoach = <String, List<Map<String, dynamic>>>{};
      final notesByCoach = <String, Map<String, dynamic>>{};

      for (final block in blocks) {
        final coachId = (block['coach_id'] ?? '').toString();
        if (coachId.isEmpty) continue;

        blocksByCoach.putIfAbsent(coachId, () => []);
        blocksByCoach[coachId]!.add(block);
      }

      for (final note in notes) {
        final coachId = (note['coach_id'] ?? '').toString();
        if (coachId.isEmpty) continue;

        notesByCoach[coachId] = note;
      }

      final allCoachIds = <String>{
        ...blocksByCoach.keys,
        ...notesByCoach.keys,
      }.toList();

      allCoachIds.sort((a, b) {
        final nameA = (profilesById[a]?['full_name'] ?? 'Técnico').toString();
        final nameB = (profilesById[b]?['full_name'] ?? 'Técnico').toString();
        return nameA.compareTo(nameB);
      });

      if (!mounted) return;

      if (allCoachIds.isEmpty) {
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          builder: (context) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 42,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.grey[300],
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'Planejamento do treino',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: olympusBlue,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.orange[50],
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.orange[200]!),
                      ),
                      child: const Text(
                        'Nenhum planejamento vinculado a este treino.',
                        style: TextStyle(fontWeight: FontWeight.w600),
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
                          padding: const EdgeInsets.symmetric(vertical: 14),
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
        return;
      }

      String selectedCoachId = allCoachIds.first;

      int blockMinutes(Map<String, dynamic> block) {
        DateTime? parseTime(dynamic value) {
          final raw = (value ?? '').toString().trim();
          final parts = raw.split(':');
          if (parts.length < 2) return null;

          final hour = int.tryParse(parts[0]);
          final minute = int.tryParse(parts[1]);

          if (hour == null || minute == null) return null;
          return DateTime(2000, 1, 1, hour, minute);
        }

        final start = parseTime(block['start_time']);
        final end = parseTime(block['end_time']);

        if (start == null || end == null || !end.isAfter(start)) return 0;
        return end.difference(start).inMinutes;
      }

      String formatDuration(int minutes) {
        if (minutes <= 0) return '0min';

        final h = minutes ~/ 60;
        final m = minutes % 60;

        if (h == 0) return '${m}min';
        if (m == 0) return '${h}h';
        return '${h}h ${m}min';
      }

      String normalizeTime(dynamic value) {
        final raw = (value ?? '').toString().trim();
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

      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (context) {
          return StatefulBuilder(
            builder: (context, setModalState) {
              final selectedBlocks = List<Map<String, dynamic>>.from(
                blocksByCoach[selectedCoachId] ?? [],
              );
              final selectedNote = notesByCoach[selectedCoachId];
              final selectedProfile = profilesById[selectedCoachId];
              final coachName =
                  (selectedProfile?['full_name'] ?? 'Técnico').toString();
              final notesText = (selectedNote?['notes'] ?? '').toString();
              final totalMinutes = selectedBlocks.fold<int>(
                0,
                (sum, block) => sum + blockMinutes(block),
              );

              return SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.of(context).size.height * 0.86,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Center(
                          child: Container(
                            width: 42,
                            height: 4,
                            decoration: BoxDecoration(
                              color: Colors.grey[300],
                              borderRadius: BorderRadius.circular(999),
                            ),
                          ),
                        ),
                        const SizedBox(height: 18),
                        Text(
                          'Planejamento do treino',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: olympusBlue,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          (evento['event_name'] ?? 'Treino').toString(),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 12),
                        if (allCoachIds.length > 1) ...[
                          DropdownButtonFormField<String>(
                            value: selectedCoachId,
                            isExpanded: true,
                            decoration: InputDecoration(
                              labelText: 'Treinador',
                              prefixIcon: Icon(
                                Icons.sports_rounded,
                                color: olympusGold,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(
                                  color: olympusGold,
                                  width: 1.5,
                                ),
                              ),
                            ),
                            items: allCoachIds.map((coachId) {
                              final name = (profilesById[coachId]
                                          ?['full_name'] ??
                                      'Técnico')
                                  .toString();
                              return DropdownMenuItem<String>(
                                value: coachId,
                                child: Text(
                                  name,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              );
                            }).toList(),
                            onChanged: (value) {
                              if (value == null) return;
                              setModalState(() {
                                selectedCoachId = value;
                              });
                            },
                          ),
                          const SizedBox(height: 12),
                        ],
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: olympusBlue.withOpacity(0.06),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: olympusBlue.withOpacity(0.10),
                            ),
                          ),
                          child: Row(
                            children: [
                              CircleAvatar(
                                backgroundColor: olympusBlue.withOpacity(0.10),
                                child: Text(
                                  coachName.isNotEmpty
                                      ? coachName.characters.first.toUpperCase()
                                      : 'T',
                                  style: TextStyle(
                                    color: olympusBlue,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      coachName,
                                      style: TextStyle(
                                        color: olympusBlue,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '${selectedBlocks.length} bloco${selectedBlocks.length == 1 ? '' : 's'} • ${formatDuration(totalMinutes)}',
                                      style: TextStyle(
                                        color: Colors.grey[700],
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (notesText.trim().isNotEmpty) ...[
                          const SizedBox(height: 10),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: olympusGold.withOpacity(0.08),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: olympusGold.withOpacity(0.20),
                              ),
                            ),
                            child: Text(
                              notesText,
                              style: TextStyle(
                                color: Colors.grey[800],
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 16),
                        if (selectedBlocks.isEmpty)
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: Colors.orange[50],
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.orange[200]!),
                            ),
                            child: const Text(
                              'Nenhum bloco cadastrado para este treinador.',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                          )
                        else
                          Flexible(
                            child: ListView.separated(
                              shrinkWrap: true,
                              itemCount: selectedBlocks.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 10),
                              itemBuilder: (context, index) {
                                final bloco = selectedBlocks[index];
                                final titulo = (bloco['type'] ??
                                        bloco['category'] ??
                                        'Bloco ${index + 1}')
                                    .toString();
                                final categoria =
                                    (bloco['category'] ?? 'Bloco').toString();
                                final inicio = normalizeTime(
                                  bloco['start_time'],
                                );
                                final fim = normalizeTime(bloco['end_time']);
                                final observacao =
                                    (bloco['observation'] ?? '').toString();
                                final minutos = blockMinutes(bloco);

                                return Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.grey[50],
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: Colors.grey[200]!,
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Container(
                                            width: 28,
                                            height: 28,
                                            alignment: Alignment.center,
                                            decoration: BoxDecoration(
                                              color: olympusGold.withOpacity(
                                                0.16,
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                            child: Text(
                                              '${index + 1}',
                                              style: TextStyle(
                                                fontWeight: FontWeight.w800,
                                                color: olympusBlue,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Text(
                                              titulo,
                                              style: TextStyle(
                                                fontWeight: FontWeight.w800,
                                                fontSize: 14,
                                                color: olympusBlue,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        '$categoria${inicio.isNotEmpty || fim.isNotEmpty ? ' • $inicio${fim.isNotEmpty ? ' às $fim' : ''}' : ''}${minutos > 0 ? ' • ${formatDuration(minutos)}' : ''}',
                                        style: TextStyle(
                                          color: Colors.grey[700],
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      if (observacao.trim().isNotEmpty) ...[
                                        const SizedBox(height: 6),
                                        Text(
                                          observacao,
                                          style: TextStyle(
                                            color: Colors.grey[700],
                                            fontSize: 12,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                );
                              },
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
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                            child: const Text('Fechar'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao carregar planejamento do treino: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _navegarParaCadastroEvento() async {
    if (_openingAgendaPage) return;
    _openingAgendaPage = true;
    try {
      final result = await Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const AddEventPage()),
      );
      if (result == true) {
        await _refreshEventos();
      }
    } finally {
      _openingAgendaPage = false;
    }
  }

  void _editarEvento(Map<String, dynamic> evento) async {
    if (_openingAgendaPage) return;
    _openingAgendaPage = true;
    try {
      final result = await Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => AddEventPage(evento: evento)),
      );
      if (result == true) {
        await _refreshEventos();
      }
    } finally {
      _openingAgendaPage = false;
    }
  }

  // ✅ NOVO: Método para excluir evento
  Future<void> _excluirEvento(Map<String, dynamic> evento) async {
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Excluir evento'),
        content: const Text(
          'Tem certeza que deseja excluir este evento? Esta ação não pode ser desfeita.',
        ),
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

  Future<void> _exportarCaronasPdf(Map<String, dynamic> evento) async {
    final eventId = (evento['id'] ?? '').toString();
    if (eventId.isEmpty) return;

    try {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Preparando PDF das caronas...'),
            duration: Duration(seconds: 2),
          ),
        );
      }

      final results = await Future.wait<dynamic>([
        _supabase
            .from('convocations')
            .select('user_id, status, justification, event_role')
            .eq('event_id', eventId),
        _supabase
            .from('event_rides')
            .select('user_id, ride_type, needs_ride, has_car, available_seats')
            .eq('event_id', eventId),
      ]);

      final convocations = List<Map<String, dynamic>>.from(results[0] as List);
      final rides = List<Map<String, dynamic>>.from(results[1] as List);
      final userIds = convocations
          .map((row) => (row['user_id'] ?? '').toString())
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList();
      final profileRows = userIds.isEmpty
          ? <dynamic>[]
          : await _supabase
              .from('profiles')
              .select('id, full_name, birth_date, rg, user_type')
              .inFilter('id', userIds);
      final profilesById = <String, Map<String, dynamic>>{
        for (final profile in List<Map<String, dynamic>>.from(
          profileRows as List,
        ))
          (profile['id'] ?? '').toString(): profile,
      };
      final ridesByUser = <String, Map<String, Map<String, dynamic>>>{};
      for (final ride in rides) {
        final userId = (ride['user_id'] ?? '').toString();
        final rideType =
            (ride['ride_type'] ?? '').toString().trim().toLowerCase();
        if (userId.isEmpty || (rideType != 'ida' && rideType != 'volta')) {
          continue;
        }
        ridesByUser.putIfAbsent(userId, () => {})[rideType] = ride;
      }

      int seats(Map<String, dynamic>? ride) {
        if (ride == null || ride['has_car'] != true) return 0;
        final raw = ride['available_seats'];
        return raw is int ? raw : int.tryParse('$raw') ?? 0;
      }

      String rideText(Map<String, dynamic>? ride) {
        if (ride == null) return 'Não respondeu';
        if (ride['needs_ride'] == true) return 'Precisa de carona';
        final available = seats(ride);
        if (ride['has_car'] == true && available > 0) {
          return 'Oferece $available vaga${available == 1 ? '' : 's'}';
        }
        if (ride['has_car'] == true) return 'Carro sem vagas';
        return 'Não precisa de carona';
      }

      String participantType(Map<String, dynamic> convocation) {
        final role = (convocation['event_role'] ?? '').toString().toLowerCase();
        if (role == 'coach') return 'Treinador';
        return 'Atleta';
      }

      final accepted = convocations.where((row) {
        return (row['status'] ?? '').toString().toLowerCase() == 'accepted';
      }).toList()
        ..sort((a, b) {
          final aName = (profilesById[(a['user_id'] ?? '').toString()]
                      ?['full_name'] ??
                  '')
              .toString();
          final bName = (profilesById[(b['user_id'] ?? '').toString()]
                      ?['full_name'] ??
                  '')
              .toString();
          return aName.toLowerCase().compareTo(bName.toLowerCase());
        });
      final pending = convocations.where((row) {
        return (row['status'] ?? 'pending').toString().toLowerCase() ==
            'pending';
      }).toList();
      final rejected = convocations.where((row) {
        return (row['status'] ?? '').toString().toLowerCase() == 'rejected';
      }).toList();

      var needRideOut = 0;
      var needRideBack = 0;
      var seatsOut = 0;
      var seatsBack = 0;
      for (final convocation in accepted) {
        final userId = (convocation['user_id'] ?? '').toString();
        final userRides = ridesByUser[userId] ?? const {};
        final out = userRides['ida'];
        final back = userRides['volta'];
        if (out?['needs_ride'] == true) needRideOut++;
        if (back?['needs_ride'] == true) needRideBack++;
        seatsOut += seats(out);
        seatsBack += seats(back);
      }

      final eventName = (evento['event_name'] ?? 'Evento').toString();
      final eventDate = (evento['event_date'] ?? '-').toString();
      final eventTime = (evento['event_time'] ?? '-').toString();
      final championship =
          (evento['championship_name'] ?? '').toString().trim();
      final street = (evento['street'] ?? '').toString().trim();
      final number = (evento['street_number'] ?? '').toString().trim();
      final city = (evento['city'] ?? '').toString().trim();
      final state = (evento['state'] ?? '').toString().trim();
      final address = street.isEmpty
          ? '-'
          : '$street${number.isEmpty ? '' : ', $number'}'
              '${city.isEmpty ? '' : ' - $city'}'
              '${state.isEmpty ? '' : '/$state'}';

      final document = pw.Document();
      document.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4.landscape,
          margin: const pw.EdgeInsets.all(28),
          header: (_) => pw.Container(
            padding: const pw.EdgeInsets.only(bottom: 8),
            decoration: const pw.BoxDecoration(
              border: pw.Border(
                bottom: pw.BorderSide(color: PdfColors.blueGrey200),
              ),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  'Olympus • Logística de caronas',
                  style: pw.TextStyle(
                    color: PdfColors.blueGrey900,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.Text(
                  'Gerado em ${DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now())}',
                  style: const pw.TextStyle(fontSize: 8),
                ),
              ],
            ),
          ),
          footer: (context) => pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Text(
              'Página ${context.pageNumber} de ${context.pagesCount}',
              style: const pw.TextStyle(fontSize: 8),
            ),
          ),
          build: (_) => [
            pw.SizedBox(height: 12),
            pw.Text(
              eventName,
              style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
            ),
            if (championship.isNotEmpty) pw.Text(championship),
            pw.SizedBox(height: 5),
            pw.Text('Data: $eventDate • Horário: $eventTime'),
            pw.Text('Endereço: $address'),
            pw.SizedBox(height: 16),
            pw.Row(
              children: [
                _pdfRideMetric('Aceitaram', accepted.length, PdfColors.green),
                pw.SizedBox(width: 8),
                _pdfRideMetric('Precisam • ida', needRideOut, PdfColors.orange),
                pw.SizedBox(width: 8),
                _pdfRideMetric('Vagas • ida', seatsOut, PdfColors.blueGrey),
                pw.SizedBox(width: 8),
                _pdfRideMetric(
                  'Precisam • volta',
                  needRideBack,
                  PdfColors.orange,
                ),
                pw.SizedBox(width: 8),
                _pdfRideMetric('Vagas • volta', seatsBack, PdfColors.blueGrey),
              ],
            ),
            pw.SizedBox(height: 18),
            pw.Text(
              'Participantes e caronas',
              style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 7),
            if (accepted.isEmpty)
              pw.Text('Nenhum participante aceitou o evento.')
            else
              pw.Table.fromTextArray(
                headers: const ['Participante', 'Tipo', 'Ida', 'Volta'],
                data: accepted.map((convocation) {
                  final userId = (convocation['user_id'] ?? '').toString();
                  final profile = profilesById[userId] ?? const {};
                  final userRides = ridesByUser[userId] ?? const {};
                  return [
                    (profile['full_name'] ?? 'Sem nome').toString(),
                    participantType(convocation),
                    rideText(userRides['ida']),
                    rideText(userRides['volta']),
                  ];
                }).toList(),
                headerDecoration: const pw.BoxDecoration(
                  color: PdfColors.blueGrey900,
                ),
                headerStyle: pw.TextStyle(
                  color: PdfColors.white,
                  fontWeight: pw.FontWeight.bold,
                ),
                cellStyle: const pw.TextStyle(fontSize: 9),
                cellPadding: const pw.EdgeInsets.all(6),
              ),
            pw.SizedBox(height: 18),
            if (pending.isNotEmpty) ...[
              pw.Text(
                'Pendentes (${pending.length})',
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              ),
              pw.Text(
                pending
                    .map(
                      (row) => (profilesById[(row['user_id'] ?? '').toString()]
                                  ?['full_name'] ??
                              'Sem nome')
                          .toString(),
                    )
                    .join(' • '),
              ),
              pw.SizedBox(height: 10),
            ],
            if (rejected.isNotEmpty) ...[
              pw.Text(
                'Recusaram (${rejected.length})',
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              ),
              pw.SizedBox(height: 5),
              ...rejected.map((row) {
                final profile =
                    profilesById[(row['user_id'] ?? '').toString()] ?? const {};
                final reason = (row['justification'] ?? '').toString().trim();
                return pw.Padding(
                  padding: const pw.EdgeInsets.only(bottom: 3),
                  child: pw.Text(
                    '• ${profile['full_name'] ?? 'Sem nome'}${reason.isEmpty ? '' : ' — $reason'}',
                  ),
                );
              }),
            ],
          ],
        ),
      );

      final safeName = eventName
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
          .replaceAll(RegExp(r'^_+|_+$'), '');
      await Printing.sharePdf(
        bytes: await document.save(),
        filename: 'caronas_${safeName.isEmpty ? eventId : safeName}.pdf',
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Não foi possível gerar o PDF: $error'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  pw.Widget _pdfRideMetric(String label, int value, PdfColor color) {
    return pw.Expanded(
      child: pw.Container(
        padding: const pw.EdgeInsets.all(10),
        decoration: pw.BoxDecoration(
          color: PdfColors.grey100,
          border: pw.Border.all(color: color, width: 1),
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              '$value',
              style: pw.TextStyle(
                color: color,
                fontSize: 17,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.Text(label, style: const pw.TextStyle(fontSize: 8)),
          ],
        ),
      ),
    );
  }

  // Mantido para compatibilidade com instalações anteriores.
  // ignore: unused_element
  Future<void> _exportarConvocados(Map<String, dynamic> evento) async {
    final eventId = evento['id']?.toString();
    if (eventId == null) return;
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
      final convocationsResponse = await _supabase
          .from('convocations')
          .select('user_id, status, justification')
          .eq('event_id', eventId);
      String _formatBirthDate(dynamic rawDate) {
        if (rawDate == null || rawDate.toString().trim().isEmpty) return '-';
        try {
          final date = DateTime.parse(rawDate.toString());
          return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
        } catch (_) {
          return rawDate.toString();
        }
      }

      String _buildRideText(Map<String, dynamic>? ride) {
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
        if (hasCar && seats == 0) {
          return 'Vou de carro e não tenho vagas';
        }
        if (!needsRide && seats == 0) {
          return 'Vou de carro e não tenho vagas';
        }
        return 'Não respondeu';
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
      final lines = <String>[
        'Campeonato/liga: $championshipName',
        'Data: $dataJogo - Horário: $horarioJogo',
        nomeJogo,
        'Endereço: $endereco',
        '',
        'ACEITARAM',
        '',
      ];
      final pendentesLines = <String>['', 'PENDENTES', ''];
      final recusadosLines = <String>['', 'RECUSARAM', ''];
      for (final convocation in convocationsResponse) {
        final userId = convocation['user_id']?.toString();
        if (userId == null || userId.isEmpty) continue;
        final status = (convocation['status'] ?? 'pending').toString();
        final profileResponse = await _supabase
            .from('profiles')
            .select('full_name, birth_date, rg')
            .eq('id', userId)
            .maybeSingle();
        if (profileResponse == null) continue;
        final nome = (profileResponse['full_name'] ?? '-').toString();

        if (status == 'accepted') {
          final ridesResponse = await _supabase
              .from('event_rides')
              .select('ride_type, needs_ride, has_car, available_seats')
              .eq('event_id', eventId)
              .eq('user_id', userId);
          Map<String, dynamic>? idaRide;
          Map<String, dynamic>? voltaRide;
          for (final ride in ridesResponse) {
            final rideType =
                (ride['ride_type'] ?? '').toString().toLowerCase().trim();
            if (rideType == 'ida') {
              idaRide = Map<String, dynamic>.from(ride);
            } else if (rideType == 'volta') {
              voltaRide = Map<String, dynamic>.from(ride);
            }
          }
          final precisaCarona = (idaRide?['needs_ride'] == true) ||
                  (voltaRide?['needs_ride'] == true)
              ? 'Sim'
              : 'Não';
          final dataNascimento = _formatBirthDate(
            profileResponse['birth_date'],
          );
          final rg = (profileResponse['rg'] ?? '-').toString();
          final ida = _buildRideText(idaRide);
          final volta = _buildRideText(voltaRide);
          lines.add(
            'Nome: $nome\n'
            'Data de nascimento: $dataNascimento\n'
            'RG: $rg\n'
            'Precisa de carona: $precisaCarona\n'
            'Ida: $ida\n'
            'Volta: $volta\n',
          );
        } else if (status == 'rejected') {
          final justificativa =
              (convocation['justification'] ?? '-').toString().trim();
          recusadosLines.add(
            'Nome: $nome\n'
            'Justificativa: ${justificativa.isEmpty ? '-' : justificativa}\n',
          );
        } else {
          pendentesLines.add('Nome: $nome\n');
        }
      }
      lines.addAll(pendentesLines);
      lines.addAll(recusadosLines);
      final formattedContent = lines.join('\n');
      await Clipboard.setData(ClipboardData(text: formattedContent));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Dados do jogo copiados! Agora é só colar'),
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
      final cachedAt = _convocadosDetailsCacheTime[eventId];
      final hasFreshCache = cachedAt != null &&
          DateTime.now().difference(cachedAt) < _convocadosDetailsCacheTtl;
      List<Map<String, dynamic>> participantes;

      if (hasFreshCache && _convocadosDetailsCache.containsKey(eventId)) {
        participantes = _convocadosDetailsCache[eventId]!
            .map((item) => Map<String, dynamic>.from(item))
            .toList();
      } else {
        final convocationsResponse = await _supabase
            .from('convocations')
            .select('user_id, status, justification, event_role')
            .eq('event_id', eventId);
        final convocations = List<Map<String, dynamic>>.from(
          convocationsResponse as List,
        );
        final userIds = convocations
            .map((row) => (row['user_id'] ?? '').toString())
            .where((id) => id.isNotEmpty)
            .toSet()
            .toList();
        final profileRows = userIds.isEmpty
            ? <dynamic>[]
            : await _supabase
                .from('profiles')
                .select('id, full_name, user_type, avatar_url')
                .inFilter('id', userIds);
        final profilesById = <String, Map<String, dynamic>>{
          for (final profile in List<Map<String, dynamic>>.from(
            profileRows as List,
          ))
            (profile['id'] ?? '').toString(): profile,
        };

        participantes = convocations.map((convocation) {
          final userId = (convocation['user_id'] ?? '').toString();
          final profile = profilesById[userId] ?? const <String, dynamic>{};
          return <String, dynamic>{
            'user_id': userId,
            'nome': profile['full_name'] ?? 'Sem nome',
            'tipo': profile['user_type'] ?? 'unknown',
            'avatar_url': profile['avatar_url'],
            'status': convocation['status'] ?? 'pending',
            'justification': convocation['justification'],
            'event_role': convocation['event_role'] ?? 'athlete',
          };
        }).toList()
          ..sort(
            (a, b) => (a['nome'] ?? '').toString().toLowerCase().compareTo(
                  (b['nome'] ?? '').toString().toLowerCase(),
                ),
          );
        _convocadosDetailsCache[eventId] = participantes;
        _convocadosDetailsCacheTime[eventId] = DateTime.now();
      }
      final athleteParticipants = participantes.where((participant) {
        final role = (participant['event_role'] ?? 'athlete')
            .toString()
            .trim()
            .toLowerCase();
        return role != 'coach' &&
            role != 'treinador' &&
            role != 'tecnico' &&
            role != 'técnico';
      }).toList();
      final accepted = athleteParticipants.where((participant) {
        return (participant['status'] ?? 'pending')
                .toString()
                .trim()
                .toLowerCase() ==
            'accepted';
      }).length;
      final rejected = athleteParticipants.where((participant) {
        return (participant['status'] ?? 'pending')
                .toString()
                .trim()
                .toLowerCase() ==
            'rejected';
      }).length;
      if (mounted) {
        setState(() {
          _convocationStats[eventId] = {
            'total_convocados': athleteParticipants.length,
            'total_aceitos': accepted,
            'total_pendentes': athleteParticipants.length - accepted - rejected,
            'total_recusados': rejected,
          };
        });
        _saveAgendaCache();
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
                      Icon(Icons.people_outline, color: olympusGold, size: 28),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Convocados: ${evento['event_name']}',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: olympusBlue,
                              ),
                            ),
                            Text(
                              '${participantes.where((p) => p['event_role'] != 'coach' && p['status'] == 'accepted').length} aceitaram de ${participantes.where((p) => p['event_role'] != 'coach').length} atletas',
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
                              final isCoach =
                                  participante['event_role'] == 'coach';
                              final labelStatus = isCoach
                                  ? 'Treinador'
                                  : isAceitou
                                      ? 'Aceitou'
                                      : (isRecusou ? 'Recusou' : 'Pendente');
                              final colorStatus = isCoach
                                  ? olympusBlue
                                  : isAceitou
                                      ? Colors.green[700]
                                      : (isRecusou
                                          ? Colors.red[700]
                                          : Colors.grey[600]);
                              return Container(
                                margin: const EdgeInsets.only(bottom: 8),
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: isCoach
                                      ? olympusGold.withOpacity(0.14)
                                      : isAceitou
                                          ? Colors.green[50]
                                          : (isRecusou
                                              ? Colors.red[50]
                                              : Colors.grey[100]),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: isCoach
                                        ? olympusGold
                                        : isAceitou
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
                                          isCoach
                                              ? Icons.sports_rounded
                                              : isAceitou
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
                                                isCoach
                                                    ? 'Treinador • sem check-in'
                                                    : (isAtleta
                                                        ? 'Atleta'
                                                        : 'Comissão técnica'),
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
                                    if (!isCoach &&
                                        isRecusou &&
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
          .select('user_id, status, justification, event_role')
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
        final role = (convocation['event_role'] ?? 'athlete')
            .toString()
            .trim()
            .toLowerCase();
        if (role == 'coach') continue;
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
                              style: TextStyle(
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
                                  border: Border.all(color: Colors.green[300]!),
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

  // ✅ NOVO: Admin pode alterar o status de aceite mesmo após o prazo
  // ✅ NOVO: Admin pode alterar o status de aceite mesmo após o prazo
  // ✅ VISUAL AJUSTADO: modal no padrão Olympus do sistema
  Future<void> _alterarStatusAceiteAtleta(Map<String, dynamic> evento) async {
    if (!_isAdmin) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Apenas administradores podem alterar o aceite.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final eventId = evento['id']?.toString();
    if (eventId == null || eventId.isEmpty) return;

    try {
      final convocationsResponse = await _supabase
          .from('convocations')
          .select('user_id, status, justification')
          .eq('event_id', eventId);

      final participantes = <Map<String, dynamic>>[];

      for (final convocation in convocationsResponse) {
        final userId = convocation['user_id']?.toString();
        if (userId == null || userId.isEmpty) continue;

        final profileResponse = await _supabase
            .from('profiles')
            .select('full_name, user_type')
            .eq('id', userId)
            .maybeSingle();

        if (profileResponse == null) continue;

        participantes.add({
          'user_id': userId,
          'nome': profileResponse['full_name'] ?? 'Sem nome',
          'tipo': profileResponse['user_type'] ?? 'unknown',
          'status': convocation['status'] ?? 'pending',
          'justification': convocation['justification'] ?? '',
        });
      }

      if (!mounted) return;

      if (participantes.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Nenhum atleta/técnico convocado para este evento.'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      String? selectedUserId = participantes.first['user_id']?.toString();
      String selectedStatus =
          participantes.first['status']?.toString() ?? 'pending';
      final justificationController = TextEditingController(
        text: participantes.first['justification']?.toString() ?? '',
      );
      bool saving = false;

      String statusLabel(String status) {
        switch (status) {
          case 'accepted':
            return 'Aceito';
          case 'rejected':
            return 'Recusado';
          default:
            return 'Pendente';
        }
      }

      IconData statusIcon(String status) {
        switch (status) {
          case 'accepted':
            return Icons.check_circle_outline;
          case 'rejected':
            return Icons.cancel_outlined;
          default:
            return Icons.hourglass_empty;
        }
      }

      Color statusColor(String status) {
        switch (status) {
          case 'accepted':
            return Colors.green;
          case 'rejected':
            return Colors.red;
          default:
            return Colors.orange;
        }
      }

      await showDialog(
        context: context,
        barrierDismissible: !saving,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setDialogState) {
            final selectedParticipante = participantes.firstWhere(
              (p) => p['user_id']?.toString() == selectedUserId,
              orElse: () => participantes.first,
            );

            final tipo = selectedParticipante['tipo'] == 'athlete'
                ? 'Atleta'
                : selectedParticipante['tipo'] == 'coach'
                    ? 'Técnico'
                    : 'Membro';

            final currentStatus =
                selectedParticipante['status']?.toString() ?? 'pending';
            final currentStatusColor = statusColor(currentStatus);

            InputDecoration olympusInputDecoration(String label) {
              return InputDecoration(
                labelText: label,
                labelStyle: TextStyle(
                  color: olympusBlue.withOpacity(0.75),
                  fontWeight: FontWeight.w600,
                ),
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: olympusBlue.withOpacity(0.12)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: olympusGold, width: 2),
                ),
                disabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: Colors.grey.withOpacity(0.20)),
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              );
            }

            Widget olympusSection({
              required IconData icon,
              required String title,
              required Widget child,
            }) {
              return Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.grey[50],
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: olympusBlue.withOpacity(0.12)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.035),
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
                        Icon(icon, size: 17, color: olympusGold),
                        const SizedBox(width: 7),
                        Text(
                          title,
                          style: TextStyle(
                            color: olympusBlue.withOpacity(0.85),
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.4,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    child,
                  ],
                ),
              );
            }

            return Dialog(
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 18,
                vertical: 24,
              ),
              elevation: 10,
              shadowColor: olympusGold.withOpacity(0.25),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: Container(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.86,
                  ),
                  decoration: const BoxDecoration(color: Colors.white),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.fromLTRB(20, 20, 12, 18),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [olympusBlue, olympusLightBlue],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(11),
                              decoration: BoxDecoration(
                                color: olympusGold.withOpacity(0.18),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: olympusGold.withOpacity(0.45),
                                ),
                              ),
                              child: Icon(
                                Icons.manage_accounts_outlined,
                                color: olympusGold,
                                size: 28,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Alterar aceite',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 21,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    evento['event_name']?.toString() ??
                                        'Evento sem nome',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: Colors.white.withOpacity(0.82),
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              onPressed: saving
                                  ? null
                                  : () => Navigator.pop(dialogContext),
                              icon: const Icon(Icons.close),
                              color: Colors.white,
                            ),
                          ],
                        ),
                      ),
                      Flexible(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(18),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              olympusSection(
                                icon: Icons.person_outline,
                                title: 'ATLETA / TÉCNICO',
                                child: DropdownButtonFormField<String>(
                                  value: selectedUserId,
                                  isExpanded: true,
                                  decoration: olympusInputDecoration(
                                    'Selecione o participante',
                                  ),
                                  icon: Icon(
                                    Icons.keyboard_arrow_down_rounded,
                                    color: olympusGold,
                                  ),
                                  items: participantes.map((participante) {
                                    final participanteTipo =
                                        participante['tipo'] == 'athlete'
                                            ? 'Atleta'
                                            : participante['tipo'] == 'coach'
                                                ? 'Técnico'
                                                : 'Membro';
                                    final participanteStatus =
                                        participante['status']?.toString() ??
                                            'pending';
                                    return DropdownMenuItem<String>(
                                      value:
                                          participante['user_id']?.toString(),
                                      child: Row(
                                        children: [
                                          Icon(
                                            statusIcon(participanteStatus),
                                            size: 18,
                                            color: statusColor(
                                              participanteStatus,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              '${participante['nome']} • $participanteTipo',
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  }).toList(),
                                  onChanged: saving
                                      ? null
                                      : (value) {
                                          if (value == null) return;
                                          final participante =
                                              participantes.firstWhere(
                                            (p) =>
                                                p['user_id']?.toString() ==
                                                value,
                                            orElse: () => participantes.first,
                                          );
                                          setDialogState(() {
                                            selectedUserId = value;
                                            selectedStatus =
                                                participante['status']
                                                            ?.toString()
                                                            .trim()
                                                            .isNotEmpty ==
                                                        true
                                                    ? participante['status']
                                                        .toString()
                                                    : 'pending';
                                            justificationController.text =
                                                participante['justification']
                                                        ?.toString() ??
                                                    '';
                                          });
                                        },
                                ),
                              ),
                              const SizedBox(height: 14),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: currentStatusColor.withOpacity(0.08),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: currentStatusColor.withOpacity(0.25),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: currentStatusColor.withOpacity(
                                          0.12,
                                        ),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Icon(
                                        statusIcon(currentStatus),
                                        color: currentStatusColor,
                                        size: 22,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Status atual: ${statusLabel(currentStatus)}',
                                            style: TextStyle(
                                              color: currentStatusColor,
                                              fontWeight: FontWeight.w900,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            tipo,
                                            style: TextStyle(
                                              color: Colors.grey[700],
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 14),
                              olympusSection(
                                icon: Icons.rule_folder_outlined,
                                title: 'NOVO STATUS',
                                child: DropdownButtonFormField<String>(
                                  value: selectedStatus,
                                  decoration: olympusInputDecoration(
                                    'Escolha o novo status',
                                  ),
                                  icon: Icon(
                                    Icons.keyboard_arrow_down_rounded,
                                    color: olympusGold,
                                  ),
                                  items: const [
                                    DropdownMenuItem(
                                      value: 'accepted',
                                      child: Row(
                                        children: [
                                          Icon(
                                            Icons.check_circle_outline,
                                            size: 18,
                                            color: Colors.green,
                                          ),
                                          SizedBox(width: 8),
                                          Text('Aceito'),
                                        ],
                                      ),
                                    ),
                                    DropdownMenuItem(
                                      value: 'pending',
                                      child: Row(
                                        children: [
                                          Icon(
                                            Icons.hourglass_empty,
                                            size: 18,
                                            color: Colors.orange,
                                          ),
                                          SizedBox(width: 8),
                                          Text('Pendente'),
                                        ],
                                      ),
                                    ),
                                    DropdownMenuItem(
                                      value: 'rejected',
                                      child: Row(
                                        children: [
                                          Icon(
                                            Icons.cancel_outlined,
                                            size: 18,
                                            color: Colors.red,
                                          ),
                                          SizedBox(width: 8),
                                          Text('Recusado'),
                                        ],
                                      ),
                                    ),
                                  ],
                                  onChanged: saving
                                      ? null
                                      : (value) {
                                          if (value == null) return;
                                          setDialogState(() {
                                            selectedStatus = value;
                                            if (value != 'rejected') {
                                              justificationController.clear();
                                            }
                                          });
                                        },
                                ),
                              ),
                              if (selectedStatus == 'rejected') ...[
                                const SizedBox(height: 14),
                                olympusSection(
                                  icon: Icons.notes_outlined,
                                  title: 'JUSTIFICATIVA',
                                  child: TextField(
                                    controller: justificationController,
                                    maxLines: 3,
                                    enabled: !saving,
                                    decoration: olympusInputDecoration(
                                      'Justificativa da recusa (opcional)',
                                    ),
                                  ),
                                ),
                              ],
                              const SizedBox(height: 14),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(13),
                                decoration: BoxDecoration(
                                  color: olympusBlue.withOpacity(0.055),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: olympusBlue.withOpacity(0.10),
                                  ),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Icon(
                                      Icons.info_outline,
                                      color: olympusBlue,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 9),
                                    Expanded(
                                      child: Text(
                                        'Esta alteração ignora o prazo normal de resposta e será aplicada diretamente na convocação.',
                                        style: TextStyle(
                                          color: Colors.grey[700],
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
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
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.08),
                              blurRadius: 10,
                              offset: const Offset(0, -2),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: saving
                                    ? null
                                    : () => Navigator.pop(dialogContext),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.grey[700],
                                  side: BorderSide(color: Colors.grey[300]!),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                ),
                                child: const Text(
                                  'Cancelar',
                                  style: TextStyle(fontWeight: FontWeight.w700),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              flex: 2,
                              child: ElevatedButton.icon(
                                onPressed: saving || selectedUserId == null
                                    ? null
                                    : () async {
                                        setDialogState(() {
                                          saving = true;
                                        });

                                        try {
                                          final justification =
                                              selectedStatus == 'rejected'
                                                  ? justificationController.text
                                                      .trim()
                                                  : null;

                                          final updatedRows = await _supabase
                                              .from('convocations')
                                              .update({
                                                'status': selectedStatus,
                                                'justification': justification,
                                              })
                                              .eq('event_id', eventId)
                                              .eq('user_id', selectedUserId!)
                                              .select(
                                                'user_id, status, justification',
                                              );

                                          if (updatedRows is! List ||
                                              updatedRows.isEmpty) {
                                            throw Exception(
                                              'Nenhuma convocação foi atualizada. Verifique as policies/RLS da tabela convocations para permitir update de admin.',
                                            );
                                          }

                                          final updatedStatus = updatedRows
                                              .first['status']
                                              ?.toString();
                                          if (updatedStatus != selectedStatus) {
                                            throw Exception(
                                              'O banco retornou status "$updatedStatus" em vez de "$selectedStatus". Pode existir trigger/policy revertendo a alteração.',
                                            );
                                          }

                                          if (selectedStatus != 'accepted') {
                                            await _supabase
                                                .from('checkins')
                                                .delete()
                                                .eq('event_id', eventId)
                                                .eq('user_id', selectedUserId!);
                                          }

                                          if (mounted) {
                                            Navigator.pop(dialogContext);
                                            await _buscarEventos();
                                            ScaffoldMessenger.of(
                                              context,
                                            ).showSnackBar(
                                              SnackBar(
                                                content: Text(
                                                  '✅ Status alterado para ${statusLabel(selectedStatus)}!',
                                                ),
                                                backgroundColor: Colors.green,
                                              ),
                                            );
                                          }
                                        } catch (e) {
                                          setDialogState(() {
                                            saving = false;
                                          });
                                          if (mounted) {
                                            ScaffoldMessenger.of(
                                              context,
                                            ).showSnackBar(
                                              SnackBar(
                                                content: Text(
                                                  '❌ Erro ao alterar status de aceite: $e',
                                                ),
                                                backgroundColor: Colors.red,
                                              ),
                                            );
                                          }
                                        }
                                      },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: olympusGold,
                                  foregroundColor: olympusBlue,
                                  disabledBackgroundColor: Colors.grey[300],
                                  disabledForegroundColor: Colors.grey[600],
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                  ),
                                  elevation: 4,
                                  shadowColor: olympusGold.withOpacity(0.35),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                ),
                                icon: saving
                                    ? SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: olympusBlue,
                                        ),
                                      )
                                    : const Icon(Icons.save_outlined),
                                label: Text(
                                  saving ? 'Salvando...' : 'Salvar alteração',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w900,
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
            );
          },
        ),
      );

      justificationController.dispose();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao abrir alteração de aceite: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // ✅ NOVO: Check-in atrasado/manual apenas para Admin
  Future<void> _realizarCheckinAtrasado(Map<String, dynamic> evento) async {
    if (!_isAdmin) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Apenas administradores podem fazer check-in atrasado.',
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final eventId = evento['id']?.toString();
    if (eventId == null || eventId.isEmpty) return;

    try {
      final convocationsResponse = await _supabase
          .from('convocations')
          .select('user_id, status, event_role')
          .eq('event_id', eventId)
          .eq('status', 'accepted');

      final checkinsResponse = await _supabase
          .from('checkins')
          .select('user_id')
          .eq('event_id', eventId);

      final Set<String> userIdsComCheckin = checkinsResponse
          .map<String>((row) => row['user_id']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .toSet();

      final participantesSemCheckin = <Map<String, dynamic>>[];

      for (final convocation in convocationsResponse) {
        final role = (convocation['event_role'] ?? 'athlete')
            .toString()
            .trim()
            .toLowerCase();
        if (role == 'coach') continue;
        final userId = convocation['user_id']?.toString();
        if (userId == null || userId.isEmpty) continue;
        if (userIdsComCheckin.contains(userId)) continue;

        final profileResponse = await _supabase
            .from('profiles')
            .select('full_name, user_type')
            .eq('id', userId)
            .maybeSingle();

        if (profileResponse == null) continue;

        participantesSemCheckin.add({
          'user_id': userId,
          'nome': profileResponse['full_name'] ?? 'Sem nome',
          'tipo': profileResponse['user_type'] ?? 'unknown',
        });
      }

      if (!mounted) return;

      if (participantesSemCheckin.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Todos os participantes que aceitaram já fizeram check-in.',
            ),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      String? selectedUserId = participantesSemCheckin.first['user_id'];
      DateTime selectedDate = DateTime.now();
      TimeOfDay selectedTime = TimeOfDay.now();
      bool saving = false;

      ThemeData olympusPickerTheme(BuildContext pickerContext) {
        final base = Theme.of(pickerContext);
        return base.copyWith(
          colorScheme: ColorScheme.light(
            primary: olympusBlue,
            onPrimary: Colors.white,
            secondary: olympusGold,
            onSecondary: olympusBlue,
            surface: Colors.white,
            onSurface: Color(0xFF1E3A5F),
          ),
          datePickerTheme: DatePickerThemeData(
            backgroundColor: Colors.white,
            headerBackgroundColor: olympusBlue,
            headerForegroundColor: Colors.white,
            surfaceTintColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            dayOverlayColor: MaterialStateProperty.all(
              olympusGold.withOpacity(0.10),
            ),
            todayBorder: BorderSide(color: olympusGold, width: 1.5),
            todayForegroundColor: MaterialStateProperty.all(olympusBlue),
            dayForegroundColor: MaterialStateProperty.resolveWith((states) {
              if (states.contains(MaterialState.selected)) return Colors.white;
              return olympusBlue;
            }),
            dayBackgroundColor: MaterialStateProperty.resolveWith((states) {
              if (states.contains(MaterialState.selected)) return olympusGold;
              return null;
            }),
          ),
          timePickerTheme: TimePickerThemeData(
            backgroundColor: Colors.white,
            hourMinuteColor: MaterialStateColor.resolveWith((states) {
              if (states.contains(MaterialState.selected)) {
                return olympusGold.withOpacity(0.22);
              }
              return olympusBlue.withOpacity(0.06);
            }),
            hourMinuteTextColor: MaterialStateColor.resolveWith((states) {
              if (states.contains(MaterialState.selected)) return olympusBlue;
              return Colors.grey[800]!;
            }),
            dialHandColor: olympusBlue,
            dialBackgroundColor: olympusBlue.withOpacity(0.06),
            dialTextColor: MaterialStateColor.resolveWith((states) {
              if (states.contains(MaterialState.selected)) return Colors.white;
              return olympusBlue;
            }),
            entryModeIconColor: olympusBlue,
            helpTextStyle: TextStyle(
              color: olympusBlue,
              fontWeight: FontWeight.w700,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
          ),
          textButtonTheme: TextButtonThemeData(
            style: TextButton.styleFrom(
              foregroundColor: olympusBlue,
              textStyle: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        );
      }

      await showDialog(
        context: context,
        barrierDismissible: !saving,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setDialogState) {
            final selectedDateTime = DateTime(
              selectedDate.year,
              selectedDate.month,
              selectedDate.day,
              selectedTime.hour,
              selectedTime.minute,
            );

            final participanteSelecionado = participantesSemCheckin.firstWhere(
              (p) => p['user_id']?.toString() == selectedUserId,
              orElse: () => participantesSemCheckin.first,
            );
            final tipoSelecionado = participanteSelecionado['tipo'] == 'athlete'
                ? 'Atleta'
                : participanteSelecionado['tipo'] == 'coach'
                    ? 'Técnico'
                    : 'Membro';

            return Dialog(
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 24,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(26),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(26),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(20, 18, 12, 18),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [olympusBlue, olympusLightBlue],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 54,
                            height: 54,
                            decoration: BoxDecoration(
                              color: olympusGold.withOpacity(0.14),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: olympusGold.withOpacity(0.55),
                              ),
                            ),
                            child: Icon(
                              Icons.more_time_outlined,
                              color: olympusGold,
                              size: 28,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Check-in atrasado',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 21,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  (evento['event_name'] ?? 'Sem nome')
                                      .toString(),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.86),
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            onPressed: saving
                                ? null
                                : () => Navigator.pop(dialogContext),
                            icon: const Icon(Icons.close_rounded),
                            color: Colors.white,
                          ),
                        ],
                      ),
                    ),
                    Flexible(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(18, 18, 18, 10),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: olympusBlue.withOpacity(0.14),
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.04),
                                    blurRadius: 14,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.person_outline,
                                        color: olympusGold,
                                        size: 18,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        'ATLETA / TÉCNICO',
                                        style: TextStyle(
                                          color: olympusBlue.withOpacity(0.82),
                                          fontSize: 12,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: 0.4,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  DropdownButtonFormField<String>(
                                    value: selectedUserId,
                                    isExpanded: true,
                                    decoration: InputDecoration(
                                      labelText: 'Selecione o participante',
                                      labelStyle: TextStyle(
                                        color: olympusBlue.withOpacity(0.70),
                                      ),
                                      filled: true,
                                      fillColor: Colors.white,
                                      prefixIcon: Icon(
                                        Icons.hourglass_empty_rounded,
                                        color: olympusGold,
                                      ),
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(14),
                                        borderSide: BorderSide(
                                          color: Colors.grey[200]!,
                                        ),
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(14),
                                        borderSide: BorderSide(
                                          color: olympusGold,
                                          width: 1.5,
                                        ),
                                      ),
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                        horizontal: 14,
                                        vertical: 14,
                                      ),
                                    ),
                                    icon: Icon(
                                      Icons.keyboard_arrow_down_rounded,
                                      color: olympusGold,
                                    ),
                                    items: participantesSemCheckin.map((
                                      participante,
                                    ) {
                                      final tipo =
                                          participante['tipo'] == 'athlete'
                                              ? 'Atleta'
                                              : participante['tipo'] == 'coach'
                                                  ? 'Técnico'
                                                  : 'Membro';
                                      return DropdownMenuItem<String>(
                                        value: participante['user_id'],
                                        child: Text(
                                          '${participante['nome']} • $tipo',
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: Color(0xFF24364B),
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      );
                                    }).toList(),
                                    onChanged: saving
                                        ? null
                                        : (value) {
                                            setDialogState(() {
                                              selectedUserId = value;
                                            });
                                          },
                                  ),
                                  const SizedBox(height: 10),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 10,
                                    ),
                                    decoration: BoxDecoration(
                                      color: olympusBlue.withOpacity(0.055),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.verified_user_outlined,
                                          color: olympusBlue,
                                          size: 18,
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            '$tipoSelecionado aceitou a convocação e está disponível para check-in manual.',
                                            style: TextStyle(
                                              color: olympusBlue.withOpacity(
                                                0.82,
                                              ),
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                Expanded(
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(16),
                                    onTap: saving
                                        ? null
                                        : () async {
                                            final pickedDate =
                                                await showDatePicker(
                                              context: context,
                                              initialDate: selectedDate,
                                              firstDate: DateTime(2020),
                                              lastDate: DateTime.now().add(
                                                const Duration(days: 365),
                                              ),
                                              locale: const Locale(
                                                'pt',
                                                'BR',
                                              ),
                                              builder: (context, child) {
                                                return Theme(
                                                  data: olympusPickerTheme(
                                                    context,
                                                  ),
                                                  child: child!,
                                                );
                                              },
                                            );
                                            if (pickedDate != null) {
                                              setDialogState(() {
                                                selectedDate = pickedDate;
                                              });
                                            }
                                          },
                                    child: Container(
                                      padding: const EdgeInsets.all(14),
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          colors: [
                                            olympusGold.withOpacity(0.16),
                                            olympusGold.withOpacity(0.08),
                                          ],
                                        ),
                                        borderRadius: BorderRadius.circular(16),
                                        border: Border.all(
                                          color: olympusGold.withOpacity(0.35),
                                        ),
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Icon(
                                                Icons.calendar_month_outlined,
                                                color: olympusBlue,
                                                size: 18,
                                              ),
                                              const SizedBox(width: 6),
                                              Text(
                                                'DATA',
                                                style: TextStyle(
                                                  color: olympusBlue
                                                      .withOpacity(0.72),
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w800,
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 8),
                                          Text(
                                            DateFormat(
                                              'dd/MM/yyyy',
                                              'pt_BR',
                                            ).format(selectedDate),
                                            style: TextStyle(
                                              color: olympusBlue,
                                              fontWeight: FontWeight.w800,
                                              fontSize: 16,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(16),
                                    onTap: saving
                                        ? null
                                        : () async {
                                            final pickedTime =
                                                await showTimePicker(
                                              context: context,
                                              initialTime: selectedTime,
                                              builder: (context, child) {
                                                return Theme(
                                                  data: olympusPickerTheme(
                                                    context,
                                                  ),
                                                  child: child!,
                                                );
                                              },
                                            );
                                            if (pickedTime != null) {
                                              setDialogState(() {
                                                selectedTime = pickedTime;
                                              });
                                            }
                                          },
                                    child: Container(
                                      padding: const EdgeInsets.all(14),
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          colors: [
                                            olympusBlue.withOpacity(0.10),
                                            olympusBlue.withOpacity(0.045),
                                          ],
                                        ),
                                        borderRadius: BorderRadius.circular(16),
                                        border: Border.all(
                                          color: olympusBlue.withOpacity(0.18),
                                        ),
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Icon(
                                                Icons.access_time_rounded,
                                                color: olympusBlue,
                                                size: 18,
                                              ),
                                              const SizedBox(width: 6),
                                              Text(
                                                'HORÁRIO',
                                                style: TextStyle(
                                                  color: olympusBlue
                                                      .withOpacity(0.72),
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w800,
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 8),
                                          Text(
                                            selectedTime.format(context),
                                            style: TextStyle(
                                              color: olympusBlue,
                                              fontWeight: FontWeight.w800,
                                              fontSize: 16,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: Colors.grey[100],
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: Colors.grey[300]!),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.info_outline,
                                    color: olympusBlue,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      'Será gravado no banco como: ${DateFormat('dd/MM/yyyy HH:mm', 'pt_BR').format(selectedDateTime)}',
                                      style: TextStyle(
                                        color: Colors.grey[700],
                                        fontWeight: FontWeight.w600,
                                        fontSize: 12,
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
                    Container(
                      padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.06),
                            blurRadius: 18,
                            offset: const Offset(0, -4),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: saving
                                  ? null
                                  : () => Navigator.pop(dialogContext),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.grey[700],
                                side: BorderSide(color: Colors.grey[300]!),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              child: const Text(
                                'Cancelar',
                                style: TextStyle(fontWeight: FontWeight.w800),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 2,
                            child: ElevatedButton.icon(
                              onPressed: saving || selectedUserId == null
                                  ? null
                                  : () async {
                                      setDialogState(() {
                                        saving = true;
                                      });

                                      try {
                                        await _supabase
                                            .from('checkins')
                                            .upsert({
                                          'event_id': eventId,
                                          'user_id': selectedUserId,
                                          // IMPORTANTE: a tela de Estatísticas só considera presença
                                          // quando check_in_status tem um valor reconhecido como realizado.
                                          'check_in_status': 'realizado',
                                          // Horário histórico escolhido pelo admin.
                                          'created_at': selectedDateTime
                                              .toIso8601String(),
                                        }, onConflict: 'event_id,user_id');

                                        if (mounted) {
                                          Navigator.pop(dialogContext);
                                          await _buscarCheckinInfo();
                                          ScaffoldMessenger.of(
                                            context,
                                          ).showSnackBar(
                                            const SnackBar(
                                              content: Text(
                                                '✅ Check-in atrasado registrado com sucesso!',
                                              ),
                                              backgroundColor: Colors.green,
                                            ),
                                          );
                                        }
                                      } catch (e) {
                                        setDialogState(() {
                                          saving = false;
                                        });
                                        if (mounted) {
                                          ScaffoldMessenger.of(
                                            context,
                                          ).showSnackBar(
                                            SnackBar(
                                              content: Text(
                                                '❌ Erro ao registrar check-in: $e',
                                              ),
                                              backgroundColor: Colors.red,
                                            ),
                                          );
                                        }
                                      }
                                    },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: olympusGold,
                                foregroundColor: olympusBlue,
                                disabledBackgroundColor: Colors.grey[300],
                                disabledForegroundColor: Colors.grey[600],
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                elevation: 4,
                                shadowColor: olympusGold.withOpacity(0.35),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              icon: saving
                                  ? SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: olympusBlue,
                                      ),
                                    )
                                  : const Icon(Icons.check_circle_outline),
                              label: Text(
                                saving ? 'Salvando...' : 'Registrar',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
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
            );
          },
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao abrir check-in atrasado: $e'),
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
      totalSets,
      (i) => TextEditingController(),
    );
    final opponentControllers = List<TextEditingController>.generate(
      totalSets,
      (i) => TextEditingController(),
    );
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
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
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
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
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
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                            borderSide: BorderSide(
                                              color: olympusBlue.withOpacity(
                                                0.3,
                                              ),
                                            ),
                                          ),
                                          enabledBorder: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                            borderSide: BorderSide(
                                              color: olympusBlue.withOpacity(
                                                0.3,
                                              ),
                                            ),
                                          ),
                                          focusedBorder: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                            borderSide: BorderSide(
                                              color: olympusGold,
                                              width: 2,
                                            ),
                                          ),
                                          filled: true,
                                          fillColor: olympusBlue.withOpacity(
                                            0.05,
                                          ),
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
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                            borderSide: BorderSide(
                                              color: Colors.grey[300]!,
                                            ),
                                          ),
                                          enabledBorder: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                            borderSide: BorderSide(
                                              color: Colors.grey[300]!,
                                            ),
                                          ),
                                          focusedBorder: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                            borderSide: BorderSide(
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
                                .map(
                                  (c) => c.text.isNotEmpty
                                      ? int.tryParse(c.text) ?? 0
                                      : null,
                                )
                                .toList();
                            final opponentSets = opponentControllers
                                .map(
                                  (c) => c.text.isNotEmpty
                                      ? int.tryParse(c.text) ?? 0
                                      : null,
                                )
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
                                    content: Text(
                                      'Preencha todos os sets! '
                                      'Melhor de $totalSets: vence quem ganhar $setsNeededToWin sets primeiro.',
                                    ),
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
                                      'Placar inserido! Vitória: $winner ($olympusWins x $opponentWins)',
                                    ),
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
        final mesNome = DateFormat(
          'MMMM',
          'pt_BR',
        ).format(DateTime(int.parse(ano), mes));
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
    final branding = OlympusBrandingController.instance.branding;
    final primary = branding.primaryColor;
    final onPrimary = Theme.of(context).colorScheme.onPrimary;
    // ✅ NOVO: Verifica permissão antes de mostrar a tela
    if (_checkingPermission) {
      return Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (!_hasPermission) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Agenda'),
          backgroundColor: primary,
          foregroundColor: onPrimary,
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.lock_outline, size: 80, color: Colors.grey[400]),
              const SizedBox(height: 24),
              Text(
                'Acesso Restrito',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[700],
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Você não tem permissão para acessar a agenda.',
                style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              ElevatedButton(
                onPressed: () {
                  Navigator.of(context).pop();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: primary,
                  foregroundColor: onPrimary,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 12,
                  ),
                ),
                child: const Text('Voltar'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Minha Agenda',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: primary,
        foregroundColor: onPrimary,
        iconTheme: IconThemeData(color: onPrimary),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadingEvents ? null : _refreshEventos,
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
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  primary,
                  Color.lerp(primary, branding.backgroundColor, 0.18)!,
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
                    SizedBox(width: 104, child: _buildEventosPassadosButton()),
                    const SizedBox(width: 12),
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
                            value: 'Todos',
                            child: Text('Todos'),
                          ),
                          DropdownMenuItem(
                            value: 'masculino',
                            child: Text('Masculino'),
                          ),
                          DropdownMenuItem(
                            value: 'feminino',
                            child: Text('Feminino'),
                          ),
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
          if (_loadingEvents && _eventos.isNotEmpty)
            LinearProgressIndicator(
              minHeight: 3,
              color: olympusGold,
              backgroundColor: Color(0xFFE8EEF5),
            ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.error_outline,
                              size: 48,
                              color: Colors.red[300],
                            ),
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
                                Icon(
                                  Icons.event_busy,
                                  size: 64,
                                  color: Colors.grey[400],
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  _mostrarEventosPassados
                                      ? 'Nenhum evento passado encontrado'
                                      : 'Nenhum evento futuro encontrado',
                                  style: TextStyle(
                                    fontSize: 18,
                                    color: Colors.grey[600],
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  _mostrarEventosPassados
                                      ? 'Volte para Futuros para ver os próximos eventos'
                                      : 'Clique no + para adicionar um evento',
                                  style: TextStyle(color: Colors.grey[500]),
                                ),
                              ],
                            ),
                          )
                        : RefreshIndicator(
                            onRefresh: _refreshEventos,
                            child: ListView.builder(
                              padding: const EdgeInsets.all(16),
                              itemCount: _eventosVisiveisCount +
                                  (_temMaisEventos ? 1 : 0),
                              itemBuilder: (context, index) {
                                if (index == _eventosVisiveisCount) {
                                  return Padding(
                                    padding: const EdgeInsets.only(
                                        top: 4, bottom: 20),
                                    child: OutlinedButton.icon(
                                      onPressed: () {
                                        setState(() {
                                          _visibleEventLimit += _eventPageSize;
                                        });
                                      },
                                      icon:
                                          const Icon(Icons.expand_more_rounded),
                                      label: Text(
                                        'Carregar mais eventos (${_eventosFiltrados.length - _eventosVisiveisCount})',
                                      ),
                                    ),
                                  );
                                }
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
                                  evento['event_type'] ?? '',
                                );
                                final eventType = evento['event_type'] ?? '';
                                final normalizedEventType =
                                    eventType.toString().toLowerCase().trim();
                                final showVerConvocados = allowCheckin ||
                                    normalizedEventType == 'treino' ||
                                    normalizedEventType == 'amistoso' ||
                                    normalizedEventType == 'campeonato' ||
                                    normalizedEventType == 'liga' ||
                                    normalizedEventType == 'campeonato/liga';
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
                                                      BorderRadius.circular(
                                                    12,
                                                  ),
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
                                            if (_canUseAgendaAction(
                                                    'edit_event') ||
                                                _canUseAgendaAction(
                                                    'insert_score') ||
                                                _canUseAgendaAction(
                                                    'view_called_up') ||
                                                _canUseAgendaAction(
                                                  'export_game_data',
                                                ) ||
                                                _canUseAgendaAction(
                                                    'delete_event') ||
                                                _isAdmin)
                                              PopupMenuButton<String>(
                                                icon: Icon(
                                                  Icons.more_vert,
                                                  color: Colors.grey[600],
                                                ),
                                                onSelected: (value) {
                                                  if (value == 'editar' &&
                                                      _canUseAgendaAction(
                                                        'edit_event',
                                                      )) {
                                                    _editarEvento(evento);
                                                  } else if (value ==
                                                          'placar' &&
                                                      _canUseAgendaAction(
                                                        'insert_score',
                                                      )) {
                                                    _inserirPlacar(evento);
                                                  } else if (value ==
                                                          'checkin' &&
                                                      _canUseAgendaAction(
                                                        'view_called_up',
                                                      )) {
                                                    _mostrarCheckinDetalhes(
                                                        evento);
                                                  } else if (value ==
                                                          'status_checkin' &&
                                                      _canUseAgendaAction(
                                                        'view_called_up',
                                                      )) {
                                                    _mostrarStatusCheckin(
                                                        evento);
                                                  } else if (value ==
                                                          'late_checkin' &&
                                                      _isAdmin) {
                                                    _realizarCheckinAtrasado(
                                                        evento);
                                                  } else if (value ==
                                                          'change_acceptance_status' &&
                                                      _isAdmin) {
                                                    _alterarStatusAceiteAtleta(
                                                        evento);
                                                  } else if (value ==
                                                          'exportar' &&
                                                      _canUseAgendaAction(
                                                        'export_game_data',
                                                      )) {
                                                    _exportarCaronasPdf(evento);
                                                  } else if (value ==
                                                          'excluir' &&
                                                      _canUseAgendaAction(
                                                        'delete_event',
                                                      )) {
                                                    _excluirEvento(evento);
                                                  }
                                                },
                                                itemBuilder: (context) {
                                                  final items =
                                                      <PopupMenuItem<String>>[];
                                                  if (_canUseAgendaAction(
                                                    'edit_event',
                                                  )) {
                                                    items.add(
                                                      const PopupMenuItem(
                                                        value: 'editar',
                                                        child: Row(
                                                          children: [
                                                            Icon(
                                                              Icons.edit,
                                                              size: 18,
                                                              color:
                                                                  Colors.blue,
                                                            ),
                                                            SizedBox(width: 8),
                                                            Text(
                                                                'Editar evento'),
                                                          ],
                                                        ),
                                                      ),
                                                    );
                                                  }
                                                  if ((eventType ==
                                                              'amistoso' ||
                                                          eventType ==
                                                              'campeonato') &&
                                                      _canUseAgendaAction(
                                                        'insert_score',
                                                      )) {
                                                    items.add(
                                                      PopupMenuItem(
                                                        value: 'placar',
                                                        child: Row(
                                                          children: [
                                                            Icon(
                                                              Icons.score,
                                                              size: 18,
                                                              color:
                                                                  olympusGold,
                                                            ),
                                                            SizedBox(width: 8),
                                                            Text(
                                                              hasPlacar
                                                                  ? 'Editar placar'
                                                                  : 'Inserir placar',
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                    );
                                                  }
                                                  if (showVerConvocados &&
                                                      _canUseAgendaAction(
                                                        'view_called_up',
                                                      )) {
                                                    items.add(
                                                      PopupMenuItem(
                                                        value: 'checkin',
                                                        child: Row(
                                                          children: [
                                                            Icon(
                                                              Icons
                                                                  .people_outline,
                                                              size: 18,
                                                              color:
                                                                  Colors.green,
                                                            ),
                                                            SizedBox(width: 8),
                                                            Text(
                                                                'Ver convocados'),
                                                          ],
                                                        ),
                                                      ),
                                                    );
                                                  }
                                                  if (allowCheckin &&
                                                      _canUseAgendaAction(
                                                        'view_called_up',
                                                      )) {
                                                    items.add(
                                                      PopupMenuItem(
                                                        value: 'status_checkin',
                                                        child: Row(
                                                          children: [
                                                            Icon(
                                                              Icons
                                                                  .check_circle_outline,
                                                              size: 18,
                                                              color:
                                                                  olympusGold,
                                                            ),
                                                            SizedBox(width: 8),
                                                            Text(
                                                                'Ver status check-in'),
                                                          ],
                                                        ),
                                                      ),
                                                    );
                                                  }
                                                  // ✅ ADMIN: sempre mostra Check-in atrasado no menu,
                                                  // mesmo se allow_checkin estiver false ou o prazo já passou.
                                                  if (_isAdmin) {
                                                    items.add(
                                                      PopupMenuItem(
                                                        value: 'late_checkin',
                                                        child: Row(
                                                          children: [
                                                            Icon(
                                                              Icons
                                                                  .more_time_outlined,
                                                              size: 18,
                                                              color:
                                                                  olympusBlue,
                                                            ),
                                                            SizedBox(width: 8),
                                                            Text(
                                                                'Check-in atrasado'),
                                                          ],
                                                        ),
                                                      ),
                                                    );
                                                  }
                                                  if (_isAdmin) {
                                                    items.add(
                                                      PopupMenuItem(
                                                        value:
                                                            'change_acceptance_status',
                                                        child: Row(
                                                          children: [
                                                            Icon(
                                                              Icons
                                                                  .manage_accounts_outlined,
                                                              size: 18,
                                                              color:
                                                                  olympusBlue,
                                                            ),
                                                            SizedBox(width: 8),
                                                            Text(
                                                                'Alterar aceite'),
                                                          ],
                                                        ),
                                                      ),
                                                    );
                                                  }
                                                  if (_canUseAgendaAction(
                                                    'export_game_data',
                                                  )) {
                                                    items.add(
                                                      PopupMenuItem(
                                                        value: 'exportar',
                                                        child: Row(
                                                          children: [
                                                            Icon(
                                                              Icons
                                                                  .file_download,
                                                              size: 18,
                                                              color:
                                                                  Colors.green,
                                                            ),
                                                            SizedBox(width: 8),
                                                            Text(
                                                              'Exportar caronas em PDF',
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                    );
                                                  }
                                                  if (_canUseAgendaAction(
                                                    'delete_event',
                                                  )) {
                                                    items.add(
                                                      PopupMenuItem(
                                                        value: 'excluir',
                                                        child: Row(
                                                          children: [
                                                            Icon(
                                                              Icons
                                                                  .delete_outline,
                                                              size: 18,
                                                              color: Colors.red,
                                                            ),
                                                            SizedBox(width: 8),
                                                            Text(
                                                              'Excluir evento',
                                                              style: TextStyle(
                                                                color:
                                                                    Colors.red,
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                    );
                                                  }
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
                                              _formatarHora(
                                                  evento['event_time']),
                                              style: TextStyle(
                                                  color: Colors.grey[700]),
                                            ),
                                          ],
                                        ),
                                        // ✅ ENDEREÇO MOVIDO PARA ABAIXO DO RELÓGIO
                                        if (enderecoCompleto != null) ...[
                                          const SizedBox(height: 4),
                                          EventAddressLink(
                                            event: evento,
                                            address: enderecoCompleto,
                                            iconColor: Colors.grey[700],
                                            style: TextStyle(
                                              color: Colors.grey[700],
                                              fontSize: 13,
                                            ),
                                          ),
                                        ],
                                        Row(
                                          children: [
                                            Icon(
                                              Icons.people_outline,
                                              size: 16,
                                              color: olympusGold,
                                            ),
                                            const SizedBox(width: 8),
                                            Text(
                                              '$totalConvocados atleta${totalConvocados == 1 ? '' : 's'} convocado${totalConvocados == 1 ? '' : 's'}',
                                              style: TextStyle(
                                                color: olympusBlue,
                                                fontWeight: FontWeight.w600,
                                                fontSize: 14,
                                              ),
                                            ),
                                          ],
                                        ),
                                        if ((quantidades['technicians'] ?? 0) >
                                            0) ...[
                                          const SizedBox(height: 4),
                                          Row(
                                            children: [
                                              Icon(
                                                Icons.sports_rounded,
                                                size: 16,
                                                color: olympusGold,
                                              ),
                                              const SizedBox(width: 8),
                                              Text(
                                                '${quantidades['technicians']} treinador${quantidades['technicians'] == 1 ? '' : 'es'} vinculado${quantidades['technicians'] == 1 ? '' : 's'} • sem check-in',
                                                style: TextStyle(
                                                  color: olympusGold,
                                                  fontWeight: FontWeight.w700,
                                                  fontSize: 12,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
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
                                        if (normalizedEventType ==
                                            'treino') ...[
                                          const SizedBox(height: 12),
                                          SizedBox(
                                            width: double.infinity,
                                            child: OutlinedButton.icon(
                                              onPressed: () =>
                                                  _mostrarPlanejamentoTreino(
                                                      evento),
                                              icon: const Icon(
                                                Icons.menu_book_outlined,
                                              ),
                                              label: const Text(
                                                  'Ver planejamento'),
                                              style: OutlinedButton.styleFrom(
                                                foregroundColor: olympusBlue,
                                                side: BorderSide(
                                                  color: olympusBlue
                                                      .withOpacity(0.35),
                                                ),
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                  vertical: 12,
                                                ),
                                              ),
                                            ),
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
                  padding: const EdgeInsets.symmetric(
                    vertical: 8,
                    horizontal: 12,
                  ),
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
            Icon(
              icone,
              size: 14,
              color: selecionado ? corBase : Colors.grey[600],
            ),
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
                      style: TextStyle(
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
                      _formatarHora(evento['event_time']),
                    ),
                    _buildDetailRow(
                      Icons.category,
                      'Tipo',
                      evento['event_type'] ?? '',
                    ),
                    if (evento['gender'] != null &&
                        evento['gender'].toString().isNotEmpty)
                      _buildDetailRow(Icons.people, 'Gênero', evento['gender']),
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
                      Text(
                        'Localização',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: olympusBlue,
                        ),
                      ),
                      const SizedBox(height: 8),
                      EventAddressLink(
                        event: evento,
                        address: EventMapLauncher.buildAddress(evento),
                        iconColor: olympusGold,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: olympusBlue,
                        ),
                        maxLines: 3,
                      ),
                      _buildDetailRow(
                        Icons.map,
                        'Bairro',
                        evento['neighborhood'] ?? '',
                      ),
                      _buildDetailRow(
                        Icons.home,
                        'Cidade',
                        '${evento['city']}, ${evento['state']}',
                      ),
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
                  style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                ),
                Text(
                  value,
                  style: TextStyle(
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

  Widget _buildEventosPassadosButton() {
    final count = _getEventosPassadosCount();

    return SizedBox(
      height: 72,
      child: ElevatedButton(
        onPressed: _alternarEventosPassados,
        style: ElevatedButton.styleFrom(
          backgroundColor: _mostrarEventosPassados ? olympusGold : Colors.white,
          foregroundColor: olympusBlue,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
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
                constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
                padding: const EdgeInsets.symmetric(horizontal: 5),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: olympusGold,
                  borderRadius: BorderRadius.circular(999),
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
                Icon(icon, size: 16, color: olympusGold),
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
                hint: Text(hint, style: TextStyle(color: Colors.grey[600])),
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
                Icon(icon, size: 16, color: olympusGold),
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
