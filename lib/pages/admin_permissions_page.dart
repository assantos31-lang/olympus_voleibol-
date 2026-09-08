import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../theme/olympus_theme.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/permission_service.dart';
import '../services/training_confirmation_deadline_service.dart';

class AdminPermissionsPage extends StatefulWidget {
  const AdminPermissionsPage({Key? key}) : super(key: key);

  @override
  State<AdminPermissionsPage> createState() => _AdminPermissionsPageState();
}

class _AdminPermissionsPageState extends State<AdminPermissionsPage> {
  final SupabaseClient _supabase = Supabase.instance.client;
  final PermissionService _permissionService = PermissionService();
  final TrainingConfirmationDeadlineService _deadlineService =
      TrainingConfirmationDeadlineService();
  final TextEditingController _deadlineHoursController =
      TextEditingController(text: '3');

  List<Map<String, dynamic>> _users = [];
  bool _loading = true;
  String _selectedPage = 'agenda';
  String _selectedGender = 'Todos';

  final Map<String, bool> _savingFilters = {};
  bool _deadlineEnabled = false;
  bool _deadlineLoading = true;
  bool _deadlineSaving = false;

  @override
  void initState() {
    super.initState();
    _loadUsers();
    _loadDeadlineSettings();
  }

  @override
  void dispose() {
    _deadlineHoursController.dispose();
    super.dispose();
  }

  Future<void> _loadDeadlineSettings() async {
    try {
      final settings = await _deadlineService.load();
      if (!mounted) return;
      setState(() {
        _deadlineEnabled = settings.enabled;
        _deadlineHoursController.text = settings.hoursBefore.toString();
        _deadlineLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _deadlineLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao carregar prazo de confirmação: $error'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _saveDeadlineSettings() async {
    final hours = int.tryParse(_deadlineHoursController.text.trim());
    if (hours == null || hours < 1 || hours > 168) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Informe um prazo entre 1 e 168 horas.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    setState(() => _deadlineSaving = true);
    try {
      await _deadlineService.save(
        TrainingConfirmationDeadlineSettings(
          enabled: _deadlineEnabled,
          hoursBefore: hours,
        ),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Prazo de confirmação salvo com sucesso!'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao salvar prazo de confirmação: $error'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _deadlineSaving = false);
    }
  }

  Widget _buildDeadlineSettingsCard() {
    if (_deadlineLoading) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: LinearProgressIndicator(),
      );
    }
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _deadlineEnabled,
              activeThumbColor: olympusGold,
              onChanged: _deadlineSaving
                  ? null
                  : (value) => setState(() => _deadlineEnabled = value),
              title: const Text(
                'Prazo para confirmar treino',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: const Text(
                'Bloqueia a confirmação do atleta quando o prazo termina.',
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _deadlineHoursController,
                    enabled: !_deadlineSaving,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Horas antes do treino',
                      helperText: 'De 1 a 168 horas',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: _deadlineSaving ? null : _saveDeadlineSettings,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: olympusBlue,
                    foregroundColor: Colors.white,
                  ),
                  icon: _deadlineSaving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.save_outlined),
                  label: const Text('Salvar'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _loadUsers() async {
    setState(() => _loading = true);

    final users =
        await _permissionService.getUsersWithPermissions(_selectedPage);

    setState(() {
      _users = users;
      _loading = false;
    });
  }

  String _normalizedGender(dynamic value) {
    final normalized = (value ?? '').toString().trim().toLowerCase();
    if (normalized == 'feminino' || normalized == 'female') return 'Feminino';
    if (normalized == 'masculino' || normalized == 'male') return 'Masculino';
    return '';
  }

  List<Map<String, dynamic>> get _filteredUsers {
    final users = _selectedGender == 'Todos'
        ? List<Map<String, dynamic>>.from(_users)
        : _users
            .where(
              (user) => _normalizedGender(user['gender']) == _selectedGender,
            )
            .toList();
    users.sort((a, b) => (a['full_name'] ?? '')
        .toString()
        .toLowerCase()
        .compareTo((b['full_name'] ?? '').toString().toLowerCase()));
    return users;
  }

  String? _resolveAvatarUrl(dynamic rawValue) {
    final value = (rawValue ?? '').toString().trim();
    if (value.isEmpty) return null;
    if (value.startsWith('http://') || value.startsWith('https://')) {
      return value;
    }
    return _supabase.storage.from('avatars').getPublicUrl(value);
  }

  Widget _buildUserAvatar(Map<String, dynamic> user, String fullName) {
    final avatarUrl = _resolveAvatarUrl(user['avatar_url']);
    final fallback = Container(
      color: olympusGold,
      alignment: Alignment.center,
      child: Text(
        fullName.trim().isEmpty ? '?' : fullName.trim()[0].toUpperCase(),
        style: TextStyle(
          color: olympusBlue,
          fontWeight: FontWeight.bold,
          fontSize: 18,
        ),
      ),
    );
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: olympusGold.withValues(alpha: 0.65),
          width: 2,
        ),
      ),
      child: ClipOval(
        child: avatarUrl == null
            ? fallback
            : CachedNetworkImage(
                imageUrl: avatarUrl,
                fit: BoxFit.cover,
                alignment: Alignment.topCenter,
                memCacheWidth: 240,
                placeholder: (_, __) => Container(
                  color: olympusBlue.withValues(alpha: 0.08),
                ),
                errorWidget: (_, __, ___) => fallback,
              ),
      ),
    );
  }

