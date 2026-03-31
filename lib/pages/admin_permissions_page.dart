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
          // Seletor de página
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
                      // Adicione mais páginas conforme necessário
                      // DropdownMenuItem(value: 'financeiro', child: Text('Financeiro')),
                      // DropdownMenuItem(value: 'competicoes', child: Text('Competições')),
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

          // Lista de usuários
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
                              trailing: Switch(
                                value: canAccess,
                                onChanged: (value) {
                                  _togglePermission(user['id'], canAccess);
                                },
                                activeColor: olympusGold,
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
