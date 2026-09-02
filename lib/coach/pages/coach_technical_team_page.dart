import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/technical_staff_service.dart';
import '../../theme/olympus_theme.dart';
import 'coach_training_approval_page.dart';
import 'coach_training_plan_detail_page.dart';
import 'coach_training_planning_dashboard_page.dart';

class CoachTechnicalTeamPage extends StatefulWidget {
  const CoachTechnicalTeamPage({super.key});

  @override
  State<CoachTechnicalTeamPage> createState() => _CoachTechnicalTeamPageState();
}

class _CoachTechnicalTeamPageState extends State<CoachTechnicalTeamPage> {
  Color get _blue => olympusBlue;
  static const _gold = Color(0xFFD4AF37);
  final TechnicalStaffService _service = TechnicalStaffService();

  TechnicalStaffAssignment? _current;
  List<TechnicalStaffAssignment> _staff = const [];
  List<Map<String, dynamic>> _profiles = const [];
  bool _loading = true;
  String? _error;
  RealtimeChannel? _realtimeChannel;

  @override
  void initState() {
    super.initState();
    _load();
    _setupRealtime();
  }

  void _setupRealtime() {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null || _realtimeChannel != null) return;
    _realtimeChannel = Supabase.instance.client
        .channel('coach-technical-team-$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'technical_staff_assignments',
          callback: (_) => _load(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'profiles',
          callback: (_) => _load(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'training_plans',
          callback: (_) => _load(),
        )
        .subscribe();
  }

  @override
  void dispose() {
    final channel = _realtimeChannel;
    if (channel != null) {
      Supabase.instance.client.removeChannel(channel);
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final values = await Future.wait([
        _service.loadCurrentAssignment(),
        _service.loadAssignments(),
        _service.loadAvailableProfiles(),
      ]);
      if (!mounted) return;
      setState(() {
        _current = values[0] as TechnicalStaffAssignment?;
        _staff = values[1] as List<TechnicalStaffAssignment>;
        _profiles = values[2] as List<Map<String, dynamic>>;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  String _name(String userId) {
    final profile = _profile(userId);
    final name = (profile?['full_name'] ?? '').toString().trim();
    if (name.isNotEmpty) return name;
    final email = (profile?['email'] ?? '').toString().trim();
    return email.isEmpty ? 'Treinador' : email.split('@').first;
  }

  Map<String, dynamic>? _profile(String userId) {
    for (final profile in _profiles) {
      if ((profile['id'] ?? '').toString() == userId) return profile;
    }
    return null;
  }

  String _avatarUrl(String userId) =>
      (_profile(userId)?['avatar_url'] ?? '').toString().trim();

  Widget _staffAvatar(String userId) {
    final name = _name(userId);
    final avatarUrl = _avatarUrl(userId);
    return CircleAvatar(
      backgroundColor: _gold.withOpacity(0.18),
      backgroundImage: avatarUrl.isEmpty ? null : NetworkImage(avatarUrl),
      child: avatarUrl.isEmpty
          ? Text(
              name.isEmpty ? 'T' : name.substring(0, 1).toUpperCase(),
              style: TextStyle(
                color: _blue,
                fontWeight: FontWeight.w900,
              ),
            )
          : null,
    );
  }

  List<TechnicalStaffAssignment> get _visibleTeam {
    final current = _current;
    if (current == null) return const [];
    if (current.isCoordinator) {
      return _staff
          .where((item) =>
              item.userId != current.userId &&
              item.technicalRole != TechnicalStaffRole.coordinator &&
              item.supervisorUserId == current.userId)
          .toList();
    }
    return _staff
        .where((item) =>
            item.userId == current.userId ||
            item.supervisorUserId == current.userId)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final branding = OlympusBrandingController.instance.branding;
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: branding.backgroundColor,
      appBar: AppBar(
        backgroundColor: colors.primary,
        foregroundColor: colors.onPrimary,
        title: const Text('Minha Equipe Técnica'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text('Não foi possível carregar: $_error'))
              : _current == null
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'Seu acesso técnico ainda não foi configurado pelo administrador.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          _buildHeader(),
                          const SizedBox(height: 14),
                          if (_current!.canCreateTraining ||
                              _current!.canPublishTraining ||
                              _current!.canApproveTraining)
                            _buildTrainingActions(),
                          const SizedBox(height: 20),
                          Text(
                            'Profissionais sob sua visão',
                            style: TextStyle(
                              color: _blue,
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 10),
                          ..._visibleTeam.map(_buildStaffCard),
                        ],
                      ),
                    ),
    );
  }

  Widget _buildHeader() {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colors.primary,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.account_tree_rounded, color: _gold, size: 34),
          const SizedBox(height: 10),
          Text(
            TechnicalStaffRole.label(_current!.technicalRole),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 21,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${_visibleTeam.length} profissionais visíveis na sua estrutura',
            style: const TextStyle(color: Colors.white70),
          ),
        ],
      ),
    );
  }

  Widget _buildTrainingActions() {
    return Row(
      children: [
        if (_current!.canApproveTraining)
          Expanded(
            child: _ActionCard(
              icon: Icons.approval_rounded,
              title: 'Aprovar treinos',
              subtitle: 'Revisar planejamentos da equipe',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const CoachTrainingApprovalPage(),
                ),
              ),
            ),
          ),
        if (_current!.canApproveTraining &&
            (_current!.canCreateTraining || _current!.canPublishTraining))
          const SizedBox(width: 10),
        if (_current!.canCreateTraining || _current!.canPublishTraining)
          Expanded(
            child: _ActionCard(
              icon: Icons.add_task_rounded,
              title: 'Planejamento',
              subtitle: _current!.canPublishTraining
                  ? 'Criar, delegar ou publicar'
                  : 'Preparar uma nova sessão',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const CoachTrainingPlanningDashboardPage(),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildStaffCard(TechnicalStaffAssignment item) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: _blue.withOpacity(0.10)),
      ),
      child: ListTile(
        onTap: _current?.isCoordinator == true
            ? () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => _CoachPlanningAccessPage(
                      coach: item,
                      coachName: _name(item.userId),
                    ),
                  ),
                );
                await _load();
              }
            : null,
        leading: _staffAvatar(item.userId),
        title: Text(
          _name(item.userId),
          style: TextStyle(color: _blue, fontWeight: FontWeight.w800),
        ),
        subtitle: Text(
          '${TechnicalStaffRole.label(item.technicalRole)}${item.supervisorUserId == null ? '' : ' • responde a ${_name(item.supervisorUserId!)}'}',
        ),
        trailing: _current?.isCoordinator == true
            ? const Icon(Icons.chevron_right_rounded)
            : null,
      ),
    );
  }
}

