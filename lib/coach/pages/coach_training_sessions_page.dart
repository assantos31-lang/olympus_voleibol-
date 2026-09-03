import 'dart:async';
import 'dart:convert';
import 'dart:math' show asin, cos, sin, sqrt;

import 'package:flutter/material.dart';
import '../../theme/olympus_theme.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/permission_service.dart';
import '../../services/technical_staff_service.dart';
import '../../widgets/event_address_link.dart';
import 'coach_championship_scout_page.dart' as championship_scout;
import 'coach_quick_athlete_evaluation_page.dart';
import 'coach_training_plan_detail_page.dart';
import 'coach_training_planning_dashboard_page.dart';
import 'training_plan_readonly_sheet.dart';

export 'coach_quick_athlete_evaluation_page.dart';
export 'coach_training_plan_detail_page.dart';

class CoachTrainingSessionsPage extends StatefulWidget {
  final String initialTipoEvento;
  final bool lockTipoEvento;
  final String? pageTitle;
  final bool agendaMode;

  const CoachTrainingSessionsPage({
    super.key,
    this.initialTipoEvento = 'treino',
    this.lockTipoEvento = false,
    this.pageTitle,
    this.agendaMode = false,
  });

  @override
  State<CoachTrainingSessionsPage> createState() =>
      _CoachTrainingSessionsPageState();
}

class _CoachTrainingSessionsPageState extends State<CoachTrainingSessionsPage> {
  final SupabaseClient _supabase = Supabase.instance.client;

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
  bool _showAllPendingPlans = false;
  bool _mostrarTodosPlanejamentos = false;
  bool _showPastEvents = false;
  bool _canViewConfirmations = false;
  TechnicalStaffAssignment? _technicalAssignment;
  Set<String> _visibleCoachIds = const {};
  Map<String, String> _visibleCoachNames = const {};
  RealtimeChannel? _planningRealtimeChannel;
  List<Map<String, dynamic>> _treinos = [];
  List<Map<String, dynamic>> _treinosFiltrados = [];

