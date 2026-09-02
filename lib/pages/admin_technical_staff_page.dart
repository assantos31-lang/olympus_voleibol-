import 'package:flutter/material.dart';

import '../services/technical_staff_service.dart';
import '../theme/olympus_theme.dart';

class AdminTechnicalStaffPage extends StatefulWidget {
  const AdminTechnicalStaffPage({super.key, this.initialUserId});

  final String? initialUserId;

  @override
  State<AdminTechnicalStaffPage> createState() =>
      _AdminTechnicalStaffPageState();
}

class _AdminTechnicalStaffPageState extends State<AdminTechnicalStaffPage> {
  OlympusBranding get _branding => OlympusBrandingController.instance.branding;
  Color get _blue => _branding.primaryColor;
  Color get _gold => _branding.secondaryColor;
  Color get _background => _branding.backgroundColor;

  final TechnicalStaffService _service = TechnicalStaffService();
  List<Map<String, dynamic>> _profiles = const [];
  List<TechnicalStaffAssignment> _assignments = const [];
  bool _loading = true;
  String? _error;
  bool _openedInitialUser = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      final values = await Future.wait([
        _service.loadAvailableProfiles(),
        _service.loadAssignments(includeInactive: true),
      ]);
      if (!mounted) return;
      setState(() {
        _profiles = values[0] as List<Map<String, dynamic>>;
        _assignments = values[1] as List<TechnicalStaffAssignment>;
        _error = null;
        _loading = false;
      });
      if (!_openedInitialUser && widget.initialUserId != null) {
        _openedInitialUser = true;
        final userId = widget.initialUserId!;
        TechnicalStaffAssignment? current;
        for (final item in _assignments) {
          if (item.userId == userId) {
            current = item;
            break;
          }
        }
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _openEditor(current: current, initialUserId: userId);
          }
        });
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  Map<String, dynamic>? _profile(String userId) {
    for (final profile in _profiles) {
      if ((profile['id'] ?? '').toString() == userId) return profile;
    }
    return null;
  }

  String _name(String userId) {
    final profile = _profile(userId);
    final name = (profile?['full_name'] ?? '').toString().trim();
    if (name.isNotEmpty) return name;
    return (profile?['email'] ?? 'Usuário').toString();
  }

  String _scopeLabel(String value) {
    switch (value) {
      case 'female':
        return 'Equipe feminina';
      case 'male':
        return 'Equipe masculina';
      default:
        return 'Todas as equipes';
    }
  }

  Future<void> _openEditor({
    TechnicalStaffAssignment? current,
    String? initialUserId,
  }) async {
    final result = await showModalBottomSheet<_TechnicalStaffDraft>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: _background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (_) => _TechnicalStaffEditor(
        profiles: _profiles,
        assignments: _assignments,
        current: current,
        initialUserId: initialUserId,
      ),
    );
    if (result == null || !mounted) return;

    try {
      await _service.saveAssignment(
        userId: result.userId,
        technicalRole: result.role,
        supervisorUserId: result.supervisorUserId,
        teamScope: result.teamScope,
        canCreateTraining: result.canCreateTraining,
        canPublishTraining: result.canPublishTraining,
        canApproveTraining: result.canApproveTraining,
        canManageStaff: result.canManageStaff,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profissional liberado com sucesso.')),
      );
      await _load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Não foi possível salvar: $error'),
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
  }

  Future<void> _toggleStatus(TechnicalStaffAssignment item) async {
    final next = item.isActive ? 'suspended' : 'active';
    try {
      await _service.setStatus(item.userId, next);
      await _load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível alterar o acesso: $error')),
      );
    }
  }

  Future<void> _openTeamEditor(
    TechnicalStaffAssignment coordinator,
  ) async {
    final result = await showModalBottomSheet<_CoordinatorTeamResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: _background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (_) => _CoordinatorTeamEditor(
        coordinator: coordinator,
        assignments: _assignments,
        profiles: _profiles,
      ),
    );
    if (result == null || !mounted) return;
    if (result.configureUserId != null) {
      await _openEditor(initialUserId: result.configureUserId);
      if (mounted) await _openTeamEditor(coordinator);
      return;
    }
    final selected = result.selectedUserIds;

    try {
      final candidates = _assignments.where(
        (item) =>
            item.isActive &&
            item.userId != coordinator.userId &&
            !item.isCoordinator,
      );
      for (final item in candidates) {
        final nextSupervisor = selected.contains(item.userId)
            ? coordinator.userId
            : item.supervisorUserId == coordinator.userId
                ? null
                : item.supervisorUserId;
        if (nextSupervisor == item.supervisorUserId) continue;
        await _service.saveAssignment(
          userId: item.userId,
          technicalRole: item.technicalRole,
          supervisorUserId: nextSupervisor,
          teamScope: item.teamScope,
          canCreateTraining: item.canCreateTraining,
          canPublishTraining: item.canPublishTraining,
          canApproveTraining: item.canApproveTraining,
          canManageStaff: item.canManageStaff,
        );
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Equipe do coordenador atualizada.')),
      );
      await _load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Não foi possível atualizar a equipe: $error'),
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final branding = OlympusBrandingController.instance.branding;
    final primary = branding.primaryColor;
    final secondary = branding.secondaryColor;
    final onPrimary = Theme.of(context).colorScheme.onPrimary;
    final active = _assignments.where((item) => item.isActive).toList();
    return Scaffold(
      backgroundColor: branding.backgroundColor,
      appBar: AppBar(
        backgroundColor: primary,
        foregroundColor: onPrimary,
        title: const Text('Equipe Técnica'),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded)),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _loading ? null : () => _openEditor(),
        backgroundColor: secondary,
        foregroundColor: primary,
        icon: const Icon(Icons.person_add_alt_1_rounded),
        label: const Text(
          'Liberar profissional',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _ErrorState(message: _error!, onRetry: _load)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 18, 16, 100),
                    children: [
                      Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: _blue,
                          borderRadius: BorderRadius.circular(22),
                        ),
                        child: Row(
                          children: [
                            CircleAvatar(
                              backgroundColor: Color(0x33D4AF37),
                              child: Icon(Icons.account_tree_rounded,
                                  color: _gold),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${active.length} profissionais ativos',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 18,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  const Text(
                                    'O administrador define a função, a liderança e as permissões.',
                                    style: TextStyle(color: Colors.white70),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 22),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF8DC),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: _gold.withOpacity(0.35)),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.touch_app_rounded, color: _blue),
                            SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Para montar a hierarquia, localize o coordenador e toque em “Definir equipe”.',
                                style: TextStyle(
                                  color: _blue,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        'Cadeia de comando',
                        style: TextStyle(
                          color: _blue,
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 10),
                      if (_assignments.isEmpty)
                        const _EmptyState()
                      else
                        ..._assignments.map(_buildCard),
                    ],
                  ),
                ),
    );
  }

  Widget _buildCard(TechnicalStaffAssignment item) {
    final profile = _profile(item.userId);
    final supervisor =
        item.supervisorUserId == null ? null : _name(item.supervisorUserId!);
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 11),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: _blue.withOpacity(0.10)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 23,
              backgroundColor: item.isActive
                  ? _gold.withOpacity(0.18)
                  : Colors.grey.shade200,
              child: Text(
                _name(item.userId).substring(0, 1).toUpperCase(),
                style: TextStyle(
                  color: item.isActive ? _blue : Colors.grey,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _name(item.userId),
                    style: TextStyle(
                      color: _blue,
                      fontSize: 15.5,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    TechnicalStaffRole.label(item.technicalRole),
                    style: const TextStyle(
                      color: Color(0xFF9A7414),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if ((profile?['email'] ?? '').toString().isNotEmpty)
                    Text(
                      profile!['email'].toString(),
                      style: const TextStyle(color: Colors.black54),
                    ),
                  const SizedBox(height: 7),
                  Text(
                    '${_scopeLabel(item.teamScope)}${supervisor == null ? '' : ' • Responde a $supervisor'}',
                    style: const TextStyle(fontSize: 12.5),
                  ),
                  const SizedBox(height: 7),
                  Wrap(
                    spacing: 6,
                    runSpacing: 5,
                    children: [
                      if (item.canCreateTraining)
                        const _PermissionChip('Preencher planejamento'),
                      if (item.canPublishTraining)
                        const _PermissionChip('Publicar planejamento'),
                      if (item.canApproveTraining)
                        const _PermissionChip('Aprovar'),
                      if (item.canManageStaff)
                        const _PermissionChip('Coordenar equipe'),
                      if (!item.isActive)
                        const _PermissionChip('Acesso suspenso', danger: true),
                    ],
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () => _openEditor(current: item),
                    icon: const Icon(Icons.admin_panel_settings_outlined,
                        size: 17),
                    label: const Text('Função e acessos'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _blue,
                      side: BorderSide(color: _blue.withOpacity(0.24)),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                  if (item.isCoordinator) ...[
                    const SizedBox(height: 7),
                    FilledButton.tonalIcon(
                      onPressed: () => _openTeamEditor(item),
                      icon: const Icon(Icons.group_add_rounded, size: 18),
                      label: Text(
                        'Definir equipe (${_assignments.where((member) => member.isActive && member.supervisorUserId == item.userId).length})',
                      ),
                      style: FilledButton.styleFrom(
                        foregroundColor: _blue,
                        backgroundColor: const Color(0xFFFFF3C4),
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'edit') _openEditor(current: item);
                if (value == 'status') _toggleStatus(item);
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'edit', child: Text('Editar')),
                PopupMenuItem(
                  value: 'status',
                  child: Text(item.isActive ? 'Suspender acesso' : 'Reativar'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CoordinatorTeamEditor extends StatefulWidget {
  const _CoordinatorTeamEditor({
    required this.coordinator,
    required this.assignments,
    required this.profiles,
  });

  final TechnicalStaffAssignment coordinator;
  final List<TechnicalStaffAssignment> assignments;
  final List<Map<String, dynamic>> profiles;

  @override
  State<_CoordinatorTeamEditor> createState() => _CoordinatorTeamEditorState();
}

class _CoordinatorTeamResult {
  const _CoordinatorTeamResult.save(this.selectedUserIds)
      : configureUserId = null;

  const _CoordinatorTeamResult.configure(this.configureUserId)
      : selectedUserIds = const {};

  final Set<String> selectedUserIds;
  final String? configureUserId;
}

class _CoordinatorTeamEditorState extends State<_CoordinatorTeamEditor> {
  OlympusBranding get _branding => OlympusBrandingController.instance.branding;
  Color get _blue => _branding.primaryColor;
  Color get _gold => _branding.secondaryColor;
  late final Set<String> _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.assignments
        .where(
          (item) =>
              item.isActive &&
              item.supervisorUserId == widget.coordinator.userId,
        )
        .map((item) => item.userId)
        .toSet();
  }

  List<String> get _candidateIds {
    final ids = <String>{
      ...widget.profiles
          .map((profile) => (profile['id'] ?? '').toString())
          .where((id) => id.isNotEmpty && id != widget.coordinator.userId),
      ...widget.assignments
          .where(
            (item) =>
                item.isActive &&
                item.userId != widget.coordinator.userId &&
                !item.isCoordinator,
          )
          .map((item) => item.userId),
    }.toList();
    ids.sort((a, b) => _name(a).compareTo(_name(b)));
    return ids;
  }

  TechnicalStaffAssignment? _assignment(String userId) {
    for (final item in widget.assignments) {
      if (item.userId == userId && item.isActive && !item.isCoordinator) {
        return item;
      }
    }
    return null;
  }

  String _name(String userId) {
    for (final profile in widget.profiles) {
      if ((profile['id'] ?? '').toString() != userId) continue;
      final name = (profile['full_name'] ?? '').toString().trim();
      return name.isEmpty
          ? (profile['email'] ?? 'Profissional').toString()
          : name;
    }
    return 'Profissional';
  }

  String? _currentSupervisor(TechnicalStaffAssignment item) {
    final supervisorId = item.supervisorUserId;
    if (supervisorId == null || supervisorId == widget.coordinator.userId) {
      return null;
    }
    return _name(supervisorId);
  }

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      heightFactor: 0.88,
      child: Column(
        children: [
          const SizedBox(height: 10),
          Container(
            width: 44,
            height: 5,
            decoration: BoxDecoration(
              color: Colors.black12,
              borderRadius: BorderRadius.circular(99),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Definir equipe do coordenador',
                  style: TextStyle(
                    color: _blue,
                    fontSize: 21,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  'Selecione os profissionais que ficarão sob a visão de ${_name(widget.coordinator.userId)}.',
                  style: const TextStyle(color: Colors.black54),
                ),
              ],
            ),
          ),
          Expanded(
            child: _candidateIds.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'Cadastre e libere outros técnicos para montar esta equipe.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                    itemCount: _candidateIds.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, index) {
                      final userId = _candidateIds[index];
                      final item = _assignment(userId);
                      if (item == null) {
                        return Card(
                          elevation: 0,
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: Color(0x1FD4AF37),
                              child: Icon(
                                Icons.person_add_alt_1_rounded,
                                color: _blue,
                              ),
                            ),
                            title: Text(
                              _name(userId),
                              style: TextStyle(
                                color: _blue,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            subtitle: const Text(
                              'Técnico cadastrado • acesso ainda não configurado',
                            ),
                            trailing: TextButton(
                              onPressed: () => Navigator.pop(
                                context,
                                _CoordinatorTeamResult.configure(userId),
                              ),
                              child: const Text('Configurar'),
                            ),
                          ),
                        );
                      }
                      final selected = _selected.contains(item.userId);
                      final otherSupervisor = _currentSupervisor(item);
                      return Card(
                        elevation: 0,
                        child: CheckboxListTile(
                          value: selected,
                          activeColor: _gold,
                          checkColor: _blue,
                          title: Text(
                            _name(item.userId),
                            style: TextStyle(
                              color: _blue,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          subtitle: Text(
                            '${TechnicalStaffRole.label(item.technicalRole)}${otherSupervisor == null ? '' : ' • atualmente com $otherSupervisor'}',
                          ),
                          onChanged: (value) => setState(() {
                            if (value == true) {
                              _selected.add(item.userId);
                            } else {
                              _selected.remove(item.userId);
                            }
                          }),
                        ),
                      );
                    },
                  ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 18),
            child: SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton.icon(
                onPressed: () => Navigator.pop(
                  context,
                  _CoordinatorTeamResult.save(Set<String>.from(_selected)),
                ),
                icon: const Icon(Icons.save_rounded),
                label: Text('Salvar equipe (${_selected.length})'),
                style: FilledButton.styleFrom(backgroundColor: _blue),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TechnicalStaffDraft {
  const _TechnicalStaffDraft({
    required this.userId,
    required this.role,
    required this.supervisorUserId,
    required this.teamScope,
    required this.canCreateTraining,
    required this.canPublishTraining,
    required this.canApproveTraining,
    required this.canManageStaff,
  });

  final String userId;
  final String role;
  final String? supervisorUserId;
  final String teamScope;
  final bool canCreateTraining;
  final bool canPublishTraining;
  final bool canApproveTraining;
  final bool canManageStaff;
}

class _TechnicalStaffEditor extends StatefulWidget {
  const _TechnicalStaffEditor({
    required this.profiles,
    required this.assignments,
    this.current,
    this.initialUserId,
  });

  final List<Map<String, dynamic>> profiles;
  final List<TechnicalStaffAssignment> assignments;
  final TechnicalStaffAssignment? current;
  final String? initialUserId;

  @override
  State<_TechnicalStaffEditor> createState() => _TechnicalStaffEditorState();
}

class _TechnicalStaffEditorState extends State<_TechnicalStaffEditor> {
  OlympusBranding get _branding => OlympusBrandingController.instance.branding;
  Color get _primary => _branding.primaryColor;
  String? _userId;
  String _role = TechnicalStaffRole.headCoach;
  String? _supervisorUserId;
  String _teamScope = 'all';
  bool _canCreate = true;
  bool _canPublish = true;
  bool _canApprove = false;
  bool _canManage = false;

  @override
  void initState() {
    super.initState();
    final value = widget.current;
    _userId = value?.userId ?? widget.initialUserId;
    _role = value?.technicalRole ?? TechnicalStaffRole.headCoach;
    _supervisorUserId = value?.supervisorUserId;
    _teamScope = value?.teamScope ?? 'all';
    _canCreate = value?.canCreateTraining ?? true;
    final isCoordinator = _role == TechnicalStaffRole.coordinator;
    _canPublish = isCoordinator;
    _canApprove = isCoordinator;
    _canManage = isCoordinator;
  }

  void _applyRoleDefaults(String value) {
    setState(() {
      _role = value;
      if (value == TechnicalStaffRole.coordinator) {
        _supervisorUserId = null;
        _canCreate = true;
        _canPublish = true;
        _canApprove = true;
        _canManage = true;
      } else if (value == TechnicalStaffRole.headCoach) {
        _canCreate = true;
        _canPublish = false;
        _canApprove = false;
        _canManage = false;
      } else {
        _canCreate = true;
        _canPublish = false;
        _canApprove = false;
        _canManage = false;
      }
    });
  }

  List<TechnicalStaffAssignment> get _possibleSupervisors {
    return widget.assignments.where((item) {
      if (!item.isActive || item.userId == _userId) return false;
      if (_role == TechnicalStaffRole.headCoach) return item.isCoordinator;
      return item.technicalRole == TechnicalStaffRole.coordinator ||
          item.technicalRole == TechnicalStaffRole.headCoach;
    }).toList();
  }

  String _profileName(String userId) {
    for (final profile in widget.profiles) {
      if ((profile['id'] ?? '').toString() == userId) {
        final name = (profile['full_name'] ?? '').toString().trim();
        return name.isEmpty ? (profile['email'] ?? 'Usuário').toString() : name;
      }
    }
    return 'Usuário';
  }

  @override
  Widget build(BuildContext context) {
    final needsSupervisor = _role != TechnicalStaffRole.coordinator;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        14,
        20,
        MediaQuery.viewInsetsOf(context).bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: Colors.black12,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'Liberar profissional',
              style: TextStyle(
                color: _primary,
                fontSize: 21,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: widget.profiles.any(
                (profile) => profile['id']?.toString() == _userId,
              )
                  ? _userId
                  : null,
              decoration: const InputDecoration(
                labelText: 'Profissional',
                helperText: 'Somente usuários cadastrados como Técnico',
                border: OutlineInputBorder(),
              ),
              hint: Text(
                widget.profiles.isEmpty
                    ? 'Nenhum técnico cadastrado'
                    : 'Selecione um técnico',
              ),
              items: widget.profiles
                  .map((profile) => DropdownMenuItem(
                        value: profile['id'].toString(),
                        child: Text(
                          (profile['full_name'] ??
                                  profile['email'] ??
                                  'Usuário')
                              .toString(),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ))
                  .toList(),
              onChanged: widget.current == null
                  ? (value) => setState(() => _userId = value)
                  : null,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _role,
              decoration: const InputDecoration(
                labelText: 'Função na equipe técnica',
                border: OutlineInputBorder(),
              ),
              items: TechnicalStaffRole.values
                  .map((role) => DropdownMenuItem(
                        value: role,
                        child: Text(TechnicalStaffRole.label(role)),
                      ))
                  .toList(),
              onChanged: (value) {
                if (value != null) _applyRoleDefaults(value);
              },
            ),
            const SizedBox(height: 12),
            if (needsSupervisor)
              DropdownButtonFormField<String>(
                value: _possibleSupervisors
                        .any((item) => item.userId == _supervisorUserId)
                    ? _supervisorUserId
                    : null,
                decoration: const InputDecoration(
                  labelText: 'Superior direto',
                  border: OutlineInputBorder(),
                ),
                items: _possibleSupervisors
                    .map((item) => DropdownMenuItem(
                          value: item.userId,
                          child: Text(_profileName(item.userId)),
                        ))
                    .toList(),
                onChanged: (value) => setState(() => _supervisorUserId = value),
              ),
            if (needsSupervisor) const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _teamScope,
              decoration: const InputDecoration(
                labelText: 'Equipes liberadas',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: 'all', child: Text('Todas as equipes')),
                DropdownMenuItem(
                    value: 'female', child: Text('Equipe feminina')),
                DropdownMenuItem(
                    value: 'male', child: Text('Equipe masculina')),
              ],
              onChanged: (value) => setState(() => _teamScope = value ?? 'all'),
            ),
            const SizedBox(height: 16),
            const Text(
              'Permissões',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
            ),
            if (_role == TechnicalStaffRole.coordinator)
              const Padding(
                padding: EdgeInsets.only(top: 6, bottom: 4),
                child: Text(
                  'O coordenador recebe automaticamente todos os acessos abaixo.',
                  style: TextStyle(color: Colors.black54, fontSize: 12.5),
                ),
              ),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('Preencher e editar planejamentos liberados'),
              subtitle: const Text(
                'Não cria o evento. Permite planejar somente os treinos liberados para este profissional.',
              ),
              value: _canCreate,
              onChanged: _role == TechnicalStaffRole.coordinator
                  ? null
                  : (value) => setState(() => _canCreate = value),
            ),
            if (_role == TechnicalStaffRole.coordinator) ...[
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('Publicar planejamento aprovado'),
                subtitle: const Text(
                  'Disponibiliza para a equipe o planejamento que já foi revisado.',
                ),
                value: _canPublish,
                onChanged: null,
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('Aprovar planejamentos'),
                value: _canApprove,
                onChanged: null,
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('Visualizar e coordenar a equipe técnica'),
                value: _canManage,
                onChanged: null,
              ),
            ],
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton.icon(
                onPressed: _userId == null ||
                        (needsSupervisor && _supervisorUserId == null)
                    ? null
                    : () => Navigator.pop(
                          context,
                          _TechnicalStaffDraft(
                            userId: _userId!,
                            role: _role,
                            supervisorUserId: _supervisorUserId,
                            teamScope: _teamScope,
                            canCreateTraining: _canCreate,
                            canPublishTraining: _canPublish,
                            canApproveTraining: _canApprove,
                            canManageStaff: _canManage,
                          ),
                        ),
                icon: const Icon(Icons.verified_user_rounded),
                label: const Text('Salvar e liberar'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PermissionChip extends StatelessWidget {
  const _PermissionChip(this.label, {this.danger = false});

  final String label;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final primary = OlympusBrandingController.instance.branding.primaryColor;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: danger ? Colors.red.shade50 : primary.withOpacity(0.08),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: danger ? Colors.red.shade700 : primary,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const Card(
      elevation: 0,
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(Icons.groups_2_outlined, size: 44, color: Colors.black38),
            SizedBox(height: 10),
            Text(
              'Nenhum profissional liberado ainda.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded,
                size: 48, color: Colors.redAccent),
            const SizedBox(height: 10),
            const Text('Não foi possível carregar a equipe técnica.'),
            const SizedBox(height: 5),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 14),
            FilledButton(
                onPressed: onRetry, child: const Text('Tentar novamente')),
          ],
        ),
      ),
    );
  }
}
