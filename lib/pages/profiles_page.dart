import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_masked_text2/flutter_masked_text2.dart';
import 'dart:convert';
import 'dart:math';
import '../services/auth_service.dart';

class ProfilesPage extends StatefulWidget {
  const ProfilesPage({super.key});

  @override
  State<ProfilesPage> createState() => _ProfilesPageState();
}

class _ProfilesPageState extends State<ProfilesPage> {
  final supabase = Supabase.instance.client;
  List<Map<String, dynamic>> profiles = [];
  bool isLoading = true;
  static const Color olympusBlue = Color(0xFF1E3A5F);
  static const Color olympusGold = Color(0xFFD4AF37);
  static const Color olympusLightBlue = Color(0xFF2C5F8D);

  @override
  void initState() {
    super.initState();
    fetchProfiles();
  }

  Future<void> fetchProfiles() async {
    try {
      setState(() => isLoading = true);
      final response = await supabase
          .from('profiles')
          .select('*')
          .order('created_at', ascending: false);
      setState(() {
        profiles = List<Map<String, dynamic>>.from(response);
        isLoading = false;
      });
    } catch (e) {
      setState(() => isLoading = false);
      debugPrint('❌ Erro ao buscar perfis: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao carregar: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> insertProfile(Map<String, dynamic> data) async {
    try {
      await supabase.from('profiles').insert(data);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Perfil cadastrado com sucesso!'),
            backgroundColor: Colors.green,
          ),
        );
        await fetchProfiles();
      }
    } catch (e) {
      debugPrint('❌ Erro ao inserir: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao cadastrar: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> updateProfile(String id, Map<String, dynamic> data) async {
    try {
      data['updated_at'] = DateTime.now().toIso8601String();
      await supabase.from('profiles').update(data).eq('id', id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Perfil atualizado!'),
            backgroundColor: Colors.green,
          ),
        );
        await fetchProfiles();
      }
    } catch (e) {
      debugPrint('❌ Erro ao atualizar: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao atualizar: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> deleteProfile(String id) async {
    try {
      await supabase.from('profiles').delete().eq('id', id);
      await fetchProfiles();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('🗑️ Perfil removido!'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      debugPrint('❌ Erro ao deletar: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao remover: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void showProfileDialog({Map<String, dynamic>? profile}) {
    showDialog(
      context: context,
      builder: (context) => ProfileFormDialog(
        profile: profile,
        onSave: (data) async {
          if (profile == null) {
            await insertProfile(data);
          } else {
            await updateProfile(profile['id'], data);
          }
        },
      ),
    );
  }

  void _confirmDelete(String id) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar exclusão'),
        content: const Text('Tem certeza que deseja excluir este perfil?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              deleteProfile(id);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
  }

  Future<void> _resetPassword(String userId, String email) async {
    try {
      final response = await supabase.functions.invoke(
        'reset-user-password',
        body: {
          'user_id': userId,
        },
      );

      final data = response.data;
      if (data is! Map || data['password'] == null) {
        throw Exception('Resposta inválida ao resetar senha.');
      }

      final newPassword = data['password'].toString();

      if (mounted) {
        _showNewPasswordDialog(newPassword, email);
      }
    } catch (e) {
      debugPrint('❌ Erro ao resetar senha: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao resetar senha: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showNewPasswordDialog(String password, String email) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.lock_reset, color: olympusGold, size: 28),
            const SizedBox(width: 12),
            const Text('🔑 Senha Resetada!'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('E-mail:'),
            Text(
              email,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: olympusBlue,
              ),
            ),
            const SizedBox(height: 10),
            const Text('Nova senha gerada:'),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: olympusGold.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: olympusGold),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      password,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'monospace',
                        color: olympusBlue,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy, color: olympusGold),
                    tooltip: 'Copiar senha',
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: password));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Senha copiada!'),
                          duration: Duration(seconds: 2),
                          backgroundColor: olympusBlue,
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Envie esta nova senha para o usuário.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Fechar'),
          ),
        ],
      ),
    );
  }

  void _confirmResetPassword(String userId, String email, String name) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Resetar Senha'),
        content: Text(
          'Uma nova senha será gerada para:\n\n$email\n\nO ADMIN deverá copiar e enviar ao usuário.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _resetPassword(userId, email);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: olympusGold,
              foregroundColor: olympusBlue,
            ),
            child: const Text('Gerar Nova Senha'),
          ),
        ],
      ),
    );
  }

  Future<String?> _getCurrentUserType() async {
    try {
      final user = supabase.auth.currentUser;
      if (user == null) return null;
      final response = await supabase
          .from('profiles')
          .select('*')
          .eq('id', user.id)
          .maybeSingle();
      return response?['user_type'];
    } catch (e) {
      debugPrint('Erro ao buscar user_type: $e');
      return null;
    }
  }

  String _getUserTypeLabel(String? userType) {
    switch (userType) {
      case 'admin':
        return 'Administrador';
      case 'coach':
        return 'Técnico';
      case 'athlete':
        return 'Atleta';
      default:
        return 'Membro';
    }
  }

  String _generateRandomPassword() {
    const chars =
        'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#\$%^&*';
    Random random = Random();
    return List.generate(12, (index) => chars[random.nextInt(chars.length)])
        .join();
  }

  void _showPasswordResultDialog(String password, String email) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.check_circle, color: olympusGold, size: 28),
            const SizedBox(width: 12),
            const Text('✅ Usuário Cadastrado!'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('E-mail:'),
            Text(
              email,
              style: const TextStyle(
                  fontWeight: FontWeight.bold, color: olympusBlue),
            ),
            const SizedBox(height: 10),
            const Text('Senha gerada automaticamente:'),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: olympusGold.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: olympusGold),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      password,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'monospace',
                        color: olympusBlue,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy, color: olympusGold),
                    tooltip: 'Copiar senha',
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: password));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Senha copiada!'),
                          duration: Duration(seconds: 2),
                          backgroundColor: olympusBlue,
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Envie esta senha para o usuário.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Fechar'),
          ),
        ],
      ),
    );
  }

  void _showQuickRegisterDialog() {
    final nameCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final phoneCtrl = MaskedTextController(mask: '(00) 00000-0000');
    String selectedType = 'member';
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.person_add_alt_1, color: olympusGold),
            const SizedBox(width: 8),
            const Text('Novo Usuário (Acesso)'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: InputDecoration(
                  labelText: 'Nome Completo',
                  prefixIcon: const Icon(Icons.person, color: olympusGold),
                  border: const OutlineInputBorder(),
                  focusedBorder: OutlineInputBorder(
                    borderSide: const BorderSide(color: olympusGold, width: 2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: emailCtrl,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  labelText: 'E-mail',
                  prefixIcon: const Icon(Icons.email, color: olympusGold),
                  border: const OutlineInputBorder(),
                  focusedBorder: OutlineInputBorder(
                    borderSide: const BorderSide(color: olympusGold, width: 2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: phoneCtrl,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  labelText: 'Telefone',
                  prefixIcon: const Icon(Icons.phone, color: olympusGold),
                  border: const OutlineInputBorder(),
                  focusedBorder: OutlineInputBorder(
                    borderSide: const BorderSide(color: olympusGold, width: 2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: selectedType,
                decoration: InputDecoration(
                  labelText: 'Tipo de Usuário',
                  prefixIcon: const Icon(Icons.badge, color: olympusGold),
                  border: const OutlineInputBorder(),
                  focusedBorder: OutlineInputBorder(
                    borderSide: const BorderSide(color: olympusGold, width: 2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                items: const [
                  DropdownMenuItem(value: 'member', child: Text('Membro')),
                  DropdownMenuItem(value: 'athlete', child: Text('Atleta')),
                  DropdownMenuItem(value: 'coach', child: Text('Técnico')),
                  DropdownMenuItem(
                      value: 'admin', child: Text('Administrador')),
                ],
                onChanged: (val) {
                  if (val != null) selectedType = val;
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton.icon(
            onPressed: () async {
              if (nameCtrl.text.isEmpty || emailCtrl.text.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Preencha nome e e-mail'),
                    backgroundColor: Colors.orange,
                  ),
                );
                return;
              }
              final password = _generateRandomPassword();
              final email = emailCtrl.text.trim();
              try {
                final response = await supabase.auth.signUp(
                  email: email,
                  password: password,
                );
                if (response.user != null) {
                  final userId = response.user!.id;
                  await supabase.from('profiles').upsert({
                    'id': userId,
                    'email': email,
                    'full_name': nameCtrl.text.trim(),
                    'phone': phoneCtrl.text.replaceAll(RegExp(r'\D'), ''),
                    'user_type': selectedType,
                    'updated_at': DateTime.now().toIso8601String(),
                  }, onConflict: 'id');
                  if (!mounted) return;
                  await fetchProfiles();
                  Navigator.pop(context);
                  _showPasswordResultDialog(password, email);
                }
              } catch (e) {
                debugPrint('❌ Erro ao cadastrar: $e');
                if (!mounted) return;
                String errorMessage = 'Erro ao cadastrar';
                if (e.toString().contains('Database error')) {
                  errorMessage =
                      'Erro no banco. Verifique se o trigger está configurado corretamente.';
                } else if (e.toString().contains('User already registered')) {
                  errorMessage = 'E-mail já cadastrado.';
                }
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(errorMessage),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            icon: const Icon(Icons.save),
            label: const Text('Cadastrar'),
            style: ElevatedButton.styleFrom(
              backgroundColor: olympusGold,
              foregroundColor: olympusBlue,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: _getCurrentUserType(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return Scaffold(
            body: Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(olympusGold),
              ),
            ),
          );
        }

        final userType = snapshot.data;

        if (userType != 'admin') {
          return const Scaffold(
            body: Center(
              child: Text(
                'Acesso restrito.',
                style: TextStyle(fontSize: 18),
              ),
            ),
          );
        }

        return Scaffold(
          appBar: AppBar(
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Perfis - Olympus Voleibol',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(
                  '👤 ${_getUserTypeLabel(userType)}',
                  style: TextStyle(
                      fontSize: 12, color: olympusGold.withOpacity(0.9)),
                ),
              ],
            ),
            centerTitle: false,
            backgroundColor: olympusBlue,
            foregroundColor: Colors.white,
            elevation: 2,
            actions: [
              IconButton(
                icon: const Icon(Icons.person_add_alt_1),
                tooltip: 'Cadastrar Usuário (Login)',
                onPressed: _showQuickRegisterDialog,
              ),
              IconButton(
                icon: const Icon(Icons.logout),
                tooltip: 'Sair',
                onPressed: () async {
                  final authService = AuthService();
                  await authService.signOut();
                  if (mounted) {
                    Navigator.pushNamedAndRemoveUntil(
                      context,
                      '/login',
                      (route) => false,
                    );
                  }
                },
              ),
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: fetchProfiles,
              ),
            ],
          ),
          body: isLoading
              ? Center(
                  child: CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(olympusGold),
                  ),
                )
              : profiles.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.people_outline,
                              size: 80, color: Colors.grey[400]),
                          const SizedBox(height: 16),
                          Text(
                            'Nenhum perfil cadastrado',
                            style: TextStyle(
                                fontSize: 16, color: Colors.grey[600]),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      itemCount: profiles.length,
                      padding: const EdgeInsets.all(8),
                      itemBuilder: (context, index) {
                        final profile = profiles[index];
                        final avatarUrl = profile['avatar_url'];
                        return Card(
                          margin: const EdgeInsets.symmetric(
                              vertical: 4, horizontal: 8),
                          elevation: 2,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 8),
                            leading: CircleAvatar(
                              radius: 28,
                              backgroundColor:
                                  _getColorForType(profile['user_type'])
                                      .withOpacity(0.2),
                              backgroundImage: avatarUrl != null &&
                                      avatarUrl.toString().isNotEmpty
                                  ? NetworkImage(avatarUrl)
                                  : null,
                              child: avatarUrl == null ||
                                      avatarUrl.toString().isEmpty
                                  ? Text(
                                      profile['full_name']?[0]?.toUpperCase() ??
                                          '?',
                                      style: TextStyle(
                                        color: _getColorForType(
                                            profile['user_type']),
                                        fontWeight: FontWeight.bold,
                                        fontSize: 20,
                                      ),
                                    )
                                  : null,
                            ),
                            title: Text(
                              profile['full_name'] ?? 'Sem nome',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: olympusBlue,
                                fontSize: 16,
                              ),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SizedBox(height: 4),
                                if (profile['user_type'] != null)
                                  Row(
                                    children: [
                                      Icon(Icons.badge_outlined,
                                          size: 14, color: olympusGold),
                                      const SizedBox(width: 4),
                                      Text(
                                        _getTypeLabel(profile['user_type']),
                                        style: TextStyle(
                                            fontSize: 13,
                                            color: Colors.grey[700]),
                                      ),
                                    ],
                                  ),
                                const SizedBox(height: 2),
                                if (profile['phone'] != null)
                                  Row(
                                    children: [
                                      Icon(Icons.phone,
                                          size: 14, color: olympusGold),
                                      const SizedBox(width: 4),
                                      Text(
                                        _formatPhone(profile['phone']),
                                        style: TextStyle(
                                            fontSize: 13,
                                            color: Colors.grey[700]),
                                      ),
                                    ],
                                  ),
                                const SizedBox(height: 2),
                                if (profile['cpf'] != null)
                                  Row(
                                    children: [
                                      Icon(Icons.credit_card,
                                          size: 14, color: olympusGold),
                                      const SizedBox(width: 4),
                                      Text(
                                        'CPF: ${_formatCpf(profile['cpf'])}',
                                        style: TextStyle(
                                            fontSize: 13,
                                            color: Colors.grey[700]),
                                      ),
                                    ],
                                  ),
                              ],
                            ),
                            trailing: PopupMenuButton<String>(
                              icon: Icon(Icons.more_vert, color: olympusGold),
                              onSelected: (value) {
                                if (value == 'edit') {
                                  showProfileDialog(profile: profile);
                                } else if (value == 'delete') {
                                  _confirmDelete(profile['id']);
                                } else if (value == 'reset_password') {
                                  _confirmResetPassword(
                                    profile['id'],
                                    profile['email'] ?? '',
                                    profile['full_name'] ?? 'Usuário',
                                  );
                                }
                              },
                              itemBuilder: (context) => [
                                const PopupMenuItem(
                                  value: 'edit',
                                  child: Row(
                                    children: [
                                      Icon(Icons.edit,
                                          size: 18, color: olympusBlue),
                                      SizedBox(width: 8),
                                      Text('✏️ Editar'),
                                    ],
                                  ),
                                ),
                                const PopupMenuItem(
                                  value: 'reset_password',
                                  child: Row(
                                    children: [
                                      Icon(Icons.lock_reset,
                                          size: 18, color: olympusGold),
                                      SizedBox(width: 8),
                                      Text('🔑 Resetar Senha'),
                                    ],
                                  ),
                                ),
                                const PopupMenuItem(
                                  value: 'delete',
                                  child: Row(
                                    children: [
                                      Icon(Icons.delete_outline,
                                          size: 18, color: Colors.red),
                                      SizedBox(width: 8),
                                      Text('🗑️ Excluir'),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => showProfileDialog(),
            icon: const Icon(Icons.person_add),
            label: const Text('Novo Perfil'),
            backgroundColor: olympusGold,
            foregroundColor: olympusBlue,
            elevation: 4,
          ),
        );
      },
    );
  }

  String _formatCpf(String? cpf) {
    if (cpf == null) return '';
    final numbers = cpf.replaceAll(RegExp(r'\D'), '');
    if (numbers.length != 11) return cpf;
    return '${numbers.substring(0, 3)}.${numbers.substring(3, 6)}.${numbers.substring(6, 9)}-${numbers.substring(9)}';
  }

  String _formatPhone(String? phone) {
    if (phone == null) return '';
    final numbers = phone.replaceAll(RegExp(r'\D'), '');
    if (numbers.length == 11) {
      return '(${numbers.substring(0, 2)}) ${numbers.substring(2, 7)}-${numbers.substring(7)}';
    } else if (numbers.length == 10) {
      return '(${numbers.substring(0, 2)}) ${numbers.substring(2, 6)}-${numbers.substring(6)}';
    }
    return phone;
  }

  Color _getColorForType(String? type) {
    switch (type) {
      case 'athlete':
        return olympusGold;
      case 'coach':
        return olympusLightBlue;
      case 'admin':
        return Colors.red[700]!;
      default:
        return olympusBlue;
    }
  }

  String _getTypeLabel(String? type) {
    switch (type) {
      case 'athlete':
        return 'Atleta';
      case 'coach':
        return 'Técnico';
      case 'admin':
        return 'Administrador';
      default:
        return 'Membro';
    }
  }
}

class ProfileFormDialog extends StatefulWidget {
  final Map<String, dynamic>? profile;
  final Future<void> Function(Map<String, dynamic> data) onSave;

  const ProfileFormDialog({
    super.key,
    this.profile,
    required this.onSave,
  });

  @override
  State<ProfileFormDialog> createState() => _ProfileFormDialogState();
}

class _ProfileFormDialogState extends State<ProfileFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _picker = ImagePicker();
  late TextEditingController _fullNameController;
  late MaskedTextController _phoneController;
  late TextEditingController _birthDateController;
  late MaskedTextController _rgController;
  late MaskedTextController _cpfController;
  late MaskedTextController _zipCodeController;
  late TextEditingController _streetController;
  late TextEditingController _streetNumberController;
  late TextEditingController _complementController;
  late TextEditingController _neighborhoodController;
  late TextEditingController _cityController;
  late TextEditingController _stateController;
  late TextEditingController _avatarUrlController;
  String _selectedUserType = 'member';
  String _selectedGender = '';
  String _selectedPosition = '';
  XFile? _selectedImage;
  bool _isLoading = false;
  bool _isFetchingCep = false;
  bool _isUploading = false;
  static const Color olympusBlue = Color(0xFF1E3A5F);
  static const Color olympusGold = Color(0xFFD4AF37);
  static const Color olympusLightBlue = Color(0xFF2C5F8D);
  final Map<String, List<Map<String, String>>> _positions = {
    'Masculino': [
      {'value': 'Ponteiro', 'label': 'Ponteiro'},
      {'value': 'Levantador', 'label': 'Levantador'},
      {'value': 'Central', 'label': 'Central'},
      {'value': 'Oposto', 'label': 'Oposto'},
      {'value': 'Líbero', 'label': 'Líbero'},
    ],
    'Feminino': [
      {'value': 'Ponteira', 'label': 'Ponteira'},
      {'value': 'Levantadora', 'label': 'Levantadora'},
      {'value': 'Central', 'label': 'Central'},
      {'value': 'Oposta', 'label': 'Oposta'},
      {'value': 'Líbero', 'label': 'Líbero'},
    ],
  };

  @override
  void initState() {
    super.initState();
    _fullNameController =
        TextEditingController(text: widget.profile?['full_name'] ?? '');
    _phoneController = MaskedTextController(
        mask: '(00) 00000-0000', text: widget.profile?['phone'] ?? '');
    _birthDateController =
        TextEditingController(text: widget.profile?['birth_date'] ?? '');
    _rgController = MaskedTextController(
        mask: '00.000.000-0', text: widget.profile?['rg'] ?? '');
    _cpfController = MaskedTextController(
        mask: '000.000.000-00', text: widget.profile?['cpf'] ?? '');
    _zipCodeController = MaskedTextController(
        mask: '00000-000', text: widget.profile?['zip_code'] ?? '');
    _streetController =
        TextEditingController(text: widget.profile?['street'] ?? '');
    _streetNumberController =
        TextEditingController(text: widget.profile?['street_number'] ?? '');
    _complementController =
        TextEditingController(text: widget.profile?['complement'] ?? '');
    _neighborhoodController =
        TextEditingController(text: widget.profile?['neighborhood'] ?? '');
    _cityController =
        TextEditingController(text: widget.profile?['city'] ?? '');
    _stateController =
        TextEditingController(text: widget.profile?['state'] ?? '');
    _avatarUrlController =
        TextEditingController(text: widget.profile?['avatar_url'] ?? '');
    _selectedUserType = widget.profile?['user_type'] ?? 'member';
    _selectedGender = widget.profile?['gender'] ?? '';
    _selectedPosition = widget.profile?['court_position'] ?? '';
    _zipCodeController.addListener(_onZipCodeChanged);
  }

  void _onZipCodeChanged() {
    final cep = _zipCodeController.text.replaceAll(RegExp(r'\D'), '');
    if (cep.length == 8 && !_isFetchingCep) {
      _fetchAddressByCep(cep);
    }
  }

  Future<void> _fetchAddressByCep(String cep) async {
    setState(() => _isFetchingCep = true);
    try {
      final response =
          await http.get(Uri.parse('https://viacep.com.br/ws/$cep/json/'));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['erro'] == null && mounted) {
          setState(() {
            _streetController.text = data['logradouro'] ?? '';
            _neighborhoodController.text = data['bairro'] ?? '';
            _cityController.text = data['localidade'] ?? '';
            _stateController.text = data['uf'] ?? '';
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ Endereço preenchido automaticamente!'),
              duration: Duration(seconds: 2),
              backgroundColor: olympusBlue,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Erro ao buscar CEP: $e');
    } finally {
      if (mounted) {
        setState(() => _isFetchingCep = false);
      }
    }
  }

  Future<void> _pickImage() async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 85,
      );
      if (image != null) {
        setState(() {
          _selectedImage = image;
        });
      }
    } catch (e) {
      debugPrint('Erro ao selecionar imagem: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Erro ao selecionar imagem'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<String?> _uploadImage() async {
    if (_selectedImage == null) return null;
    if (mounted) {
      setState(() => _isUploading = true);
    }
    try {
      final fileName =
          '${DateTime.now().millisecondsSinceEpoch}_${_fullNameController.text.replaceAll(RegExp(r'\D'), '')}.jpg';
      final supabase = Supabase.instance.client;
      final fileBytes = await _selectedImage!.readAsBytes();
      await supabase.storage.from('avatars').uploadBinary(fileName, fileBytes,
          fileOptions: const FileOptions(upsert: true));
      final publicUrl = supabase.storage.from('avatars').getPublicUrl(fileName);
      return publicUrl;
    } catch (e) {
      debugPrint('Erro ao fazer upload: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao fazer upload: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return null;
    } finally {
      if (mounted) {
        setState(() => _isUploading = false);
      }
    }
  }

  Future<void> _selectDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: olympusGold,
              onPrimary: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null && mounted) {
      setState(() {
        _birthDateController.text = DateFormat('yyyy-MM-dd').format(picked);
      });
    }
  }

  String _removeMask(String? text) {
    if (text == null || text.isEmpty) return '';
    return text.replaceAll(RegExp(r'\D'), '');
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 600;
    if (isMobile) {
      return Scaffold(
        appBar: AppBar(
          title: Text(widget.profile == null ? 'Novo Perfil' : 'Editar Perfil'),
          backgroundColor: olympusBlue,
          foregroundColor: Colors.white,
          elevation: 2,
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: _buildFormContent(context),
      );
    }
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: double.infinity,
        constraints: const BoxConstraints(maxWidth: 600),
        child: _buildFormContent(context),
      ),
    );
  }

  Widget _buildFormContent(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (MediaQuery.of(context).size.width >= 600)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [olympusBlue, olympusLightBlue],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.person, color: olympusGold, size: 28),
                const SizedBox(width: 12),
                Text(
                  widget.profile == null ? 'Novo Perfil' : 'Editar Perfil',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: GestureDetector(
                      onTap: _pickImage,
                      child: Container(
                        width: 120,
                        height: 120,
                        decoration: BoxDecoration(
                          color: olympusGold.withOpacity(0.1),
                          shape: BoxShape.circle,
                          border: Border.all(color: olympusGold, width: 3),
                        ),
                        child: ClipOval(
                          child: _getAvatarImage(),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Center(
                    child: TextButton.icon(
                      onPressed: _pickImage,
                      icon: const Icon(Icons.photo_camera, color: olympusGold),
                      label: const Text(
                        'Selecionar Foto',
                        style: TextStyle(color: olympusBlue),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _fullNameController,
                    decoration: InputDecoration(
                      labelText: 'Nome Completo *',
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.person, color: olympusGold),
                      focusedBorder: OutlineInputBorder(
                        borderSide:
                            const BorderSide(color: olympusGold, width: 2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    validator: (value) =>
                        value?.isEmpty ?? true ? 'Campo obrigatório' : null,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: _selectedUserType,
                    decoration: InputDecoration(
                      labelText: 'Tipo de Usuário *',
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.badge, color: olympusGold),
                      focusedBorder: OutlineInputBorder(
                        borderSide:
                            const BorderSide(color: olympusGold, width: 2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'member', child: Text('Membro')),
                      DropdownMenuItem(value: 'athlete', child: Text('Atleta')),
                      DropdownMenuItem(value: 'coach', child: Text('Técnico')),
                      DropdownMenuItem(
                          value: 'admin', child: Text('Administrador')),
                    ],
                    onChanged: (value) =>
                        setState(() => _selectedUserType = value!),
                    validator: (value) =>
                        value == null ? 'Campo obrigatório' : null,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _cpfController,
                          decoration: InputDecoration(
                            labelText: 'CPF *',
                            border: const OutlineInputBorder(),
                            prefixIcon: const Icon(Icons.credit_card,
                                color: olympusGold),
                            focusedBorder: OutlineInputBorder(
                              borderSide: const BorderSide(
                                  color: olympusGold, width: 2),
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                          keyboardType: TextInputType.number,
                          validator: (value) => _removeMask(value).length != 11
                              ? 'CPF inválido'
                              : null,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextFormField(
                          controller: _rgController,
                          decoration: InputDecoration(
                            labelText: 'RG *',
                            border: const OutlineInputBorder(),
                            prefixIcon: const Icon(Icons.credit_card,
                                color: olympusGold),
                            focusedBorder: OutlineInputBorder(
                              borderSide: const BorderSide(
                                  color: olympusGold, width: 2),
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                          keyboardType: TextInputType.number,
                          validator: (value) => value?.isEmpty ?? true
                              ? 'Campo obrigatório'
                              : null,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _phoneController,
                          decoration: InputDecoration(
                            labelText: 'Telefone *',
                            border: const OutlineInputBorder(),
                            prefixIcon:
                                const Icon(Icons.phone, color: olympusGold),
                            focusedBorder: OutlineInputBorder(
                              borderSide: const BorderSide(
                                  color: olympusGold, width: 2),
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                          keyboardType: TextInputType.phone,
                          validator: (value) => _removeMask(value).length < 10
                              ? 'Telefone inválido'
                              : null,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: _selectedGender.isNotEmpty
                              ? _selectedGender
                              : null,
                          decoration: InputDecoration(
                            labelText: 'Gênero *',
                            border: const OutlineInputBorder(),
                            prefixIcon: const Icon(Icons.transgender,
                                color: olympusGold),
                            focusedBorder: OutlineInputBorder(
                              borderSide: const BorderSide(
                                  color: olympusGold, width: 2),
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                          items: const [
                            DropdownMenuItem(
                                value: 'Masculino', child: Text('Masculino')),
                            DropdownMenuItem(
                                value: 'Feminino', child: Text('Feminino')),
                          ],
                          onChanged: (value) {
                            setState(() {
                              _selectedGender = value ?? '';
                              _selectedPosition = '';
                            });
                          },
                          validator: (value) =>
                              value == null ? 'Campo obrigatório' : null,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _birthDateController,
                    decoration: InputDecoration(
                      labelText: 'Data de Nascimento',
                      border: const OutlineInputBorder(),
                      prefixIcon:
                          const Icon(Icons.calendar_today, color: olympusGold),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.calendar_today,
                            color: olympusGold),
                        onPressed: _selectDate,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderSide:
                            const BorderSide(color: olympusGold, width: 2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    readOnly: true,
                  ),
                  const SizedBox(height: 12),
                  if (_selectedUserType == 'athlete' &&
                      _selectedGender.isNotEmpty)
                    DropdownButtonFormField<String>(
                      value: _selectedPosition.isNotEmpty
                          ? _selectedPosition
                          : null,
                      decoration: InputDecoration(
                        labelText: 'Posição na Quadra',
                        border: const OutlineInputBorder(),
                        prefixIcon: const Icon(Icons.sports_volleyball,
                            color: olympusGold),
                        focusedBorder: OutlineInputBorder(
                          borderSide:
                              const BorderSide(color: olympusGold, width: 2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      items: _positions[_selectedGender]!
                          .map((pos) => DropdownMenuItem(
                                value: pos['value'],
                                child: Text(pos['label']!),
                              ))
                          .toList(),
                      onChanged: (value) =>
                          setState(() => _selectedPosition = value ?? ''),
                    ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Icon(Icons.location_on, color: olympusGold, size: 20),
                      const SizedBox(width: 8),
                      const Text(
                        'Endereço',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: olympusBlue,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _zipCodeController,
                    decoration: InputDecoration(
                      labelText: 'CEP *',
                      border: const OutlineInputBorder(),
                      prefixIcon:
                          const Icon(Icons.location_on, color: olympusGold),
                      suffixIcon: _isFetchingCep
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor:
                                    AlwaysStoppedAnimation<Color>(olympusGold),
                              ),
                            )
                          : null,
                      focusedBorder: OutlineInputBorder(
                        borderSide:
                            const BorderSide(color: olympusGold, width: 2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    keyboardType: TextInputType.number,
                    maxLength: 9,
                    validator: (value) =>
                        _removeMask(value).length != 8 ? 'CEP inválido' : null,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: TextFormField(
                          controller: _streetController,
                          decoration: InputDecoration(
                            labelText: 'Rua *',
                            border: const OutlineInputBorder(),
                            focusedBorder: OutlineInputBorder(
                              borderSide: const BorderSide(
                                  color: olympusGold, width: 2),
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                          validator: (value) => value?.isEmpty ?? true
                              ? 'Campo obrigatório'
                              : null,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextFormField(
                          controller: _streetNumberController,
                          decoration: InputDecoration(
                            labelText: 'Número *',
                            border: const OutlineInputBorder(),
                            focusedBorder: OutlineInputBorder(
                              borderSide: const BorderSide(
                                  color: olympusGold, width: 2),
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                          keyboardType: TextInputType.number,
                          validator: (value) => value?.isEmpty ?? true
                              ? 'Campo obrigatório'
                              : null,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _complementController,
                    decoration: InputDecoration(
                      labelText: 'Complemento',
                      border: const OutlineInputBorder(),
                      focusedBorder: OutlineInputBorder(
                        borderSide:
                            const BorderSide(color: olympusGold, width: 2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _neighborhoodController,
                    decoration: InputDecoration(
                      labelText: 'Bairro *',
                      border: const OutlineInputBorder(),
                      focusedBorder: OutlineInputBorder(
                        borderSide:
                            const BorderSide(color: olympusGold, width: 2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    validator: (value) =>
                        value?.isEmpty ?? true ? 'Campo obrigatório' : null,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: TextFormField(
                          controller: _cityController,
                          decoration: InputDecoration(
                            labelText: 'Cidade *',
                            border: const OutlineInputBorder(),
                            focusedBorder: OutlineInputBorder(
                              borderSide: const BorderSide(
                                  color: olympusGold, width: 2),
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                          validator: (value) => value?.isEmpty ?? true
                              ? 'Campo obrigatório'
                              : null,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextFormField(
                          controller: _stateController,
                          decoration: InputDecoration(
                            labelText: 'Estado *',
                            border: const OutlineInputBorder(),
                            focusedBorder: OutlineInputBorder(
                              borderSide: const BorderSide(
                                  color: olympusGold, width: 2),
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                          maxLength: 2,
                          validator: (value) => value?.isEmpty ?? true
                              ? 'Campo obrigatório'
                              : null,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.grey[100],
            borderRadius: MediaQuery.of(context).size.width >= 600
                ? const BorderRadius.only(
                    bottomLeft: Radius.circular(16),
                    bottomRight: Radius.circular(16),
                  )
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancelar'),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: _isLoading || _isUploading ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: olympusGold,
                  foregroundColor: olympusBlue,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: _isLoading || _isUploading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor:
                              AlwaysStoppedAnimation<Color>(olympusBlue),
                        ),
                      )
                    : Text(
                        widget.profile == null ? 'Cadastrar' : 'Salvar',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _getAvatarImage() {
    if (_selectedImage != null) {
      return FutureBuilder<Uint8List>(
        future: _selectedImage!.readAsBytes(),
        builder: (context, snapshot) {
          if (snapshot.hasData) {
            return Image.memory(snapshot.data!, fit: BoxFit.cover);
          }
          return const Icon(Icons.person, size: 60, color: Colors.grey);
        },
      );
    }
    if (widget.profile?['avatar_url'] != null &&
        widget.profile!['avatar_url'].toString().isNotEmpty) {
      return Image.network(
        widget.profile!['avatar_url'],
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          return const Icon(Icons.person, size: 60, color: Colors.grey);
        },
      );
    }
    return const Icon(Icons.person, size: 60, color: Colors.grey);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    String? avatarUrl = _avatarUrlController.text.trim();
    if (_selectedImage != null) {
      final uploadedUrl = await _uploadImage();
      if (uploadedUrl != null) {
        avatarUrl = uploadedUrl;
      }
    }
    if (!mounted) return;
    final data = <String, dynamic>{
      'full_name': _fullNameController.text.trim(),
      'user_type': _selectedUserType,
      'phone': _removeMask(_phoneController.text),
      if (_birthDateController.text.isNotEmpty)
        'birth_date': _birthDateController.text,
      'rg': _removeMask(_rgController.text),
      'cpf': _removeMask(_cpfController.text),
      'gender': _selectedGender,
      if (_selectedPosition.isNotEmpty) 'court_position': _selectedPosition,
      'zip_code': _removeMask(_zipCodeController.text),
      'street': _streetController.text.trim(),
      'street_number': _streetNumberController.text.trim(),
      'complement': _complementController.text.trim(),
      'neighborhood': _neighborhoodController.text.trim(),
      'city': _cityController.text.trim(),
      'state': _stateController.text.trim().toUpperCase(),
      if (avatarUrl.isNotEmpty) 'avatar_url': avatarUrl,
    };
    await widget.onSave(data);
    if (mounted) {
      Navigator.pop(context);
    }
  }

  @override
  void dispose() {
    _zipCodeController.removeListener(_onZipCodeChanged);
    _fullNameController.dispose();
    _phoneController.dispose();
    _birthDateController.dispose();
    _rgController.dispose();
    _cpfController.dispose();
    _zipCodeController.dispose();
    _streetController.dispose();
    _streetNumberController.dispose();
    _complementController.dispose();
    _neighborhoodController.dispose();
    _cityController.dispose();
    _stateController.dispose();
    _avatarUrlController.dispose();
    super.dispose();
  }
}