  String _filtroMes = '';
  String _filtroStatus = 'todos';
  String _filtroCoachId = 'todos';
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
    _initializeTechnicalScope();
    _setupPlanningRealtime();
  }

  Future<void> _initializeTechnicalScope() async {
    try {
      final service = TechnicalStaffService(client: _supabase);
      _technicalAssignment = await service.loadCurrentAssignment();
      if (!widget.agendaMode && _technicalAssignment?.isCoordinator == true) {
        _mostrarTodosPlanejamentos = true;
      }
      final currentUserId = _supabase.auth.currentUser?.id;
      if (currentUserId != null) {
        final actions = await PermissionService().getAgendaActionPermissions(
          currentUserId,
        );
        _canViewConfirmations = actions['ver_convocados'] == true;
        _visibleCoachIds = {currentUserId};
        if (_technicalAssignment?.isCoordinator == true) {
          final values = await Future.wait([
            service.loadAssignments(),
            service.loadAvailableProfiles(),
          ]);
          final assignments = values[0] as List<TechnicalStaffAssignment>;
          final profiles = values[1] as List<Map<String, dynamic>>;
          _visibleCoachIds = {
            currentUserId,
            ...assignments
                .where((item) => item.supervisorUserId == currentUserId)
                .map((item) => item.userId),
          };
          _visibleCoachNames = {
            for (final profile in profiles)
              if (_visibleCoachIds.contains((profile['id'] ?? '').toString()))
                (profile['id'] ?? '').toString():
                    (profile['full_name'] ?? profile['email'] ?? 'Treinador')
                        .toString()
                        .trim(),
          };
        }
      }
    } catch (_) {
      // Mantém o escopo pessoal para cadastros técnicos antigos.
    }
    await _buscarTreinosDoTecnico();
  }

  void _setupPlanningRealtime() {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null || _planningRealtimeChannel != null) return;

    _planningRealtimeChannel = _supabase
        .channel('coach-training-sessions-plans-$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'training_plan_blocks',
          callback: (_) => _buscarTreinosDoTecnico(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'training_plans',
          callback: (_) => _buscarTreinosDoTecnico(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'events',
          callback: (_) => _buscarTreinosDoTecnico(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'convocations',
          callback: (_) => _buscarTreinosDoTecnico(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'technical_staff_assignments',
          callback: (_) => _initializeTechnicalScope(),
        )
        .subscribe();
  }

  @override
  void dispose() {
    final channel = _planningRealtimeChannel;
    if (channel != null) {
      _supabase.removeChannel(channel);
    }
    super.dispose();
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
    if (raw.contains('amistoso')) return 'amistoso';
    if (raw == 'jogo' || raw.contains('partida')) return 'amistoso';
    if (raw.contains('liga')) return 'liga';

    return raw;
  }

  bool _isTipoEventoSuportado(dynamic value) {
    final tipo = _normalizarTipoEvento(value);
    return tipo == 'treino' ||
        tipo == 'campeonato' ||
        tipo == 'amistoso' ||
        tipo == 'liga';
  }

  bool _isCoachEventRole(dynamic value) {
    final role = (value ?? '').toString().trim().toLowerCase();
    return role == 'coach' ||
        role == 'treinador' ||
        role == 'tecnico' ||
        role == 'técnico';
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

  String _normalizarStatusConvocacao(dynamic status) {
    final value = (status ?? '').toString().trim().toLowerCase();
    if (['accepted', 'aceito', 'aceitou', 'confirmado'].contains(value)) {
      return 'accepted';
    }
    if (['rejected', 'recusado', 'recusou'].contains(value)) {
      return 'rejected';
    }
    return 'pending';
  }

  Future<Map<String, Map<String, int>>> _buscarContagensAtletasPorEvento(
    List<String> eventIds,
  ) async {
    if (eventIds.isEmpty) return {};
    final counts = <String, Map<String, int>>{
      for (final eventId in eventIds)
        eventId: {
          'accepted': 0,
          'rejected': 0,
          'pending': 0,
        },
    };
    final response = await _supabase
        .from('convocations')
        .select('event_id, status, event_role')
        .inFilter('event_id', eventIds);
    for (final row in List<Map<String, dynamic>>.from(response as List)) {
      final role =
          (row['event_role'] ?? 'athlete').toString().trim().toLowerCase();
      if (role == 'coach') continue;
      final eventId = (row['event_id'] ?? '').toString();
      final eventCounts = counts[eventId];
      if (eventCounts == null) continue;
      final status = _normalizarStatusConvocacao(row['status']);
      eventCounts[status] = (eventCounts[status] ?? 0) + 1;
    }
    return counts;
  }

  Future<Map<String, Map<String, int>>> _buscarContagensComFallback(
    List<String> eventIds,
  ) async {
    try {
      return await _buscarContagensAtletasPorEvento(eventIds);
    } catch (e) {
      debugPrint('Erro ao carregar convocados pela RPC: $e');
      return {
        for (final eventId in eventIds)
          eventId: {'accepted': 0, 'rejected': 0, 'pending': 0},
      };
    }
  }

  Future<Set<String>> _buscarEventosComPlanejamento(
    List<String> eventIds,
  ) async {
    if (eventIds.isEmpty) return <String>{};
    final rows = await _supabase
        .from('training_plan_blocks')
        .select('event_id')
        .inFilter('event_id', eventIds);
    return List<Map<String, dynamic>>.from(rows as List)
        .map((row) => (row['event_id'] ?? '').toString())
        .where((id) => id.isNotEmpty)
        .toSet();
  }

  Future<Map<String, Set<String>>> _buscarAutoresPlanejamento(
    List<String> eventIds,
  ) async {
    if (eventIds.isEmpty) return {};
    final rows = await _supabase
        .from('training_plan_blocks')
        .select('event_id, coach_id')
        .inFilter('event_id', eventIds);
    final result = <String, Set<String>>{};
    for (final row in List<Map<String, dynamic>>.from(rows as List)) {
      final eventId = (row['event_id'] ?? '').toString();
      final coachId = (row['coach_id'] ?? '').toString();
      if (eventId.isEmpty || coachId.isEmpty) continue;
      result.putIfAbsent(eventId, () => <String>{}).add(coachId);
    }
    return result;
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

      // Consultas separadas são menores e mais estáveis no celular do que um
      // único embed grande de convocations + events.
      final response = await _supabase
          .from('convocations')
          .select('id, event_id, status, justification, event_role')
          .eq('user_id', user.id)
          .timeout(const Duration(seconds: 15));

      final ownEventIds = List<Map<String, dynamic>>.from(response)
          .where((row) => _isCoachEventRole(row['event_role']))
          .map((row) => (row['event_id'] ?? '').toString())
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList();

      final plannedEventIds = <String>{};
      if (_mostrarTodosPlanejamentos) {
        try {
          var plannedQuery = _supabase
              .from('training_plan_blocks')
              .select('event_id, coach_id');
          if (_visibleCoachIds.isNotEmpty) {
            plannedQuery =
                plannedQuery.inFilter('coach_id', _visibleCoachIds.toList());
          }
          final plannedRows =
              await plannedQuery.timeout(const Duration(seconds: 15));

          for (final row in List<Map<String, dynamic>>.from(plannedRows)) {
            final eventId = (row['event_id'] ?? '').toString();
            if (eventId.isNotEmpty) plannedEventIds.add(eventId);
          }
        } catch (_) {
          // Se a leitura ampla ainda não estiver liberada no Supabase,
          // mantém a tela funcionando com os próprios treinos.
        }
      }

      final coordinatorEventIds = <String>{};
      final assignment = _technicalAssignment;
      if (_mostrarTodosPlanejamentos && assignment?.isCoordinator == true) {
        try {
          final visibleConvocations = await _supabase
              .from('convocations')
              .select('event_id')
              .eq('event_role', 'coach')
              .inFilter('user_id', _visibleCoachIds.toList())
              .timeout(const Duration(seconds: 15));
          for (final row
              in List<Map<String, dynamic>>.from(visibleConvocations)) {
            final eventId = (row['event_id'] ?? '').toString();
            if (eventId.isNotEmpty) coordinatorEventIds.add(eventId);
          }
        } catch (_) {
          // A política do Supabase continua sendo a fonte final de acesso.
        }
      }

      final eventIds = <String>{
        ...ownEventIds,
        if (_mostrarTodosPlanejamentos) ...plannedEventIds,
        if (_mostrarTodosPlanejamentos) ...coordinatorEventIds,
      }.toList();

      final ownConvocationByEventId = <String, Map<String, dynamic>>{};
      for (final item in List<Map<String, dynamic>>.from(response)) {
        if (!_isCoachEventRole(item['event_role'])) continue;
        final eventId = (item['event_id'] ?? '').toString();
        if (eventId.isNotEmpty) ownConvocationByEventId[eventId] = item;
      }

      final coachIdsByEventId = <String, Set<String>>{};
      for (final eventId in ownEventIds) {
        coachIdsByEventId.putIfAbsent(eventId, () => <String>{}).add(user.id);
      }

      if (eventIds.isNotEmpty) {
        try {
          final assignedCoachRows = await _supabase
              .from('convocations')
              .select('event_id, user_id')
              .eq('event_role', 'coach')
              .inFilter('event_id', eventIds)
              .timeout(const Duration(seconds: 15));

          for (final row
              in List<Map<String, dynamic>>.from(assignedCoachRows)) {
            final eventId = (row['event_id'] ?? '').toString();
            final coachId = (row['user_id'] ?? '').toString();
            if (eventId.isEmpty || coachId.isEmpty) continue;
            if (_mostrarTodosPlanejamentos &&
                assignment?.isCoordinator == true &&
                !_visibleCoachIds.contains(coachId)) {
              continue;
            }
            coachIdsByEventId
                .putIfAbsent(eventId, () => <String>{})
                .add(coachId);
          }
        } catch (_) {
          // Se as convocações não puderem ser lidas agora, mantém
          // pelo menos o treinador logado nos próprios treinos.
        }
      }

      final coachIds = coachIdsByEventId.values
          .expand((ids) => ids)
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList();
      final coachNameById = <String, String>{};
      if (coachIds.isNotEmpty) {
        try {
          final profileRows = await _supabase
              .from('profiles')
              .select('id, full_name')
              .inFilter('id', coachIds)
              .timeout(const Duration(seconds: 15));

          for (final profile in List<Map<String, dynamic>>.from(profileRows)) {
            final id = (profile['id'] ?? '').toString();
            final name = (profile['full_name'] ?? '').toString().trim();
            if (id.isNotEmpty && name.isNotEmpty) {
              coachNameById[id] = name;
            }
          }
        } catch (_) {}
      }

      final eventsById = <String, Map<String, dynamic>>{};
      if (eventIds.isNotEmpty) {
        final eventRows = await _supabase.from('events').select('''
              id, event_name, event_type, event_date, event_time,
              event_end_time, gender, championship_name, street,
              street_number, neighborhood, city, state, cep, latitude,
              longitude, allow_checkin, enable_ride_logistics
            ''').inFilter('id', eventIds).timeout(const Duration(seconds: 15));
        for (final row in List<Map<String, dynamic>>.from(eventRows)) {
          eventsById[(row['id'] ?? '').toString()] = row;
        }
      }

      final convocacoesParaAceitar = <String>[];

      final treinos = <Map<String, dynamic>>[];
      for (final eventId in eventIds) {
        final rawEvent = eventsById[eventId];
        if (rawEvent == null) continue;

        final event = Map<String, dynamic>.from(rawEvent);
        final eventType =
            (event['event_type'] ?? '').toString().toLowerCase().trim();

        if (!_isTipoEventoSuportado(eventType)) continue;

        final ownConvocation = ownConvocationByEventId[eventId];
        final isOwnCoachEvent = ownConvocation != null;

        if (_mostrarTodosPlanejamentos &&
            !isOwnCoachEvent &&
            assignment?.isCoordinator != true) {
          final normalizedType = _normalizarTipoEvento(eventType);
          if (normalizedType != 'treino' ||
              !plannedEventIds.contains(eventId)) {
            continue;
          }
        }

        event['normalized_event_type'] = _normalizarTipoEvento(eventType);
        event['is_own_coach_event'] = isOwnCoachEvent;
        event['view_only_planning'] =
            !isOwnCoachEvent && assignment?.isCoordinator != true;
        final eventCoachIds =
            coachIdsByEventId[eventId]?.where((id) => id.isNotEmpty).toList() ??
                <String>[];
        final eventCoachNames = eventCoachIds
            .map((id) => coachNameById[id] ?? 'Treinador')
            .where((name) => name.trim().isNotEmpty)
            .toSet()
            .toList();
        event['coach_ids'] = eventCoachIds;
        event['coach_names'] = eventCoachNames;
        event['coach_options'] = eventCoachIds
            .map((id) => {
                  'id': id,
                  'name': coachNameById[id] ?? 'Treinador',
                })
            .toList();

        if (isOwnCoachEvent) {
          event['convocation_id'] = ownConvocation['id'];
          final currentStatus =
              _normalizarStatusConvocacao(ownConvocation['status']);
          event['convocation_status'] = 'accepted';
          if (currentStatus != 'accepted') {
            final convocationId = (ownConvocation['id'] ?? '').toString();
            if (convocationId.isNotEmpty) {
              convocacoesParaAceitar.add(convocationId);
            }
          }
          event['justification'] = ownConvocation['justification'];
        } else {
          event['convocation_status'] = 'view_only';
          event['justification'] = null;
        }
        treinos.add(event);
      }

      if (convocacoesParaAceitar.isNotEmpty) {
        await _supabase
            .from('convocations')
            .update({'status': 'accepted', 'justification': null}).inFilter(
                'id', convocacoesParaAceitar);
      }

      final loadedEventIds = treinos.map((e) => e['id'].toString()).toList();
      final extraData = await Future.wait([
        _buscarContagensComFallback(loadedEventIds),
        _buscarEventosComPlanejamento(loadedEventIds),
        _buscarAutoresPlanejamento(loadedEventIds),
      ]);
      final athleteCounts = extraData[0] as Map<String, Map<String, int>>;
      final eventsWithPlanning = extraData[1] as Set<String>;
      final planAuthorsByEvent = extraData[2] as Map<String, Set<String>>;

      for (final treino in treinos) {
        final id = treino['id'].toString();
        treino['athlete_status_counts'] =
            athleteCounts[id] ?? {'accepted': 0, 'rejected': 0, 'pending': 0};
        treino['has_planning'] = eventsWithPlanning.contains(id);
        treino['plan_author_ids'] =
            (planAuthorsByEvent[id] ?? const <String>{}).toList();
      }

      if (loadedEventIds.isNotEmpty) {
        try {
          final workflowRows = await _supabase
              .from('training_planning_workflows')
              .select('event_id, status, assigned_coach_id')
              .inFilter('event_id', loadedEventIds);
          final workflowByEvent = <String, Map<String, dynamic>>{
            for (final row in List<Map<String, dynamic>>.from(workflowRows))
              (row['event_id'] ?? '').toString(): row,
          };
          for (final treino in treinos) {
            final workflow = workflowByEvent[(treino['id'] ?? '').toString()];
            treino['planning_status'] = workflow?['status'] ?? 'pending';
            treino['assigned_planning_coach_id'] =
                workflow?['assigned_coach_id'];
          }
        } catch (_) {
          for (final treino in treinos) {
            treino['planning_status'] =
                treino['has_planning'] == true ? 'published' : 'pending';
          }
        }
      }

      treinos.sort(
        (a, b) => _parseEventDateTime(a).compareTo(_parseEventDateTime(b)),
      );

      if (!mounted) return;
      setState(() {
        _treinos = treinos;
        if (_filtroCoachId != 'todos' &&
            !_treinos.any((treino) =>
                ((treino['coach_ids'] as List?) ?? const [])
                    .map((id) => id.toString())
                    .contains(_filtroCoachId))) {
          _filtroCoachId = 'todos';
        }
        _aplicarFiltros();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e is TimeoutException
            ? 'A conexão demorou mais que o esperado. Toque em atualizar para tentar novamente.'
            : 'Não foi possível carregar os treinos agora. Verifique sua conexão e tente novamente.';
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
    final hora = _formatarHora(evento['event_time']);

    if (data.isEmpty && hora.isEmpty) return 'Sem data definida';
    if (data.isEmpty) return hora;
    if (hora.isEmpty) return data;
    return '$data • $hora';
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

  Future<void> _alternarFontePlanejamentos(bool mostrarTodos) async {
    if (_mostrarTodosPlanejamentos == mostrarTodos) return;

    setState(() {
      _mostrarTodosPlanejamentos = mostrarTodos;
      _filtroStatus = 'todos';
      _filtroCoachId = 'todos';
      _showAllPendingPlans = false;
    });

    await _buscarTreinosDoTecnico();
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

    final baseResumo = _getTreinosBaseFiltro().where((evento) {
      if (!_mostrarTodosPlanejamentos || _filtroCoachId == 'todos') {
        return true;
      }

      final coachIds = ((evento['coach_ids'] as List?) ?? const [])
          .map((id) => id.toString())
          .toSet();
      return coachIds.contains(_filtroCoachId);
    }).toList();

    for (final evento in baseResumo) {
      final tipo = _normalizarTipoEvento(
        evento['normalized_event_type'] ?? evento['event_type'],
      );

      if (typeCounts.containsKey(tipo)) {
        typeCounts[tipo] = typeCounts[tipo]! + 1;
      }
    }

    final counts = {'accepted': 0, 'rejected': 0, 'pending': 0};

    for (final evento in baseResumo.where((evento) {
      final tipo = _normalizarTipoEvento(
        evento['normalized_event_type'] ?? evento['event_type'],
      );
      return tipo == _filtroTipoEvento;
    })) {
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

    if (widget.agendaMode) {
      final now = DateTime.now();
      lista = lista.where((treino) {
        final eventDate = _parseEventDateTime(treino);
        return _showPastEvents
            ? eventDate.isBefore(now)
            : !eventDate.isBefore(now);
      }).toList();
    }

    if (_filtroStatus != 'todos') {
      lista = lista.where((treino) {
        final status = (treino['convocation_status'] ?? 'pending')
            .toString()
            .toLowerCase()
            .trim();
        return status == _filtroStatus;
      }).toList();
    }

    if (_mostrarTodosPlanejamentos && _filtroCoachId != 'todos') {
      lista = lista.where((treino) {
        final coachIds = ((treino['coach_ids'] as List?) ?? const [])
            .map((id) => id.toString())
            .toSet();
        return coachIds.contains(_filtroCoachId);
      }).toList();
    }

    lista.sort((a, b) {
      final comparison =
          _parseEventDateTime(a).compareTo(_parseEventDateTime(b));
      return widget.agendaMode && _showPastEvents ? -comparison : comparison;
    });

    _treinosFiltrados = lista;
    _atualizarResumoStatus();
  }

  List<MapEntry<String, String>> _getTreinadoresDisponiveis() {
    final coaches = <String, String>{
      if (_technicalAssignment?.isCoordinator == true)
        for (final entry in _visibleCoachNames.entries)
          if (entry.key != (_supabase.auth.currentUser?.id ?? ''))
            entry.key: entry.value.isEmpty ? 'Treinador' : entry.value,
    };

    for (final treino in _getEventosDoTipoSelecionado()) {
      final options = ((treino['coach_options'] as List?) ?? const []);
      for (final option in options) {
        if (option is! Map) continue;
        final id = (option['id'] ?? '').toString();
        if (id.isEmpty) continue;
        final name = (option['name'] ?? '').toString().trim();
        coaches[id] = name.isEmpty ? 'Treinador' : name;
      }
    }

    final entries = coaches.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value));
    return entries;
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
                    gradient: LinearGradient(
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
              Text(
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

  List<Map<String, dynamic>> _getTreinosSemPlanejamentoDoMes() {
    final referenceMonth = _filtroMes.isEmpty ? _getMesAtual() : _filtroMes;
    final pending = _treinos.where((event) {
      final type = _normalizarTipoEvento(
        event['normalized_event_type'] ?? event['event_type'],
      );
      final date = (event['event_date'] ?? '').toString();
      final monthMatches =
          date.length >= 7 && date.substring(3) == referenceMonth;
      return type == 'treino' && monthMatches && event['has_planning'] != true;
    }).toList();

    final now = DateTime.now();
    pending.sort((a, b) {
      final aDate = _parseEventDateTime(a);
      final bDate = _parseEventDateTime(b);
      final aPast = aDate.isBefore(now);
      final bPast = bDate.isBefore(now);
      if (aPast != bPast) return aPast ? -1 : 1;
      return aPast ? bDate.compareTo(aDate) : aDate.compareTo(bDate);
    });
    return pending;
  }

  Color _pendingPlanningColor(DateTime eventDate) {
    final difference = eventDate.difference(DateTime.now());
    if (difference <= Duration.zero) return olympusDanger;
    if (difference <= const Duration(hours: 48)) {
      return const Color(0xFFE67E22);
    }
    if (difference <= const Duration(days: 7)) return olympusWarning;
    return const Color(0xFF3B82F6);
  }

  String _pendingPlanningLabel(DateTime eventDate) {
    final difference = eventDate.difference(DateTime.now());
    if (difference <= Duration.zero) return 'ATRASADO';
    if (difference <= const Duration(hours: 48)) return 'URGENTE';
    if (difference <= const Duration(days: 7)) return 'ESTA SEMANA';
    return 'PROGRAMADO';
  }

  Widget _buildPendingPlanningCard() {
    if (_filtroTipoEvento != 'treino') return const SizedBox.shrink();

    final pending = _getTreinosSemPlanejamentoDoMes();
    if (pending.isEmpty) return const SizedBox.shrink();

    final now = DateTime.now();
    final nextWeek = now.add(const Duration(days: 7));
    final weekCount = pending.where((event) {
      final date = _parseEventDateTime(event);
      return date.isAfter(now) && !date.isAfter(nextWeek);
    }).length;
    final overdueCount = pending
        .where((event) => _parseEventDateTime(event).isBefore(now))
        .length;
    final visible = _showAllPendingPlans ? pending : pending.take(3).toList();

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.96),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: olympusGold.withOpacity(0.34)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: olympusGold.withOpacity(0.14),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.pending_actions_rounded,
                  color: olympusBlue,
                  size: 19,
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Planejamentos pendentes',
                      style: TextStyle(
                        color: olympusBlue,
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: olympusBlue,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '${pending.length}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            runSpacing: 4,
            children: [
              Text(
                'Esta semana: $weekCount',
                style: const TextStyle(
                  color: olympusMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                'No mês: ${pending.length}',
                style: const TextStyle(
                  color: olympusMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (overdueCount > 0)
                Text(
                  'Atrasados: $overdueCount',
                  style: const TextStyle(
                    color: olympusDanger,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          ...visible.map((event) {
            final date = _parseEventDateTime(event);
            final color = _pendingPlanningColor(date);
            return InkWell(
              onTap: () => _abrirDetalheTreino(event),
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Container(
                      width: 4,
                      height: 34,
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            (event['event_name'] ?? 'Treino').toString(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: olympusBlue,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            _formatarDataHora(event),
                            style: const TextStyle(
                              color: olympusMuted,
                              fontSize: 10.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.10),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        _pendingPlanningLabel(date),
                        style: TextStyle(
                          color: color,
                          fontSize: 8.5,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
          if (pending.length > 3)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => setState(() {
                  _showAllPendingPlans = !_showAllPendingPlans;
                }),
                icon: Icon(
                  _showAllPendingPlans
                      ? Icons.expand_less_rounded
                      : Icons.expand_more_rounded,
                  size: 17,
                ),
                label: Text(
                  _showAllPendingPlans
                      ? 'Mostrar menos'
                      : '+ ${pending.length - 3} outros',
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildResumoTreinosSection({bool compact = false}) {
    if (compact) {
      final total = _getEventosDoTipoSelecionado().length;
      final pending = _filtroTipoEvento == 'treino'
          ? _getTreinosSemPlanejamentoDoMes().length
          : 0;

      return Container(
        margin: const EdgeInsets.fromLTRB(10, 8, 10, 8),
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.96),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.blue.withOpacity(0.20)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.07),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: _colorTipoEvento(_filtroTipoEvento).withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                _iconTipoEvento(_filtroTipoEvento),
                color: _colorTipoEvento(_filtroTipoEvento),
                size: 18,
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${_labelTipoEvento(_filtroTipoEvento)} no mês',
                    style: TextStyle(
                      color: olympusBlue,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    '$total evento(s)',
                    style: const TextStyle(
                      color: olympusMuted,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            if (pending > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                decoration: BoxDecoration(
                  color: olympusDanger.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '$pending sem plano',
                  style: const TextStyle(
                    color: olympusDanger,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
          ],
        ),
      );
    }

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
                    style: TextStyle(
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
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: olympusBlue.withOpacity(0.06),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: olympusBlue.withOpacity(0.12)),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.calendar_view_month_rounded,
                    color: olympusBlue,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Total no mês',
                      style: TextStyle(
                        color: olympusBlue,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Text(
                    '${_getEventosDoTipoSelecionado().length}',
                    style: TextStyle(
                      color: olympusBlue,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
            _buildPendingPlanningCard(),
          ],
        ),
      ),
    );
  }

  Widget _buildFiltersAndSummary() {
    if (widget.agendaMode) return _buildAgendaFilters();
    final branding = OlympusBrandingController.instance.branding;
    final primary = branding.primaryColor;
    final secondary = Color.lerp(
      primary,
      branding.backgroundColor,
      0.18,
    )!;
    return LayoutBuilder(
      builder: (context, constraints) {
        final mobile = constraints.maxWidth < 600;

        if (mobile) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [primary, secondary],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                  borderRadius: BorderRadius.only(
                    bottomLeft: Radius.circular(14),
                    bottomRight: Radius.circular(14),
                  ),
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: 46,
                      height: 46,
                      child: IconButton.filled(
                        tooltip: _isVisaoGeral
                            ? 'Voltar para o mês atual'
                            : 'Ativar visão geral',
                        onPressed: _alternarVisaoGeral,
                        style: IconButton.styleFrom(
                          backgroundColor:
                              _isVisaoGeral ? olympusGold : Colors.white,
                          foregroundColor: olympusBlue,
                        ),
                        icon: Icon(
                          _isVisaoGeral
                              ? Icons.calendar_month_rounded
                              : Icons.dashboard_customize_rounded,
                          size: 20,
                        ),
                      ),
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: _buildModernDropdown(
                        icon: Icons.calendar_month,
                        value: _filtroMes.isEmpty ? null : _filtroMes,
                        hint: 'Mês',
                        items: _getMesesDisponiveis().map((mes) {
                          return DropdownMenuItem(
                            value: mes,
                            child: Text(_formatarNomeMes(mes)),
                          );
                        }).toList(),
                        onChanged: (valor) {
                          if (valor != null) {
                            _selecionarMes(valor.toString());
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
                child: _buildPlanningScopeSelector(),
              ),
              if (_mostrarTodosPlanejamentos)
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
                  child: _buildCoachFilterDropdown(),
                ),
              _buildResumoTreinosSection(compact: true),
            ],
          );
        }

        return Column(
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [primary, secondary],
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
                  _buildPlanningScopeSelector(),
                  if (_mostrarTodosPlanejamentos) ...[
                    const SizedBox(height: 10),
                    _buildCoachFilterDropdown(),
                  ],
                  const SizedBox(height: 10),
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
                            color:
                                _filtroMes == mes ? olympusBlue : Colors.black,
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
      },
    );
  }

  Widget _buildAgendaFilters() {
    final branding = OlympusBrandingController.instance.branding;
    final primary = branding.primaryColor;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
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
          bottomLeft: Radius.circular(16),
          bottomRight: Radius.circular(16),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: _buildModernDropdown(
              icon: Icons.calendar_month_rounded,
              value: _filtroMes.isEmpty ? null : _filtroMes,
              hint: 'Mês',
              items: _getMesesDisponiveis()
                  .map(
                    (mes) => DropdownMenuItem(
                      value: mes,
                      child: Text(_formatarNomeMes(mes)),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value != null) _selecionarMes(value.toString());
              },
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            height: 58,
            child: FilterChip(
              selected: _showPastEvents,
              showCheckmark: false,
              avatar: Icon(
                Icons.history_rounded,
                color: _showPastEvents ? olympusBlue : Colors.white,
              ),
              label: const Text('Passados'),
              selectedColor: olympusGold,
              backgroundColor: primary,
              side: BorderSide(
                color: _showPastEvents ? olympusGold : Colors.white38,
              ),
              labelStyle: TextStyle(
                color: _showPastEvents ? olympusBlue : Colors.white,
                fontWeight: FontWeight.w900,
              ),
              onSelected: (selected) {
                setState(() {
                  _showPastEvents = selected;
                  _filtroStatus = 'todos';
                  _aplicarFiltros();
                });
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlanningScopeSelector() {
    Widget chip({
      required bool selected,
      required String label,
      required IconData icon,
      required VoidCallback onTap,
    }) {
      return ChoiceChip(
        selected: selected,
        showCheckmark: false,
        avatar: Icon(
          icon,
          size: 16,
          color: olympusBlue,
        ),
        label: Text(label),
        onSelected: (_) => onTap(),
        selectedColor: olympusGold,
        backgroundColor: Colors.white.withOpacity(0.92),
        side: BorderSide(
          color: selected ? olympusGold : Colors.white.withOpacity(0.58),
        ),
        labelStyle: TextStyle(
          color: olympusBlue,
          fontWeight: FontWeight.w900,
          fontSize: 12,
        ),
      );
    }

    return Align(
      alignment: Alignment.centerLeft,
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          chip(
            selected: !_mostrarTodosPlanejamentos,
            label: 'Meus treinos',
            icon: Icons.person_rounded,
            onTap: () => _alternarFontePlanejamentos(false),
          ),
          chip(
            selected: _mostrarTodosPlanejamentos,
            label: _technicalAssignment?.isCoordinator == true
                ? 'Minha equipe'
                : 'Todos planejados',
            icon: Icons.visibility_rounded,
            onTap: () => _alternarFontePlanejamentos(true),
          ),
        ],
      ),
    );
  }

  Widget _buildCoachFilterDropdown() {
    final coaches = _getTreinadoresDisponiveis();

    return _buildModernDropdown(
      icon: Icons.sports_rounded,
      value: _filtroCoachId,
      hint: 'Treinador',
      items: [
        const DropdownMenuItem(
          value: 'todos',
          child: Text('Treinadores da minha equipe'),
        ),
        ...coaches.map(
          (coach) => DropdownMenuItem(
            value: coach.key,
            child: Text(coach.value),
          ),
        ),
      ],
      onChanged: (valor) {
        setState(() {
          _filtroCoachId = (valor ?? 'todos').toString();
          _aplicarFiltros();
        });
      },
    );
  }

  Future<void> _abrirDetalheTreino(Map<String, dynamic> treino) async {
    final currentUserId = _supabase.auth.currentUser?.id ?? '';
    final assignedPlannerId =
        (treino['assigned_planning_coach_id'] ?? '').toString();
    final authorIds = ((treino['plan_author_ids'] as List?) ?? const [])
        .map((id) => id.toString())
        .where((id) => id.isNotEmpty)
        .toList();
    final effectivePlannerId = assignedPlannerId.isNotEmpty
        ? assignedPlannerId
        : (authorIds.isNotEmpty ? authorIds.first : '');
    final viewOnly = treino['view_only_planning'] == true ||
        (effectivePlannerId.isNotEmpty && effectivePlannerId != currentUserId);
    if (viewOnly) {
      await TrainingPlanReadonlySheet.show(
        context,
        event: treino,
        coachId: effectivePlannerId.isEmpty ? null : effectivePlannerId,
        emptyMessage: 'Este treino ainda não tem planejamento publicado.',
      );
      return;
    }

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CoachTrainingPlanDetailPage(treino: treino),
      ),
    );
    if (mounted) {
      await _buscarTreinosDoTecnico();
    }
  }

  Future<void> _liberarPlanejamentoParaTecnico(
    Map<String, dynamic> treino,
  ) async {
    final assignment = _technicalAssignment;
    if (assignment?.isCoordinator != true) return;
    try {
      final service = TechnicalStaffService(client: _supabase);
      final values = await Future.wait([
        service.loadAssignments(),
        service.loadAvailableProfiles(),
      ]);
      final assignments = values[0] as List<TechnicalStaffAssignment>;
      final profiles = values[1] as List<Map<String, dynamic>>;
      final names = <String, String>{
        for (final profile in profiles)
          (profile['id'] ?? '').toString():
              (profile['full_name'] ?? profile['email'] ?? 'Técnico')
                  .toString(),
      };
      final eligible = assignments
          .where((item) => item.isActive && item.userId != assignment!.userId)
          .toList();
      if (!mounted) return;
      if (eligible.isEmpty) {
        _showError('Não há outro técnico ativo disponível para este treino.');
        return;
      }
      final selected = await showDialog<TechnicalStaffAssignment>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Liberar planejamento'),
          content: SizedBox(
            width: 420,
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: eligible.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, index) {
                final item = eligible[index];
                return ListTile(
                  leading: const CircleAvatar(
                    child: Icon(Icons.sports_rounded),
                  ),
                  title: Text(names[item.userId] ?? 'Técnico'),
                  subtitle: Text(TechnicalStaffRole.label(item.technicalRole)),
                  onTap: () => Navigator.pop(dialogContext, item),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancelar'),
            ),
          ],
        ),
      );
      if (selected == null) return;
      await _supabase.rpc('enable_training_planning_v1', params: {
        'p_event_id': (treino['id'] ?? '').toString(),
        'p_coach_id': selected.userId,
      });
      try {
        await _supabase.functions.invoke(
          'send-push-notification',
          body: {
            'userId': selected.userId,
            'title': 'Planejamento de treino liberado',
            'body':
                'O planejamento de ${(treino['event_name'] ?? 'um treino').toString()} está disponível para preenchimento.',
            'type': 'training_planning',
            'eventId': (treino['id'] ?? '').toString(),
          },
        );
      } catch (_) {}
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Planejamento liberado para ${names[selected.userId] ?? 'o técnico'}.',
          ),
          backgroundColor: olympusSuccess,
        ),
      );
      await _buscarTreinosDoTecnico();
    } catch (error) {
      _showError('Não foi possível liberar o planejamento: $error');
    }
  }

  Future<void> _publicarPlanejamento(Map<String, dynamic> treino) async {
    try {
      await _supabase.rpc('publish_training_planning_v1', params: {
        'p_event_id': (treino['id'] ?? '').toString(),
      });
      try {
        await _supabase.functions.invoke(
          'send-event-notification',
          body: {'eventId': (treino['id'] ?? '').toString()},
        );
      } catch (_) {}
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Treino disponibilizado para a equipe.'),
          backgroundColor: olympusSuccess,
        ),
      );
      await _buscarTreinosDoTecnico();
    } catch (error) {
      _showError('Não foi possível disponibilizar o treino: $error');
    }
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

  Widget _buildAthleteCountBadge({
    required String label,
    required int count,
    required Color color,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
        decoration: BoxDecoration(
          color: color.withOpacity(0.09),
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: color.withOpacity(0.24)),
        ),
        child: Column(
          children: [
            Text(
              '$count',
              style: TextStyle(
                color: color,
                fontSize: 16,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontSize: 10,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _mostrarConfirmacoesTreino(
    Map<String, dynamic> treino,
  ) async {
    final eventId = (treino['id'] ?? '').toString().trim();
    if (eventId.isEmpty) {
      _showError('Não foi possível identificar este treino.');
      return;
    }

    var loadingVisible = true;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => Center(
        child: CircularProgressIndicator(color: olympusGold),
      ),
    );

    try {
      final response = await _supabase.rpc(
        'get_agenda_event_convocados',
        params: {'p_event_id': eventId},
      );
      final participantes = (response as List<dynamic>)
          .map((item) => Map<String, dynamic>.from(item as Map))
          .where((participante) {
        final tipo =
            (participante['user_type'] ?? '').toString().trim().toLowerCase();
        // Perfis antigos de atletas foram gravados como `member`. Eles também
        // são convocados e não podem desaparecer da lista de confirmações.
        return tipo == 'athlete' ||
            tipo == 'atleta' ||
            tipo == 'member' ||
            tipo == 'membro';
      }).toList()
        ..sort((a, b) {
          const ordem = {'accepted': 0, 'pending': 1, 'rejected': 2};
          final statusA = _normalizarStatusConvocacao(a['status']);
          final statusB = _normalizarStatusConvocacao(b['status']);
          final porStatus = (ordem[statusA] ?? 1).compareTo(
            ordem[statusB] ?? 1,
          );
          if (porStatus != 0) return porStatus;
          return (a['full_name'] ?? '').toString().toLowerCase().compareTo(
                (b['full_name'] ?? '').toString().toLowerCase(),
              );
        });

      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      loadingVisible = false;

      final aceitaram = participantes
          .where(
            (participante) =>
                _normalizarStatusConvocacao(participante['status']) ==
                'accepted',
          )
          .length;

      await showDialog<void>(
        context: context,
        builder: (dialogContext) => Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: Container(
            padding: const EdgeInsets.all(20),
            constraints: BoxConstraints(
              maxWidth: 520,
              maxHeight: MediaQuery.of(dialogContext).size.height * 0.75,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.people_outline_rounded,
                      color: olympusGold,
                      size: 28,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Confirmações: ${(treino['event_name'] ?? 'Treino').toString()}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: olympusBlue,
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            '$aceitaram aceitaram de ${participantes.length} atletas',
                            style: const TextStyle(
                              color: olympusMuted,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Fechar',
                      onPressed: () => Navigator.pop(dialogContext),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const Divider(height: 28),
                if (participantes.isEmpty)
                  const Flexible(
                    child: Center(
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 32),
                        child: Text(
                          'Nenhum atleta convocado para este treino.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: olympusMuted),
                        ),
                      ),
                    ),
                  )
                else
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: participantes.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final participante = participantes[index];
                        final status = _normalizarStatusConvocacao(
                          participante['status'],
                        );
                        final aceitou = status == 'accepted';
                        final recusou = status == 'rejected';
                        final cor = aceitou
                            ? olympusSuccess
                            : recusou
                                ? olympusDanger
                                : olympusWarning;
                        final rotulo = aceitou
                            ? 'Aceitou'
                            : recusou
                                ? 'Recusou'
                                : 'Pendente';
                        final justificativa =
                            (participante['justification'] ?? '')
                                .toString()
                                .trim();

                        return Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: cor.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: cor.withValues(alpha: 0.28),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    aceitou
                                        ? Icons.check_circle_rounded
                                        : recusou
                                            ? Icons.cancel_rounded
                                            : Icons.schedule_rounded,
                                    color: cor,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      (participante['full_name'] ?? 'Sem nome')
                                          .toString(),
                                      style: const TextStyle(
                                        color: olympusText,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    rotulo,
                                    style: TextStyle(
                                      color: cor,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ],
                              ),
                              if (recusou && justificativa.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Text(
                                  'Justificativa: $justificativa',
                                  style: const TextStyle(
                                    color: olympusDanger,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      if (loadingVisible) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      _showError('Erro ao carregar confirmações: $e');
    }
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
    final coachNames = ((treino['coach_names'] as List?) ?? const [])
        .map((name) => name.toString().trim())
        .where((name) => name.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    final coachLabel = coachNames.isEmpty
        ? ''
        : coachNames.length == 1
            ? coachNames.first
            : coachNames.take(2).join(', ') +
                (coachNames.length > 2 ? ' +${coachNames.length - 2}' : '');
    final endereco = _formatarEndereco(treino);
    final hasPlanning = treino['has_planning'] == true;
    final viewOnlyPlanning = treino['view_only_planning'] == true;
    final athleteCounts = Map<String, int>.from(
      treino['athlete_status_counts'] as Map? ?? const <String, int>{},
    );

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
                  if (_canViewConfirmations)
                    PopupMenuButton<String>(
                      tooltip: 'Opções do treino',
                      icon: Icon(
                        Icons.more_vert_rounded,
                        color: olympusBlue,
                      ),
                      onSelected: (value) {
                        if (value == 'confirmacoes') {
                          _mostrarConfirmacoesTreino(treino);
                        }
                      },
                      itemBuilder: (context) => [
                        PopupMenuItem<String>(
                          value: 'confirmacoes',
                          child: Row(
                            children: [
                              Icon(
                                Icons.how_to_reg_outlined,
                                color: olympusBlue,
                              ),
                              SizedBox(width: 10),
                              Text('Ver confirmações'),
                            ],
                          ),
                        ),
                      ],
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
              if (coachLabel.isNotEmpty) ...[
                const SizedBox(height: 7),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: olympusBlue.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: olympusBlue.withOpacity(0.10),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.sports_rounded,
                        size: 15,
                        color: olympusBlue.withOpacity(0.86),
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          'Treinador: $coachLabel',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: olympusBlue.withOpacity(0.90),
                            fontSize: isMobile ? 11.5 : 12.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
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
                EventAddressLink(
                  event: treino,
                  address: endereco,
                  iconColor: olympusSubtle,
                  iconSize: 15,
                  maxLines: 2,
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
              if (!widget.agendaMode) ...[
                const SizedBox(height: 14),
                Row(
                  children: [
                    _buildAthleteCountBadge(
                      label: 'Aceitaram',
                      count: athleteCounts['accepted'] ?? 0,
                      color: olympusSuccess,
                    ),
                    const SizedBox(width: 7),
                    _buildAthleteCountBadge(
                      label: 'Pendentes',
                      count: athleteCounts['pending'] ?? 0,
                      color: olympusWarning,
                    ),
                    const SizedBox(width: 7),
                    _buildAthleteCountBadge(
                      label: 'Recusaram',
                      count: athleteCounts['rejected'] ?? 0,
                      color: olympusDanger,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
              ],
              if (!viewOnlyPlanning && !widget.agendaMode)
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
                    onPressed: widget.agendaMode && !hasPlanning
                        ? null
                        : () => _abrirDetalheTreino(treino),
                    icon: Icon(
                      viewOnlyPlanning || hasPlanning
                          ? Icons.menu_book_outlined
                          : Icons.add_task_rounded,
                    ),
                    label: Text(widget.agendaMode
                        ? hasPlanning
                            ? 'Ver planejamento'
                            : 'Planejamento pendente'
                        : viewOnlyPlanning
                            ? 'Ver planejamento'
                            : hasPlanning
                                ? 'Abrir planejamento'
                                : 'Criar planejamento'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: viewOnlyPlanning
                          ? olympusBlue
                          : hasPlanning
                              ? olympusSuccess
                              : const Color(0xFFE67E22),
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.symmetric(
                        vertical: isMobile ? 11 : 12,
                      ),
                    ),
                  ),
                ),
                if (!widget.agendaMode &&
                    _technicalAssignment?.isCoordinator == true &&
                    !hasPlanning) ...[
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => _liberarPlanejamentoParaTecnico(treino),
                      icon: const Icon(Icons.person_add_alt_1_rounded),
                      label: const Text('Liberar planejamento para técnico'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: olympusBlue,
                        side: BorderSide(color: olympusGold),
                      ),
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOlympusBackground() {
    final branding = OlympusBrandingController.instance.branding;
    return Stack(
      fit: StackFit.expand,
      children: [
        OlympusBrandBackgroundImage(
          fit: BoxFit.cover,
          alignment: Alignment.center,
          errorBuilder: (_, __, ___) => Container(color: branding.primaryColor),
        ),
        Container(color: branding.primaryColor.withOpacity(0.62)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text(
          widget.pageTitle ??
              (widget.lockTipoEvento
                  ? 'Avaliar ${_labelTipoEvento(_filtroTipoEvento)}'
                  : 'Eventos e avaliações'),
        ),
        backgroundColor: colors.primary,
        foregroundColor: colors.onPrimary,
        actions: [
          if (_technicalAssignment?.isCoordinator == true)
            IconButton(
              tooltip: 'Painel de planejamento',
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const CoachTrainingPlanningDashboardPage(),
                ),
              ),
              icon: const Icon(Icons.dashboard_customize_rounded),
            ),
          IconButton(
            onPressed: _buscarTreinosDoTecnico,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          _buildOlympusBackground(),
          Column(
            children: [
              _buildFiltersAndSummary(),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _error != null
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Container(
                                constraints:
                                    const BoxConstraints(maxWidth: 360),
                                padding: const EdgeInsets.all(18),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.94),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: olympusDanger.withOpacity(0.18),
                                  ),
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.cloud_off_rounded,
                                      color: olympusDanger,
                                      size: 34,
                                    ),
                                    const SizedBox(height: 10),
                                    Text(
                                      _error!,
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        color: olympusText,
                                        fontWeight: FontWeight.w700,
                                        height: 1.3,
                                      ),
                                    ),
                                    const SizedBox(height: 14),
                                    FilledButton.icon(
                                      onPressed: _buscarTreinosDoTecnico,
                                      style: FilledButton.styleFrom(
                                        backgroundColor: olympusBlue,
                                      ),
                                      icon: const Icon(Icons.refresh_rounded),
                                      label: const Text('Tentar novamente'),
                                    ),
                                  ],
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
        ],
      ),
    );
  }
}