  Future<void> _abrirPermissoesAgenda(Map<String, dynamic> user) async {
    final userId = user['id']?.toString();
    if (userId == null || userId.isEmpty) return;

    try {
      final filters = await _permissionService.getAgendaFilters(userId);

      bool showMonthFilter = filters['show_month_filter'] ?? true;
      bool showStatusFilter = filters['show_status_filter'] ?? true;
      final allowedEventTypes = filters['allowed_event_types'] != null
          ? List<String>.from(filters['allowed_event_types'])
          : <String>['treino', 'amistoso', 'campeonato'];
      final allowedConvocationStatuses =
          filters['allowed_convocation_statuses'] != null
              ? List<String>.from(filters['allowed_convocation_statuses'])
              : <String>['accepted', 'rejected', 'pending'];

      if (!mounted) return;

      await showDialog(
        context: context,
        builder: (dialogContext) {
          return StatefulBuilder(
            builder: (context, setDialogState) {
              Widget buildSwitchTile({
                required String title,
                required String subtitle,
                required bool value,
                required ValueChanged<bool> onChanged,
                IconData? icon,
              }) {
                return SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: value,
                  onChanged: onChanged,
                  activeColor: olympusGold,
                  title: Row(
                    children: [
                      if (icon != null) ...[
                        Icon(icon, color: olympusBlue, size: 18),
                        const SizedBox(width: 8),
                      ],
                      Expanded(
                        child: Text(
                          title,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                  subtitle: Text(
                    subtitle,
                    style: TextStyle(color: Colors.grey[600], fontSize: 12),
                  ),
                );
              }

              return AlertDialog(
                titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
                contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
                actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                title: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Permissões da Agenda'),
                    const SizedBox(height: 6),
                    Text(
                      user['full_name'] ?? 'Usuário',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[700],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                content: SizedBox(
                  width: 420,
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Filtros visíveis',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: olympusBlue,
                          ),
                        ),
                        const SizedBox(height: 8),
                        buildSwitchTile(
                          title: 'Filtro de mês',
                          subtitle:
                              'Mostra o seletor de mês na agenda do usuário.',
                          value: showMonthFilter,
                          onChanged: (value) => setDialogState(() {
                            showMonthFilter = value;
                          }),
                          icon: Icons.calendar_month,
                        ),
                        buildSwitchTile(
                          title: 'Filtro de status',
                          subtitle:
                              'Mostra os filtros por aceito, recusado e pendente.',
                          value: showStatusFilter,
                          onChanged: (value) => setDialogState(() {
                            showStatusFilter = value;
                          }),
                          icon: Icons.filter_alt_outlined,
                        ),
                        const Divider(height: 24),
                        Text(
                          'Tipos de evento permitidos',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: olympusBlue,
                          ),
                        ),
                        const SizedBox(height: 8),
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          value: allowedEventTypes.contains('treino'),
                          activeColor: olympusGold,
                          title: const Text('Treino'),
                          onChanged: (value) => setDialogState(() {
                            if (value == true) {
                              if (!allowedEventTypes.contains('treino')) {
                                allowedEventTypes.add('treino');
                              }
                            } else {
                              allowedEventTypes.remove('treino');
                            }
                          }),
                        ),
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          value: allowedEventTypes.contains('amistoso'),
                          activeColor: olympusGold,
                          title: const Text('Amistoso'),
                          onChanged: (value) => setDialogState(() {
                            if (value == true) {
                              if (!allowedEventTypes.contains('amistoso')) {
                                allowedEventTypes.add('amistoso');
                              }
                            } else {
                              allowedEventTypes.remove('amistoso');
                            }
                          }),
                        ),
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          value: allowedEventTypes.contains('campeonato'),
                          activeColor: olympusGold,
                          title: const Text('Campeonato'),
                          onChanged: (value) => setDialogState(() {
                            if (value == true) {
                              if (!allowedEventTypes.contains('campeonato')) {
                                allowedEventTypes.add('campeonato');
                              }
                            } else {
                              allowedEventTypes.remove('campeonato');
                            }
                          }),
                        ),
                        const Divider(height: 24),
                        Text(
                          'Status de convocação visíveis',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: olympusBlue,
                          ),
                        ),
                        const SizedBox(height: 8),
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          value:
                              allowedConvocationStatuses.contains('accepted'),
                          activeColor: olympusGold,
                          title: const Text('Aceitou'),
                          onChanged: (value) => setDialogState(() {
                            if (value == true) {
                              if (!allowedConvocationStatuses
                                  .contains('accepted')) {
                                allowedConvocationStatuses.add('accepted');
                              }
                            } else {
                              allowedConvocationStatuses.remove('accepted');
                            }
                          }),
                        ),
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          value:
                              allowedConvocationStatuses.contains('rejected'),
                          activeColor: olympusGold,
                          title: const Text('Recusou'),
                          onChanged: (value) => setDialogState(() {
                            if (value == true) {
                              if (!allowedConvocationStatuses
                                  .contains('rejected')) {
                                allowedConvocationStatuses.add('rejected');
                              }
                            } else {
                              allowedConvocationStatuses.remove('rejected');
                            }
                          }),
                        ),
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          value: allowedConvocationStatuses.contains('pending'),
                          activeColor: olympusGold,
                          title: const Text('Pendente'),
                          onChanged: (value) => setDialogState(() {
                            if (value == true) {
                              if (!allowedConvocationStatuses
                                  .contains('pending')) {
                                allowedConvocationStatuses.add('pending');
                              }
                            } else {
                              allowedConvocationStatuses.remove('pending');
                            }
                          }),
                        ),
                      ],
                    ),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    child: const Text('Cancelar'),
                  ),
                  ElevatedButton(
                    onPressed: () async {
                      if (allowedEventTypes.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content:
                                Text('Selecione ao menos um tipo de evento.'),
                            backgroundColor: Colors.red,
                          ),
                        );
                        return;
                      }

                      if (allowedConvocationStatuses.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                                'Selecione ao menos um status de convocação.'),
                            backgroundColor: Colors.red,
                          ),
                        );
                        return;
                      }

                      Navigator.pop(dialogContext);

                      setState(() {
                        _savingFilters[userId] = true;
                      });

                      try {
                        await _permissionService.updateAgendaFilters(
                          userId: userId,
                          showMonthFilter: showMonthFilter,
                          allowedEventTypes: allowedEventTypes,
                          showStatusFilter: showStatusFilter,
                          allowedConvocationStatuses:
                              allowedConvocationStatuses,
                        );

                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                                'Permissões da agenda salvas com sucesso!'),
                            backgroundColor: Colors.green,
                          ),
                        );
                      } catch (e) {
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content:
                                Text('Erro ao salvar permissões da agenda: $e'),
                            backgroundColor: Colors.red,
                          ),
                        );
                      } finally {
                        if (mounted) {
                          setState(() {
                            _savingFilters.remove(userId);
                          });
                        }
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: olympusBlue,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Salvar'),
                  ),
                ],
              );
            },
          );
        },
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao carregar permissões da agenda: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _togglePermission(String userId, bool currentAccess) async {
    try {
      await _permissionService.updatePermission(
        userId: userId,
        pageName: _selectedPage,
        canAccess: !currentAccess,
      );

      await _loadUsers();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Permissão ${!currentAccess ? 'concedida' : 'revogada'} com sucesso!',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao atualizar permissão: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gerenciar Permissões'),
        backgroundColor: olympusBlue,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          _buildDeadlineSettingsCard(),
          Container(
            margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.94),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: olympusBlue.withValues(alpha: 0.18),
              ),
            ),
            child: Column(
              children: [
                DropdownButtonFormField<String>(
                  initialValue: _selectedPage,
                  isExpanded: true,
                  dropdownColor: Colors.white,
                  style: TextStyle(
                    color: olympusBlue,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Permissão',
                    floatingLabelBehavior: FloatingLabelBehavior.always,
                    labelStyle: TextStyle(
                      color: olympusBlue,
                      fontWeight: FontWeight.w700,
                    ),
                    floatingLabelStyle: TextStyle(
                      color: olympusBlue,
                      fontWeight: FontWeight.w800,
                    ),
                    prefixIcon: Icon(Icons.pageview, color: olympusBlue),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(
                        color: olympusBlue.withValues(alpha: 0.32),
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(color: olympusGold, width: 2),
                    ),
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 18,
                    ),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'agenda', child: Text('Agenda')),
                    DropdownMenuItem(
                      value: 'birthdays',
                      child: Text('Aniversariantes'),
                    ),
                    DropdownMenuItem(
                      value: 'ranking',
                      child: Text('Visível no ranking'),
                    ),
                    DropdownMenuItem(
                      value: 'avaliacoes',
                      child: Text('Visível nas avaliações'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => _selectedPage = value);
                      _loadUsers();
                    }
                  },
                ),
                const SizedBox(height: 18),
                DropdownButtonFormField<String>(
                  initialValue: _selectedGender,
                  isExpanded: true,
                  dropdownColor: Colors.white,
                  style: TextStyle(
                    color: olympusBlue,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Filtrar por gênero',
                    floatingLabelBehavior: FloatingLabelBehavior.always,
                    labelStyle: TextStyle(
                      color: olympusBlue,
                      fontWeight: FontWeight.w700,
                    ),
                    floatingLabelStyle: TextStyle(
                      color: olympusBlue,
                      fontWeight: FontWeight.w800,
                    ),
                    prefixIcon: Icon(Icons.transgender, color: olympusBlue),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(
                        color: olympusBlue.withValues(alpha: 0.32),
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(color: olympusGold, width: 2),
                    ),
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 18,
                    ),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'Todos', child: Text('Todos')),
                    DropdownMenuItem(
                      value: 'Feminino',
                      child: Text('Feminino'),
                    ),
                    DropdownMenuItem(
                      value: 'Masculino',
                      child: Text('Masculino'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => _selectedGender = value);
                    }
                  },
                ),
              ],
            ),
          ),
          Builder(
            builder: (context) {
              final filteredUsers = _filteredUsers;
              return Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : filteredUsers.isEmpty
                        ? Center(
                            child: Text(
                              _users.isEmpty
                                  ? 'Nenhum usuário encontrado'
                                  : 'Nenhum usuário deste gênero',
                            ),
                          )
                        : ListView.builder(
                            itemCount: filteredUsers.length,
                            padding: const EdgeInsets.all(16),
                            itemBuilder: (context, index) {
                              final user = filteredUsers[index];
                              final canAccess = user['can_access'] as bool;
                              final fullName =
                                  (user['full_name'] ?? 'Sem nome').toString();
                              final email = user['email'] ?? '';
                              final userType = user['user_type'] ?? 'member';
                              final gender = _normalizedGender(user['gender']);

                              return Card(
                                margin: const EdgeInsets.only(bottom: 12),
                                elevation: 2,
                                child: ListTile(
                                  leading: _buildUserAvatar(user, fullName),
                                  title: Text(
                                    fullName,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  subtitle: Text(
                                    [
                                      email,
                                      _getUserTypeLabel(userType),
                                      if (gender.isNotEmpty) gender,
                                    ].join(' • '),
                                    style: TextStyle(
                                      color: Colors.grey[600],
                                      fontSize: 12,
                                    ),
                                  ),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (_selectedPage == 'agenda')
                                        IconButton(
                                          tooltip: 'Configurar agenda',
                                          onPressed:
                                              _savingFilters[user['id']] == true
                                                  ? null
                                                  : () =>
                                                      _abrirPermissoesAgenda(
                                                          user),
                                          icon:
                                              _savingFilters[user['id']] == true
                                                  ? const SizedBox(
                                                      width: 18,
                                                      height: 18,
                                                      child:
                                                          CircularProgressIndicator(
                                                        strokeWidth: 2,
                                                      ),
                                                    )
                                                  : const Icon(Icons.tune),
                                          color: olympusBlue,
                                        ),
                                      Switch(
                                        value: canAccess,
                                        onChanged: (value) {
                                          _togglePermission(
                                            user['id'],
                                            canAccess,
                                          );
                                        },
                                        activeThumbColor: olympusGold,
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
              );
            },
          ),
        ],
      ),
    );
  }

  String _getUserTypeLabel(String userType) {
    switch (userType) {
      case 'admin':
        return 'Administrador';
      case 'coach':
        return 'Técnico';
      case 'athlete':
        return 'Atleta';
      case 'member':
        return 'Membro';
      default:
        return userType;
    }
  }
}
