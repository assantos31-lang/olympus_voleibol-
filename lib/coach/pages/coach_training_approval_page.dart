import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/technical_staff_service.dart';
import '../../theme/olympus_theme.dart';
import 'coach_training_plan_detail_page.dart';
import 'coach_training_planning_dashboard_page.dart';

class CoachTrainingApprovalPage extends StatefulWidget {
  const CoachTrainingApprovalPage({super.key});

  @override
  State<CoachTrainingApprovalPage> createState() =>
      _CoachTrainingApprovalPageState();
}

class _CoachTrainingApprovalPageState
    extends State<CoachTrainingApprovalPage> {
  Color get _blue => olympusBlue;
  static const _gold = Color(0xFFD4AF37);
  static const _green = Color(0xFF16A34A);
  static const _orange = Color(0xFFF59E0B);
  static const _background = Color(0xFFF4F7FB);

  final _supabase = Supabase.instance.client;
  final _staffService = TechnicalStaffService();
  bool _loading = true;
  bool _showPast = false;
  bool _canApprove = false;
  String? _error;
  String? _publishingEventId;
  List<Map<String, dynamic>> _items = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  String _text(dynamic value) => (value ?? '').toString().trim();

  DateTime? _eventDateTime(Map<String, dynamic> item) {
    final parts = _text(item['event_date']).split('/');
    if (parts.length != 3) return null;
    final day = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    final year = int.tryParse(parts[2]);
    if (day == null || month == null || year == null) return null;
    final time = _text(item['event_time']).split(':');
    return DateTime(
      year,
      month,
      day,
      time.isEmpty ? 0 : int.tryParse(time[0]) ?? 0,
      time.length < 2 ? 0 : int.tryParse(time[1]) ?? 0,
    );
  }

  int _minutes(Map<String, dynamic> block) {
    int toMinutes(dynamic value) {
      final parts = _text(value).split(':');
      if (parts.length < 2) return 0;
      return (int.tryParse(parts[0]) ?? 0) * 60 +
          (int.tryParse(parts[1]) ?? 0);
    }

    final start = toMinutes(block['start_time']);
    final end = toMinutes(block['end_time']);
    return end > start ? end - start : 0;
  }

  String _duration(int minutes) {
    if (minutes < 60) return '${minutes}min';
    final hours = minutes ~/ 60;
    final rest = minutes % 60;
    return rest == 0 ? '${hours}h' : '${hours}h ${rest}min';
  }

  String _shortTime(dynamic value) {
    final raw = _text(value);
    return raw.length <= 5 ? raw : raw.substring(0, 5);
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final staffValues = await Future.wait([
        _staffService.loadCurrentAssignment(),
        _staffService.loadAssignments(),
      ]);
      final assignment = staffValues[0] as TechnicalStaffAssignment?;
      final assignments = staffValues[1] as List<TechnicalStaffAssignment>;
      _canApprove = assignment?.canApproveTraining == true;
      final currentUserId = _supabase.auth.currentUser?.id ?? '';
      var visibleCoachIds = <String>{currentUserId}..remove('');
      if (_canApprove) {
        visibleCoachIds = {
          currentUserId,
          ...assignments
              .where((item) => item.supervisorUserId == currentUserId)
              .map((item) => item.userId),
        }..remove('');
      }
      final planningValues = await Future.wait<dynamic>([
        _supabase
            .from('training_planning_workflows')
            .select(
              'event_id, assigned_coach_id, status, enabled_at, published_at',
            )
            .inFilter('status', ['pending', 'enabled', 'published']),
        _supabase
            .from('training_plan_blocks')
            .select(
              'event_id, coach_id, start_time, end_time, category, type',
            )
            .inFilter('coach_id', visibleCoachIds.toList()),
      ]);
      final workflowResponse = planningValues[0];
      final allWorkflows =
          List<Map<String, dynamic>>.from(workflowResponse as List);
      final scopedBlocksResponse = planningValues[1];
      final scopedBlocks =
          List<Map<String, dynamic>>.from(scopedBlocksResponse as List);
      final workflows = (_canApprove
          ? allWorkflows
          : allWorkflows
              .where(
                (row) =>
                    _text(row['assigned_coach_id']) == currentUserId,
              )
              .toList())
        ..addAll(
          scopedBlocks
              .map((block) => _text(block['event_id']))
              .where((eventId) => eventId.isNotEmpty)
              .toSet()
              .where((eventId) => !allWorkflows.any(
                    (workflow) => _text(workflow['event_id']) == eventId,
                  ))
              .map((eventId) => <String, dynamic>{
                    'event_id': eventId,
                    'assigned_coach_id': '',
                    'status': 'enabled',
                    'enabled_at': null,
                    'published_at': null,
                  }),
        );
      final eventIds = workflows
          .map((row) => _text(row['event_id']))
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList();
      if (eventIds.isEmpty) {
        if (!mounted) return;
        setState(() {
          _items = const [];
          _loading = false;
        });
        return;
      }

      final responses = await Future.wait<dynamic>([
        _supabase
            .from('events')
            .select(
              'id, event_name, event_date, event_time, event_end_time, gender, city, state',
            )
            .inFilter('id', eventIds),
        Future.value(scopedBlocks),
        _supabase.rpc('get_technical_staff_directory_v1'),
        _supabase
            .from('convocations')
            .select('event_id, user_id')
            .eq('event_role', 'coach')
            .inFilter('event_id', eventIds),
      ]);

      final events = List<Map<String, dynamic>>.from(responses[0] as List);
      final blocks = List<Map<String, dynamic>>.from(responses[1] as List);
      final profiles = List<Map<String, dynamic>>.from(responses[2] as List);
      final convocations =
          List<Map<String, dynamic>>.from(responses[3] as List);
      final assignedCoachesByEvent = <String, Set<String>>{};
      for (final row in convocations) {
        final eventId = _text(row['event_id']);
        final coachId = _text(row['user_id']);
        if (eventId.isEmpty || coachId.isEmpty) continue;
        assignedCoachesByEvent
            .putIfAbsent(eventId, () => <String>{})
            .add(coachId);
      }
      final eventsById = {
        for (final event in events) _text(event['id']): event,
      };
      final namesById = {
        for (final profile in profiles)
          _text(profile['id']): _text(profile['full_name']).isEmpty
              ? _text(profile['email'])
              : _text(profile['full_name']),
      };

      final items = <Map<String, dynamic>>[];
      for (final workflow in workflows) {
        final eventId = _text(workflow['event_id']);
        final event = eventsById[eventId];
        if (event == null) continue;
        if (_canApprove) {
          final assignedCoaches =
              assignedCoachesByEvent[eventId] ?? const <String>{};
          final blockAuthors = blocks
              .where((block) => _text(block['event_id']) == eventId)
              .map((block) => _text(block['coach_id']))
              .toSet();
          if (!assignedCoaches.any(visibleCoachIds.contains) &&
              !blockAuthors.any(visibleCoachIds.contains)) {
            continue;
          }
        }
        final assignedPlannerId = _text(workflow['assigned_coach_id']);
        final eventBlocks = blocks
            .where((block) => _text(block['event_id']) == eventId)
            .toList();
        final historicalAuthorId = eventBlocks
            .map((block) => _text(block['coach_id']))
            .firstWhere((id) => id.isNotEmpty, orElse: () => '');
        final plannerId = assignedPlannerId.isNotEmpty
            ? assignedPlannerId
            : historicalAuthorId;
        final planBlocks = blocks
            .where((block) =>
                _text(block['event_id']) == eventId &&
                (plannerId.isEmpty || _text(block['coach_id']) == plannerId))
            .toList();
        items.add({
          ...event,
          ...workflow,
          'assigned_coach_id': plannerId,
          'planner_name': namesById[plannerId] ?? 'Coordenador/Técnico',
          'blocks': planBlocks,
          'block_count': planBlocks.length,
          'planned_minutes':
              planBlocks.fold<int>(0, (total, block) => total + _minutes(block)),
        });
      }
      items.sort((a, b) => (_eventDateTime(a) ?? DateTime(2100))
          .compareTo(_eventDateTime(b) ?? DateTime(2100)));
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Não foi possível carregar os planejamentos: $error';
      });
    }
  }

  List<Map<String, dynamic>> get _visibleItems {
    final now = DateTime.now();
    final list = _items.where((item) {
      final date = _eventDateTime(item);
      if (date == null) return !_showPast;
      return _showPast ? date.isBefore(now) : !date.isBefore(now);
    }).toList();
    if (_showPast) return list.reversed.toList();
    return list;
  }

  int get _readyCount => _items
      .where((item) =>
          _text(item['status']) == 'enabled' &&
          (item['block_count'] as int? ?? 0) > 0)
      .length;

  int get _buildingCount => _items
      .where((item) =>
          _text(item['status']) == 'pending' ||
          (_text(item['status']) == 'enabled' &&
              (item['block_count'] as int? ?? 0) == 0))
      .length;

  int get _publishedCount =>
      _items.where((item) => _text(item['status']) == 'published').length;

  List<Map<String, dynamic>> get _futureItems {
    final now = DateTime.now();
    return _items
        .where((item) => !(_eventDateTime(item) ?? now).isBefore(now))
        .toList()
      ..sort((a, b) => (_eventDateTime(a) ?? DateTime(2100))
          .compareTo(_eventDateTime(b) ?? DateTime(2100)));
  }

  int get _futurePlannedMinutes => _futureItems.fold<int>(
        0,
        (total, item) => total + (item['planned_minutes'] as int? ?? 0),
      );

  Future<void> _publish(Map<String, dynamic> item) async {
    final eventId = _text(item['event_id']);
    if (eventId.isEmpty || _publishingEventId != null) return;
    setState(() => _publishingEventId = eventId);
    try {
      await _supabase.rpc(
        'publish_training_planning_v1',
        params: {'p_event_id': eventId},
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Planejamento aprovado e publicado.'),
          backgroundColor: _green,
        ),
      );
      await _load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível publicar: $error')),
      );
    } finally {
      if (mounted) setState(() => _publishingEventId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visibleItems;
    return Scaffold(
      backgroundColor: _background,
      appBar: AppBar(
        title: const Text('Painel de planejamento'),
        backgroundColor: _blue,
        foregroundColor: Colors.white,
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _ErrorState(message: _error!, onRetry: _load)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Text(
                        _canApprove ? 'Visão da equipe' : 'Meus treinos',
                        style: TextStyle(
                          color: _blue,
                          fontSize: 21,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _canApprove
                            ? 'Acompanhe o andamento da equipe e publique somente os planejamentos prontos.'
                            : 'Acompanhe o que precisa ser planejado e o que já foi publicado.',
                        style: TextStyle(color: Color(0xFF53657B)),
                      ),
                      const SizedBox(height: 14),
                      _buildRelevantOverview(),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(child: _Summary(value: _readyCount, label: _canApprove ? 'Para aprovar' : 'Prontos', color: _orange)),
                          const SizedBox(width: 8),
                          Expanded(child: _Summary(value: _buildingCount, label: _canApprove ? 'Pendentes' : 'Em elaboração', color: _blue)),
                          const SizedBox(width: 8),
                          Expanded(child: _Summary(value: _publishedCount, label: 'Publicados', color: _green)),
                        ],
                      ),
                      const SizedBox(height: 16),
                      OutlinedButton.icon(
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const CoachTrainingPlanningDashboardPage(),
                          ),
                        ),
                        icon: const Icon(Icons.insights_rounded),
                        label: const Text('Ver análise de carga e distribuição'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _blue,
                          padding: const EdgeInsets.symmetric(vertical: 13),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SegmentedButton<bool>(
                        segments: const [
                          ButtonSegment(value: false, icon: Icon(Icons.upcoming_rounded), label: Text('Futuros')),
                          ButtonSegment(value: true, icon: Icon(Icons.history_rounded), label: Text('Passados')),
                        ],
                        selected: {_showPast},
                        onSelectionChanged: (value) => setState(() => _showPast = value.first),
                        style: ButtonStyle(
                          backgroundColor: WidgetStateProperty.resolveWith((states) =>
                              states.contains(WidgetState.selected) ? _gold : Colors.white),
                        ),
                      ),
                      const SizedBox(height: 14),
                      if (visible.isEmpty)
                        const _EmptyState()
                      else
                        ...visible.map(_buildCard),
                    ],
                  ),
                ),
    );
  }

  Widget _buildCard(Map<String, dynamic> item) {
    final status = _text(item['status']);
    final blocks = List<Map<String, dynamic>>.from(item['blocks'] as List);
    final ready = status == 'enabled' && blocks.isNotEmpty;
    final published = status == 'published';
    final color = published ? _green : ready ? _orange : _blue;
    final statusLabel = published
        ? 'Publicado'
        : status == 'pending'
            ? 'Aguardando responsável'
        : ready
            ? (_canApprove ? 'Pronto para aprovar' : 'Pronto')
            : 'Em elaboração';
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: color.withOpacity(0.22)),
      ),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.fromLTRB(14, 7, 14, 7),
        childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
        leading: CircleAvatar(
          backgroundColor: color.withOpacity(0.12),
          child: Icon(Icons.fitness_center_rounded, color: color),
        ),
        title: Text(
          _text(item['event_name']).isEmpty ? 'Treino' : _text(item['event_name']),
          style: TextStyle(color: _blue, fontWeight: FontWeight.w900),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 5),
          child: Text(
            '${item['event_date'] ?? ''} • ${_shortTime(item['event_time'])}\n${item['planner_name']} • ${blocks.length} bloco(s) • ${_duration(item['planned_minutes'] as int? ?? 0)}',
          ),
        ),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
          decoration: BoxDecoration(color: color.withOpacity(0.11), borderRadius: BorderRadius.circular(99)),
          child: Text(statusLabel, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w800)),
        ),
        children: [
          if (blocks.isEmpty)
            const Align(
              alignment: Alignment.centerLeft,
              child: Text('O responsável ainda não cadastrou blocos.'),
            )
          else
            ...blocks.asMap().entries.map((entry) => ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(radius: 14, child: Text('${entry.key + 1}')),
                  title: Text(_text(entry.value['type']).isEmpty ? 'Bloco ${entry.key + 1}' : _text(entry.value['type'])),
                  subtitle: Text('${entry.value['category'] ?? ''} • ${entry.value['start_time'] ?? ''} às ${entry.value['end_time'] ?? ''}'),
                )),
          if (ready && _canApprove) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _publishingEventId == _text(item['event_id']) ? null : () => _publish(item),
                icon: const Icon(Icons.verified_rounded),
                label: Text(_publishingEventId == _text(item['event_id']) ? 'Publicando...' : 'Aprovar e publicar'),
                style: ElevatedButton.styleFrom(backgroundColor: _green, foregroundColor: Colors.white),
              ),
            ),
          ],
          if (status == 'enabled' &&
              _text(item['assigned_coach_id']) ==
                  (_supabase.auth.currentUser?.id ?? '')) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => CoachTrainingPlanDetailPage(treino: item),
                    ),
                  );
                  await _load();
                },
                icon: const Icon(Icons.edit_calendar_rounded),
                label: Text(blocks.isEmpty ? 'Criar planejamento' : 'Continuar planejamento'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRelevantOverview() {
    final next = _futureItems.isEmpty ? null : _futureItems.first;
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: _blue,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          const CircleAvatar(
            backgroundColor: Color(0x33D4AF37),
            child: Icon(Icons.event_available_rounded, color: _gold),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Próximo treino',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
                const SizedBox(height: 2),
                Text(
                  next == null
                      ? 'Nenhum treino futuro'
                      : '${next['event_date']} às ${_shortTime(next['event_time'])}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Text(
                'Carga futura',
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
              const SizedBox(height: 2),
              Text(
                _duration(_futurePlannedMinutes),
                style: const TextStyle(
                  color: _gold,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.value, required this.label, required this.color});
  final int value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 13),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
        child: Column(children: [Text('$value', style: TextStyle(color: color, fontSize: 22, fontWeight: FontWeight.w900)), const SizedBox(height: 3), Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700))]),
      );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();
  @override
  Widget build(BuildContext context) => const Card(
        elevation: 0,
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(children: [Icon(Icons.task_alt_rounded, size: 42, color: Color(0xFF16A34A)), SizedBox(height: 10), Text('Nenhum planejamento neste período.', textAlign: TextAlign.center)]),
        ),
      );
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});
  final String message;
  final Future<void> Function() onRetry;
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [Text(message, textAlign: TextAlign.center), const SizedBox(height: 12), ElevatedButton(onPressed: onRetry, child: const Text('Tentar novamente'))]),
        ),
      );
}
