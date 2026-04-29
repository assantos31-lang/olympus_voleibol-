import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/permission_service.dart';

class AdminPermissionsPage extends StatefulWidget {
  const AdminPermissionsPage({Key? key}) : super(key: key);

  @override
  State<AdminPermissionsPage> createState() => _AdminPermissionsPageState();
}

class _AdminPermissionsPageState extends State<AdminPermissionsPage> {
  final SupabaseClient _supabase = Supabase.instance.client;
  final PermissionService _permissionService = PermissionService();

  List<Map<String, dynamic>> _users = [];
  bool _loading = true;
  String _selectedPage = 'agenda';

  final Map<String, bool> _savingFilters = {};

  static const Color olympusBlue = Color(0xFF1E3A5F);
  static const Color olympusGold = Color(0xFFD4AF37);

  @override
  void initState() {
    super.initState();
    _loadUsers();
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
                        const Text(
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
                        const Text(
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
                        const Text(
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
          Container(
            padding: const EdgeInsets.all(16),
            color: olympusBlue.withOpacity(0.1),
            child: Row(
              children: [
                const Icon(Icons.pageview, color: olympusBlue),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButton<String>(
                    value: _selectedPage,
                    isExpanded: true,
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
                ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _users.isEmpty
                    ? const Center(
                        child: Text('Nenhum usuário encontrado'),
                      )
                    : ListView.builder(
                        itemCount: _users.length,
                        padding: const EdgeInsets.all(16),
                        itemBuilder: (context, index) {
                          final user = _users[index];
                          final canAccess = user['can_access'] as bool;
                          final fullName = user['full_name'] ?? 'Sem nome';
                          final email = user['email'] ?? '';
                          final userType = user['user_type'] ?? 'member';

                          return Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            elevation: 2,
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: olympusGold,
                                foregroundColor: olympusBlue,
                                child: Text(
                                  fullName[0].toUpperCase(),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              title: Text(
                                fullName,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              subtitle: Text(
                                '$email • ${_getUserTypeLabel(userType)}',
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
                                      onPressed: _savingFilters[user['id']] ==
                                              true
                                          ? null
                                          : () => _abrirPermissoesAgenda(user),
                                      icon: _savingFilters[user['id']] == true
                                          ? const SizedBox(
                                              width: 18,
                                              height: 18,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                              ),
                                            )
                                          : const Icon(Icons.tune),
                                      color: olympusBlue,
                                    ),
                                  Switch(
                                    value: canAccess,
                                    onChanged: (value) {
                                      _togglePermission(user['id'], canAccess);
                                    },
                                    activeColor: olympusGold,
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
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