class _CoachPlanningAccessPage extends StatefulWidget {
  const _CoachPlanningAccessPage({
    required this.coach,
    required this.coachName,
  });

  final TechnicalStaffAssignment coach;
  final String coachName;

  @override
  State<_CoachPlanningAccessPage> createState() =>
      _CoachPlanningAccessPageState();
}

class _CoachPlanningAccessPageState extends State<_CoachPlanningAccessPage> {
  final _supabase = Supabase.instance.client;
  Color get _blue => olympusBlue;
  static const _gold = Color(0xFFD4AF37);

  bool _loading = true;
  bool _saving = false;
  bool _showPast = false;
  final Set<String> _selectedEventIds = {};
  List<Map<String, dynamic>> _events = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  String _text(dynamic value) => (value ?? '').toString().trim();

  DateTime? _dateTime(Map<String, dynamic> event) {
    final date = _text(event['event_date']).split('/');
    if (date.length != 3) return null;
    final time = _text(event['event_time']).split(':');
    final day = int.tryParse(date[0]);
    final month = int.tryParse(date[1]);
    final year = int.tryParse(date[2]);
    if (day == null || month == null || year == null) return null;
    return DateTime(
      year,
      month,
      day,
      time.isEmpty ? 0 : int.tryParse(time[0]) ?? 0,
      time.length < 2 ? 0 : int.tryParse(time[1]) ?? 0,
    );
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      final response = await _supabase.rpc(
        'get_coach_assigned_trainings_v1',
        params: {'p_coach_id': widget.coach.userId},
      );
      final events = List<Map<String, dynamic>>.from(response as List);
      for (final event in events) {
        event['id'] = event['event_id'];
        event['planner_id'] = event['planner_id'];
        event['planning_status'] = event['planning_status'] ?? 'pending';
      }
      events.sort((a, b) => (_dateTime(a) ?? DateTime(2100))
          .compareTo(_dateTime(b) ?? DateTime(2100)));
      if (!mounted) return;
      setState(() {
        _events = events;
        _selectedEventIds.removeWhere(
          (id) => !events.any((event) => _text(event['id']) == id),
        );
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _events = const [];
        _loading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível carregar os treinos: $error')),
      );
    }
  }

  List<Map<String, dynamic>> get _visibleEvents {
    final now = DateTime.now();
    final result = _events.where((event) {
      final date = _dateTime(event);
      if (date == null) return !_showPast;
      return _showPast ? date.isBefore(now) : !date.isBefore(now);
    }).toList();
    return _showPast ? result.reversed.toList() : result;
  }

  Future<void> _assignSelected({required bool toCoach}) async {
    if (_selectedEventIds.isEmpty || _saving) return;
    final plannerId =
        toCoach ? widget.coach.userId : _supabase.auth.currentUser?.id;
    if (plannerId == null || plannerId.isEmpty) return;
    setState(() => _saving = true);
    try {
      for (final eventId in _selectedEventIds) {
        await _supabase.rpc(
          'enable_training_planning_v1',
          params: {'p_event_id': eventId, 'p_coach_id': plannerId},
        );
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(toCoach
              ? 'Planejamento liberado para ${widget.coachName}.'
              : 'Os treinos selecionados ficaram com o coordenador.'),
          backgroundColor: Colors.green,
        ),
      );
      _selectedEventIds.clear();
      await _load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível atualizar: $error')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'published':
        return 'Publicado';
      case 'enabled':
        return 'Liberado para preencher';
      default:
        return 'Aguardando definição';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FB),
      appBar: AppBar(
        title: Text(widget.coachName),
        backgroundColor: _blue,
        foregroundColor: Colors.white,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  'Atribuir planejamentos',
                  style: TextStyle(
                    color: _blue,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  'Aqui aparecem somente os treinos em que ${widget.coachName} foi definido como treinador no Admin. Selecione quem fará o planejamento.',
                  style: const TextStyle(color: Color(0xFF53657B)),
                ),
                const SizedBox(height: 14),
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(
                        value: false,
                        icon: Icon(Icons.upcoming_rounded),
                        label: Text('Futuros')),
                    ButtonSegment(
                        value: true,
                        icon: Icon(Icons.history_rounded),
                        label: Text('Passados')),
                  ],
                  selected: {_showPast},
                  onSelectionChanged: (value) => setState(() {
                    _showPast = value.first;
                    _selectedEventIds.clear();
                  }),
                  style: ButtonStyle(
                    backgroundColor: WidgetStateProperty.resolveWith(
                      (states) => states.contains(WidgetState.selected)
                          ? _gold
                          : Colors.white,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                if (_visibleEvents.isEmpty)
                  const Card(
                    elevation: 0,
                    child: Padding(
                      padding: EdgeInsets.all(18),
                      child: Text(
                        'Nenhum treino atribuído a este técnico neste período.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                else
                  ..._visibleEvents.map((event) {
                    final eventId = _text(event['id']);
                    final plannerId = _text(event['planner_id']);
                    final currentUserId = _supabase.auth.currentUser?.id ?? '';
                    final plannerLabel = plannerId.isEmpty
                        ? 'Planejamento ainda não atribuído'
                        : plannerId == widget.coach.userId
                            ? '${widget.coachName} fará o planejamento'
                            : plannerId == currentUserId
                                ? 'Coordenador fará o planejamento'
                                : 'Planejamento atribuído';
                    return Card(
                      elevation: 0,
                      child: ListTile(
                        leading: Checkbox(
                          value: _selectedEventIds.contains(eventId),
                          activeColor: _gold,
                          checkColor: _blue,
                          onChanged: _showPast ||
                                  _text(event['planning_status']) == 'published'
                              ? null
                              : (selected) => setState(() {
                                    if (selected == true) {
                                      _selectedEventIds.add(eventId);
                                    } else {
                                      _selectedEventIds.remove(eventId);
                                    }
                                  }),
                        ),
                        title: Text(
                          _text(event['event_name']).isEmpty
                              ? 'Treino'
                              : _text(event['event_name']),
                          style: TextStyle(
                              color: _blue, fontWeight: FontWeight.w800),
                        ),
                        subtitle: Text(
                          '${event['event_date'] ?? ''} • ${event['event_time'] ?? ''}\n$plannerLabel • ${_statusLabel(_text(event['planning_status']))}',
                        ),
                        isThreeLine: true,
                        trailing: plannerId == currentUserId &&
                                _text(event['planning_status']) == 'enabled'
                            ? IconButton(
                                tooltip: 'Abrir planejamento',
                                onPressed: () async {
                                  await Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          CoachTrainingPlanDetailPage(
                                              treino: event),
                                    ),
                                  );
                                  await _load();
                                },
                                icon: Icon(Icons.edit_calendar_rounded,
                                    color: _blue),
                              )
                            : null,
                      ),
                    );
                  }),
                if (_selectedEventIds.isNotEmpty && !_showPast) ...[
                  const SizedBox(height: 12),
                  Text('${_selectedEventIds.length} treino(s) selecionado(s)',
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _saving
                              ? null
                              : () => _assignSelected(toCoach: true),
                          icon: const Icon(Icons.person_rounded),
                          label: Text('${widget.coachName} planeja',
                              overflow: TextOverflow.ellipsis),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _saving
                              ? null
                              : () => _assignSelected(toCoach: false),
                          icon: const Icon(Icons.supervisor_account_rounded),
                          label: const Text('Eu planejo'),
                          style: ElevatedButton.styleFrom(
                              backgroundColor: _blue,
                              foregroundColor: Colors.white),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: const Color(0xFFFFF8DC),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(17)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(17),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: const Color(0xFF1E3A5F)),
              const SizedBox(height: 9),
              Text(title,
                  style: const TextStyle(
                      color: Color(0xFF1E3A5F), fontWeight: FontWeight.w900)),
              const SizedBox(height: 3),
              Text(subtitle,
                  style: const TextStyle(fontSize: 11, color: Colors.black54)),
            ],
          ),
        ),
      ),
    );
  }
}
