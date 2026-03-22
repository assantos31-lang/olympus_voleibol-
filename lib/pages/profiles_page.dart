import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_masked_text2/flutter_masked_text2.dart';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui';
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

  String _selectedUserTypeFilter = 'all';

  static const Color olympusBlue = Color(0xFF1E3A5F);
  static const Color olympusGold = Color(0xFFD4AF37);
  static const Color olympusLightBlue = Color(0xFF2C5F8D);
  static const Color futuristicDark = Color(0xFF0B1420);
  static const Color futuristicCard = Color(0xFF122235);

  Widget _buildOlympusBackground() {
    return IgnorePointer(
      child: Stack(
        children: [
          Positioned.fill(
            child: Opacity(
              opacity: 0.78,
              child: Image.asset(
                'assets/images/monte_olimpo.png',
                fit: BoxFit.cover,
                alignment: Alignment.topCenter,
              ),
            ),
          ),
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 0.8, sigmaY: 0.8),
              child: Container(color: Colors.transparent),
            ),
          ),
          Positioned.fill(
            child: Container(
              color: const Color(0xFF0B1420).withOpacity(0.46),
            ),
          ),
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color.fromRGBO(9, 17, 27, 0.26),
                    Color.fromRGBO(17, 37, 58, 0.14),
                    Color.fromRGBO(30, 58, 95, 0.28),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    fetchProfiles();
  }

  Future<void> fetchProfiles() async {
    try {
      setState(() => isLoading = true);

      final response = await supabase.from('profiles').select('*');

      final loadedProfiles = List<Map<String, dynamic>>.from(response);
      loadedProfiles.sort((a, b) {
        final nameA = (a['full_name'] ?? '').toString().trim().toLowerCase();
        final nameB = (b['full_name'] ?? '').toString().trim().toLowerCase();
        return nameA.compareTo(nameB);
      });

      setState(() {
        profiles = loadedProfiles;
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

  List<Map<String, dynamic>> get _filteredProfiles {
    final filtered = profiles.where((profile) {
      if (_selectedUserTypeFilter == 'all') return true;
      return (profile['user_type'] ?? '').toString() == _selectedUserTypeFilter;
    }).toList();

    filtered.sort((a, b) {
      final nameA = (a['full_name'] ?? '').toString().trim().toLowerCase();
      final nameB = (b['full_name'] ?? '').toString().trim().toLowerCase();
      return nameA.compareTo(nameB);
    });

    return filtered;
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

  void showPermissionsDialog(Map<String, dynamic> profile) {
    showDialog(
      context: context,
      builder: (context) => PermissionsFormDialog(
        profile: profile,
        onSave: (data) async {
          await updateProfile(profile['id'], data);
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
        body: {'user_id': userId},
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
    final random = Random();
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
                fontWeight: FontWeight.bold,
                color: olympusBlue,
              ),
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
                    value: 'admin',
                    child: Text('Administrador'),
                  ),
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
                    'permissions': {
                      'pages': [],
                      'actions': {},
                      'filters': {},
                    },
                    'show_athlete_info': true,
                    'show_financial_alert': true,
                    'show_presence_summary': true,
                    'show_week_events': true,
                    'show_agenda': true,
                    'show_financial': true,
                    'show_chat': true,
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

  List<Widget> _buildQuickStatusChips(Map<String, dynamic> profile) {
    final chips = <Widget>[];

    final type = _getTypeLabel(profile['user_type']);
    chips.add(_buildChip(type, _getColorForType(profile['user_type'])));

    final permissions = profile['permissions'];
    if (permissions is Map && permissions['pages'] is List) {
      final pages = List<String>.from(permissions['pages']);
      if (pages.contains('agenda')) {
        chips.add(_buildChip('Agenda', olympusGold));
      }
      if (pages.contains('financial')) {
        chips.add(_buildChip('Financeiro', olympusLightBlue));
      }
    }

    if ((profile['show_chat'] ?? false) == true) {
      chips.add(_buildChip('Chat', Colors.tealAccent.shade400));
    }

    return chips;
  }

  Widget _buildChip(String label, Color color) {
    return Container(
      margin: const EdgeInsets.only(right: 6, top: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.14),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: color.withOpacity(0.45)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color is MaterialColor ? color.shade700 : color,
        ),
      ),
    );
  }

  Widget _buildFilterBar() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [
            Color(0xFF122235),
            Color(0xFF18324D),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: olympusGold.withOpacity(0.35)),
        boxShadow: [
          BoxShadow(
            color: olympusGold.withOpacity(0.08),
            blurRadius: 18,
            spreadRadius: 1,
          ),
          BoxShadow(
            color: Colors.black.withOpacity(0.35),
            blurRadius: 22,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: olympusGold.withOpacity(0.16),
              border: Border.all(color: olympusGold.withOpacity(0.35)),
            ),
            child: const Icon(Icons.filter_alt_rounded, color: olympusGold),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: DropdownButtonFormField<String>(
              value: _selectedUserTypeFilter,
              dropdownColor: futuristicCard,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
              iconEnabledColor: olympusGold,
              decoration: InputDecoration(
                labelText: 'Filtrar por tipo de usuário',
                labelStyle: TextStyle(color: Colors.white.withOpacity(0.78)),
                prefixIcon: const Icon(Icons.badge, color: olympusGold),
                filled: true,
                fillColor: const Color(0xFF0E1B2A),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(
                    color: olympusGold.withOpacity(0.25),
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(
                    color: olympusGold.withOpacity(0.25),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(
                    color: olympusGold,
                    width: 1.8,
                  ),
                ),
              ),
              items: const [
                DropdownMenuItem(value: 'all', child: Text('Todos')),
                DropdownMenuItem(
                  value: 'admin',
                  child: Text('Administrador'),
                ),
                DropdownMenuItem(
                  value: 'athlete',
                  child: Text('Atleta'),
                ),
                DropdownMenuItem(
                  value: 'coach',
                  child: Text('Técnico'),
                ),
                DropdownMenuItem(
                  value: 'member',
                  child: Text('Membro'),
                ),
              ],
              onChanged: (value) {
                if (value == null) return;
                setState(() => _selectedUserTypeFilter = value);
              },
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filteredProfiles = _filteredProfiles;

    return FutureBuilder<String?>(
      future: _getCurrentUserType(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return Scaffold(
            backgroundColor: futuristicDark,
            body: Stack(
              children: [
                _buildOlympusBackground(),
                Center(
                  child: CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(olympusGold),
                  ),
                ),
              ],
            ),
          );
        }

        final userType = snapshot.data;

        if (userType != 'admin') {
          return Scaffold(
            backgroundColor: futuristicDark,
            body: Stack(
              children: [
                _buildOlympusBackground(),
                const Center(
                  child: Text(
                    'Acesso restrito.',
                    style: TextStyle(fontSize: 18, color: Colors.white),
                  ),
                ),
              ],
            ),
          );
        }

        return Scaffold(
          backgroundColor: futuristicDark,
          appBar: AppBar(
            toolbarHeight: 74,
            titleSpacing: 16,
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Perfis - Olympus Voleibol',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 2),
                Text(
                  '👤 ${_getUserTypeLabel(userType)}',
                  style: TextStyle(
                    fontSize: 12,
                    color: olympusGold.withOpacity(0.95),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            centerTitle: false,
            backgroundColor: olympusBlue,
            foregroundColor: Colors.white,
            elevation: 0,
            flexibleSpace: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Color(0xFF09111B),
                    Color(0xFF11253A),
                    Color(0xFF1E3A5F),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.person_add_alt_1),
                tooltip: 'Cadastrar Usuário (Login)',
                onPressed: _showQuickRegisterDialog,
              ),
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: fetchProfiles,
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
              const SizedBox(width: 6),
            ],
          ),
          body: Stack(
            children: [
              _buildOlympusBackground(),
              Column(
                children: [
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [
                          Color(0xFF122235),
                          Color(0xFF18324D),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: olympusGold.withOpacity(0.35)),
                      boxShadow: [
                        BoxShadow(
                          color: olympusGold.withOpacity(0.08),
                          blurRadius: 18,
                          spreadRadius: 1,
                        ),
                        BoxShadow(
                          color: Colors.black.withOpacity(0.35),
                          blurRadius: 22,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 54,
                          height: 54,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              colors: [
                                olympusGold.withOpacity(0.95),
                                const Color(0xFFFFE08A),
                              ],
                            ),
                          ),
                          child: const Icon(
                            Icons.manage_accounts_rounded,
                            color: olympusBlue,
                            size: 30,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Gestão de perfis',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${filteredProfiles.length} usuário(s) encontrado(s)',
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.72),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  _buildFilterBar(),
                  Expanded(
                    child: isLoading
                        ? Center(
                            child: CircularProgressIndicator(
                              valueColor:
                                  AlwaysStoppedAnimation<Color>(olympusGold),
                            ),
                          )
                        : filteredProfiles.isEmpty
                            ? Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.people_outline,
                                      size: 80,
                                      color: Colors.grey[400],
                                    ),
                                    const SizedBox(height: 16),
                                    Text(
                                      'Nenhum perfil encontrado',
                                      style: TextStyle(
                                        fontSize: 16,
                                        color: Colors.grey[400],
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            : ListView.builder(
                                itemCount: filteredProfiles.length,
                                padding:
                                    const EdgeInsets.fromLTRB(16, 0, 16, 100),
                                itemBuilder: (context, index) {
                                  final profile = filteredProfiles[index];
                                  final avatarUrl = profile['avatar_url'];

                                  return Container(
                                    margin: const EdgeInsets.only(bottom: 14),
                                    decoration: BoxDecoration(
                                      gradient: const LinearGradient(
                                        colors: [
                                          Color(0xFF132235),
                                          Color(0xFF0E1B2A),
                                        ],
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                      ),
                                      borderRadius: BorderRadius.circular(22),
                                      border: Border.all(
                                        color: _getColorForType(
                                                profile['user_type'])
                                            .withOpacity(0.30),
                                        width: 1.2,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withOpacity(0.28),
                                          blurRadius: 18,
                                          offset: const Offset(0, 8),
                                        ),
                                        BoxShadow(
                                          color: _getColorForType(
                                                  profile['user_type'])
                                              .withOpacity(0.08),
                                          blurRadius: 16,
                                          spreadRadius: 1,
                                        ),
                                      ],
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.all(16),
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Container(
                                            width: 62,
                                            height: 62,
                                            decoration: BoxDecoration(
                                              shape: BoxShape.circle,
                                              gradient: LinearGradient(
                                                colors: [
                                                  _getColorForType(
                                                    profile['user_type'],
                                                  ).withOpacity(0.95),
                                                  Colors.white,
                                                ],
                                                begin: Alignment.topLeft,
                                                end: Alignment.bottomRight,
                                              ),
                                            ),
                                            padding: const EdgeInsets.all(2.5),
                                            child: CircleAvatar(
                                              radius: 28,
                                              backgroundColor: futuristicCard,
                                              backgroundImage:
                                                  avatarUrl != null &&
                                                          avatarUrl
                                                              .toString()
                                                              .isNotEmpty
                                                      ? NetworkImage(avatarUrl)
                                                      : null,
                                              child: avatarUrl == null ||
                                                      avatarUrl
                                                          .toString()
                                                          .isEmpty
                                                  ? Text(
                                                      profile['full_name']?[0]
                                                              ?.toUpperCase() ??
                                                          '?',
                                                      style: TextStyle(
                                                        color: _getColorForType(
                                                          profile['user_type'],
                                                        ),
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        fontSize: 22,
                                                      ),
                                                    )
                                                  : null,
                                            ),
                                          ),
                                          const SizedBox(width: 14),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Row(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Expanded(
                                                      child: Column(
                                                        crossAxisAlignment:
                                                            CrossAxisAlignment
                                                                .start,
                                                        children: [
                                                          Text(
                                                            profile['full_name'] ??
                                                                'Sem nome',
                                                            style:
                                                                const TextStyle(
                                                              fontWeight:
                                                                  FontWeight
                                                                      .bold,
                                                              color:
                                                                  Colors.white,
                                                              fontSize: 17,
                                                            ),
                                                          ),
                                                          const SizedBox(
                                                              height: 4),
                                                          if ((profile[
                                                                      'email'] ??
                                                                  '')
                                                              .toString()
                                                              .isNotEmpty)
                                                            Text(
                                                              profile['email'],
                                                              style: TextStyle(
                                                                fontSize: 13,
                                                                color: Colors
                                                                    .white
                                                                    .withOpacity(
                                                                  0.72,
                                                                ),
                                                              ),
                                                            ),
                                                        ],
                                                      ),
                                                    ),
                                                    PopupMenuButton<String>(
                                                      icon: Icon(
                                                        Icons.more_vert,
                                                        color: olympusGold,
                                                      ),
                                                      color: const Color(
                                                          0xFF162638),
                                                      onSelected: (value) {
                                                        if (value == 'edit') {
                                                          showProfileDialog(
                                                            profile: profile,
                                                          );
                                                        } else if (value ==
                                                            'permissions') {
                                                          showPermissionsDialog(
                                                            profile,
                                                          );
                                                        } else if (value ==
                                                            'delete') {
                                                          _confirmDelete(
                                                            profile['id'],
                                                          );
                                                        } else if (value ==
                                                            'reset_password') {
                                                          _confirmResetPassword(
                                                            profile['id'],
                                                            profile['email'] ??
                                                                '',
                                                            profile['full_name'] ??
                                                                'Usuário',
                                                          );
                                                        }
                                                      },
                                                      itemBuilder: (context) =>
                                                          [
                                                        const PopupMenuItem(
                                                          value: 'edit',
                                                          child: Row(
                                                            children: [
                                                              Icon(
                                                                Icons.edit,
                                                                size: 18,
                                                                color:
                                                                    olympusBlue,
                                                              ),
                                                              SizedBox(
                                                                  width: 8),
                                                              Text(
                                                                'Editar dados',
                                                                style:
                                                                    TextStyle(
                                                                  color: Colors
                                                                      .white,
                                                                ),
                                                              ),
                                                            ],
                                                          ),
                                                        ),
                                                        const PopupMenuItem(
                                                          value: 'permissions',
                                                          child: Row(
                                                            children: [
                                                              Icon(
                                                                Icons
                                                                    .admin_panel_settings,
                                                                size: 18,
                                                                color:
                                                                    olympusGold,
                                                              ),
                                                              SizedBox(
                                                                  width: 8),
                                                              Text(
                                                                'Editar permissões',
                                                                style:
                                                                    TextStyle(
                                                                  color: Colors
                                                                      .white,
                                                                ),
                                                              ),
                                                            ],
                                                          ),
                                                        ),
                                                        const PopupMenuItem(
                                                          value:
                                                              'reset_password',
                                                          child: Row(
                                                            children: [
                                                              Icon(
                                                                Icons
                                                                    .lock_reset,
                                                                size: 18,
                                                                color:
                                                                    olympusGold,
                                                              ),
                                                              SizedBox(
                                                                  width: 8),
                                                              Text(
                                                                'Resetar senha',
                                                                style:
                                                                    TextStyle(
                                                                  color: Colors
                                                                      .white,
                                                                ),
                                                              ),
                                                            ],
                                                          ),
                                                        ),
                                                        const PopupMenuItem(
                                                          value: 'delete',
                                                          child: Row(
                                                            children: [
                                                              Icon(
                                                                Icons
                                                                    .delete_outline,
                                                                size: 18,
                                                                color:
                                                                    Colors.red,
                                                              ),
                                                              SizedBox(
                                                                  width: 8),
                                                              Text(
                                                                'Excluir',
                                                                style:
                                                                    TextStyle(
                                                                  color: Colors
                                                                      .white,
                                                                ),
                                                              ),
                                                            ],
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ],
                                                ),
                                                const SizedBox(height: 10),
                                                Wrap(
                                                  children:
                                                      _buildQuickStatusChips(
                                                    profile,
                                                  ),
                                                ),
                                                const SizedBox(height: 12),
                                                Row(
                                                  children: [
                                                    Icon(
                                                      Icons.phone,
                                                      size: 15,
                                                      color: olympusGold,
                                                    ),
                                                    const SizedBox(width: 6),
                                                    Expanded(
                                                      child: Text(
                                                        _formatPhone(
                                                          profile['phone'],
                                                        ).isEmpty
                                                            ? 'Telefone não informado'
                                                            : _formatPhone(
                                                                profile[
                                                                    'phone'],
                                                              ),
                                                        style: TextStyle(
                                                          fontSize: 13,
                                                          color: Colors.white
                                                              .withOpacity(
                                                                  0.78),
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                const SizedBox(height: 6),
                                                Row(
                                                  children: [
                                                    Icon(
                                                      Icons.credit_card,
                                                      size: 15,
                                                      color: olympusGold,
                                                    ),
                                                    const SizedBox(width: 6),
                                                    Expanded(
                                                      child: Text(
                                                        _formatCpf(
                                                          profile['cpf'],
                                                        ).isEmpty
                                                            ? 'CPF não informado'
                                                            : 'CPF: ${_formatCpf(profile['cpf'])}',
                                                        style: TextStyle(
                                                          fontSize: 13,
                                                          color: Colors.white
                                                              .withOpacity(
                                                                  0.78),
                                                        ),
                                                      ),
                                                    ),
                                                  ],
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
                  ),
                ],
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => showProfileDialog(),
            icon: const Icon(Icons.person_add),
            label: const Text('Novo Perfil'),
            backgroundColor: olympusGold,
            foregroundColor: olympusBlue,
            elevation: 8,
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
        return Colors.redAccent;
      default:
        return Colors.cyanAccent;
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
      mask: '(00) 00000-0000',
      text: widget.profile?['phone'] ?? '',
    );
    _birthDateController =
        TextEditingController(text: widget.profile?['birth_date'] ?? '');
    _rgController = MaskedTextController(
      mask: '00.000.000-0',
      text: widget.profile?['rg'] ?? '',
    );
    _cpfController = MaskedTextController(
      mask: '000.000.000-00',
      text: widget.profile?['cpf'] ?? '',
    );
    _zipCodeController = MaskedTextController(
      mask: '00000-000',
      text: widget.profile?['zip_code'] ?? '',
    );
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

      await supabase.storage.from('avatars').uploadBinary(
            fileName,
            fileBytes,
            fileOptions: const FileOptions(upsert: true),
          );

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
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        width: double.infinity,
        constraints: const BoxConstraints(maxWidth: 760),
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
            padding: const EdgeInsets.all(18),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Color(0xFF09111B),
                  Color(0xFF10253A),
                  Color(0xFF1E3A5F),
                ],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
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
            padding: const EdgeInsets.all(18),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: GestureDetector(
                      onTap: _pickImage,
                      child: Container(
                        width: 126,
                        height: 126,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              olympusGold,
                              const Color(0xFFFFE7A4),
                            ],
                          ),
                          shape: BoxShape.circle,
                        ),
                        padding: const EdgeInsets.all(3),
                        child: Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFF10253A),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.white.withOpacity(0.12),
                            ),
                          ),
                          child: ClipOval(
                            child: _getAvatarImage(),
                          ),
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
                    decoration: _inputDecoration(
                      'Nome Completo *',
                      Icons.person,
                    ),
                    validator: (value) =>
                        value?.isEmpty ?? true ? 'Campo obrigatório' : null,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: _selectedUserType,
                    decoration: _inputDecoration(
                      'Tipo de Usuário *',
                      Icons.badge,
                    ),
                    items: const [
                      DropdownMenuItem(value: 'member', child: Text('Membro')),
                      DropdownMenuItem(value: 'athlete', child: Text('Atleta')),
                      DropdownMenuItem(value: 'coach', child: Text('Técnico')),
                      DropdownMenuItem(
                        value: 'admin',
                        child: Text('Administrador'),
                      ),
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
                          decoration:
                              _inputDecoration('CPF *', Icons.credit_card),
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
                          decoration:
                              _inputDecoration('RG *', Icons.credit_card),
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
                          decoration:
                              _inputDecoration('Telefone *', Icons.phone),
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
                          decoration:
                              _inputDecoration('Gênero *', Icons.transgender),
                          items: const [
                            DropdownMenuItem(
                              value: 'Masculino',
                              child: Text('Masculino'),
                            ),
                            DropdownMenuItem(
                              value: 'Feminino',
                              child: Text('Feminino'),
                            ),
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
                    decoration: _inputDecoration(
                      'Data de Nascimento',
                      Icons.calendar_today,
                    ).copyWith(
                      suffixIcon: IconButton(
                        icon: const Icon(
                          Icons.calendar_today,
                          color: olympusGold,
                        ),
                        onPressed: _selectDate,
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
                      decoration: _inputDecoration(
                        'Posição na Quadra',
                        Icons.sports_volleyball,
                      ),
                      items: _positions[_selectedGender]!
                          .map(
                            (pos) => DropdownMenuItem(
                              value: pos['value'],
                              child: Text(pos['label']!),
                            ),
                          )
                          .toList(),
                      onChanged: (value) =>
                          setState(() => _selectedPosition = value ?? ''),
                    ),
                  const SizedBox(height: 18),
                  _buildSectionTitle('Endereço', Icons.location_on),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _zipCodeController,
                    decoration:
                        _inputDecoration('CEP *', Icons.location_on).copyWith(
                      suffixIcon: _isFetchingCep
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: Padding(
                                padding: EdgeInsets.all(12),
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    olympusGold,
                                  ),
                                ),
                              ),
                            )
                          : null,
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
                          decoration: _inputDecoration('Rua *', Icons.home),
                          validator: (value) => value?.isEmpty ?? true
                              ? 'Campo obrigatório'
                              : null,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextFormField(
                          controller: _streetNumberController,
                          decoration: _inputDecoration('Número *', Icons.pin),
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
                    decoration:
                        _inputDecoration('Complemento', Icons.apartment),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _neighborhoodController,
                    decoration:
                        _inputDecoration('Bairro *', Icons.location_city),
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
                          decoration:
                              _inputDecoration('Cidade *', Icons.public),
                          validator: (value) => value?.isEmpty ?? true
                              ? 'Campo obrigatório'
                              : null,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextFormField(
                          controller: _stateController,
                          decoration: _inputDecoration('Estado *', Icons.flag),
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
                    bottomLeft: Radius.circular(20),
                    bottomRight: Radius.circular(20),
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
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

  InputDecoration _inputDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
      ),
      prefixIcon: Icon(icon, color: olympusGold),
      filled: true,
      fillColor: const Color(0xFFF9FBFD),
      focusedBorder: OutlineInputBorder(
        borderSide: const BorderSide(color: olympusGold, width: 2),
        borderRadius: BorderRadius.circular(14),
      ),
    );
  }

  Widget _buildSectionTitle(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: olympusGold, size: 20),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: olympusBlue,
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
      if (avatarUrl != null && avatarUrl.isNotEmpty) 'avatar_url': avatarUrl,
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

class PermissionsFormDialog extends StatefulWidget {
  final Map<String, dynamic> profile;
  final Future<void> Function(Map<String, dynamic> data) onSave;

  const PermissionsFormDialog({
    super.key,
    required this.profile,
    required this.onSave,
  });

  @override
  State<PermissionsFormDialog> createState() => _PermissionsFormDialogState();
}

class _PermissionsFormDialogState extends State<PermissionsFormDialog> {
  bool _isLoading = false;

  bool _agendaPage = false;
  bool _agendaCreate = false;
  bool _agendaEdit = false;
  bool _agendaDelete = false;
  bool _agendaScore = false;
  bool _agendaExport = false;
  bool _agendaViewConvocados = false;
  bool _agendaViewCheckin = false;

  bool _athleteAgendaViewMonthFilter = true;
  bool _athleteAgendaViewTypeFilter = true;
  bool _athleteAgendaViewStatusFilter = true;
  bool _athleteAgendaViewStatusBadge = true;
  bool _athleteAgendaViewChampionship = true;
  bool _athleteAgendaViewAddress = true;
  bool _athleteAgendaRespondConvocation = true;
  bool _athleteAgendaEditResponse = true;
  bool _athleteAgendaViewCheckin = true;
  bool _athleteAgendaDoCheckin = true;
  bool _athleteAgendaViewDeadlineInfo = true;
  bool _athleteAgendaViewTreino = true;
  bool _athleteAgendaViewAmistoso = true;
  bool _athleteAgendaViewCampeonato = true;

  bool _financialPage = false;
  bool _athleteFinancialViewMonthFilter = true;
  bool _athleteFinancialViewYearFilter = true;
  bool _athleteFinancialViewTypeFilter = true;
  bool _athleteFinancialViewCounters = true;
  bool _athleteFinancialViewStatusBadge = true;
  bool _athleteFinancialViewDueDate = true;
  bool _athleteFinancialViewDescription = true;
  bool _athleteFinancialUploadReceipt = true;
  bool _athleteFinancialViewReceiptStatus = true;

  bool _showAthleteInfo = true;
  bool _showFinancialAlert = true;
  bool _showPresenceSummary = true;
  bool _showWeekEvents = true;
  bool _showAgenda = true;
  bool _showFinancial = true;
  bool _showChat = true;

  String _agendaPermissionLevel = 'none';
  String _financialPermissionLevel = 'none';

  static const Color olympusBlue = Color(0xFF1E3A5F);
  static const Color olympusGold = Color(0xFFD4AF37);
  static const Color futuristicCard = Color(0xFF122235);

  Widget _buildOlympusBackground() {
    return IgnorePointer(
      child: Stack(
        children: [
          Positioned.fill(
            child: Opacity(
              opacity: 0.78,
              child: Image.asset(
                'assets/images/monte_olimpo.png',
                fit: BoxFit.cover,
                alignment: Alignment.topCenter,
              ),
            ),
          ),
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 0.8, sigmaY: 0.8),
              child: Container(color: Colors.transparent),
            ),
          ),
          Positioned.fill(
            child: Container(
              color: const Color(0xFF0B1420).withOpacity(0.46),
            ),
          ),
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color.fromRGBO(9, 17, 27, 0.26),
                    Color.fromRGBO(17, 37, 58, 0.14),
                    Color.fromRGBO(30, 58, 95, 0.28),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static const Color futuristicDark = Color(0xFF0B1420);

  @override
  void initState() {
    super.initState();
    _loadPermissionsFromProfile();
    _loadDashboardVisibilityFromProfile();
    _syncPermissionDropdowns();
  }

  void _loadPermissionsFromProfile() {
    final rawPermissions = widget.profile['permissions'];

    if (rawPermissions is! Map) return;

    final permissions = Map<String, dynamic>.from(rawPermissions);
    final pagesRaw = permissions['pages'];
    final actionsRaw = permissions['actions'];

    final pages = pagesRaw is List ? List<String>.from(pagesRaw) : <String>[];
    final actions =
        actionsRaw is Map<String, dynamic> ? actionsRaw : <String, dynamic>{};

    final agendaActions = actions['agenda'] is Map<String, dynamic>
        ? Map<String, dynamic>.from(actions['agenda'])
        : <String, dynamic>{};

    final athleteAgendaActions =
        actions['athlete_agenda'] is Map<String, dynamic>
            ? Map<String, dynamic>.from(actions['athlete_agenda'])
            : <String, dynamic>{};

    final athleteFinancialActions =
        actions['athlete_financial'] is Map<String, dynamic>
            ? Map<String, dynamic>.from(actions['athlete_financial'])
            : <String, dynamic>{};

    _agendaPage = pages.contains('agenda');
    _financialPage = pages.contains('financial');
    _agendaCreate = agendaActions['create'] == true;
    _agendaEdit = agendaActions['edit'] == true;
    _agendaDelete = agendaActions['delete'] == true;
    _agendaScore = agendaActions['score'] == true;
    _agendaExport = agendaActions['export'] == true;
    _agendaViewConvocados = agendaActions['view_convocados'] == true;
    _agendaViewCheckin = agendaActions['view_checkin'] == true;

    _athleteAgendaViewMonthFilter =
        athleteAgendaActions['view_month_filter'] ?? true;
    _athleteAgendaViewTypeFilter =
        athleteAgendaActions['view_type_filter'] ?? true;
    _athleteAgendaViewStatusFilter =
        athleteAgendaActions['view_status_filter'] ?? true;
    _athleteAgendaViewStatusBadge =
        athleteAgendaActions['view_status_badge'] ?? true;
    _athleteAgendaViewChampionship =
        athleteAgendaActions['view_championship'] ?? true;
    _athleteAgendaViewAddress = athleteAgendaActions['view_address'] ?? true;
    _athleteAgendaRespondConvocation =
        athleteAgendaActions['respond_convocation'] ?? true;
    _athleteAgendaEditResponse = athleteAgendaActions['edit_response'] ?? true;
    _athleteAgendaViewCheckin = athleteAgendaActions['view_checkin'] ?? true;
    _athleteAgendaDoCheckin = athleteAgendaActions['do_checkin'] ?? true;
    _athleteAgendaViewDeadlineInfo =
        athleteAgendaActions['view_deadline_info'] ?? true;
    _athleteAgendaViewTreino = athleteAgendaActions['view_treino'] ?? true;
    _athleteAgendaViewAmistoso = athleteAgendaActions['view_amistoso'] ?? true;
    _athleteAgendaViewCampeonato =
        athleteAgendaActions['view_campeonato'] ?? true;

    _athleteFinancialViewMonthFilter =
        athleteFinancialActions['view_month_filter'] ?? true;
    _athleteFinancialViewYearFilter =
        athleteFinancialActions['view_year_filter'] ?? true;
    _athleteFinancialViewTypeFilter =
        athleteFinancialActions['view_type_filter'] ?? true;
    _athleteFinancialViewCounters =
        athleteFinancialActions['view_counters'] ?? true;
    _athleteFinancialViewStatusBadge =
        athleteFinancialActions['view_status_badge'] ?? true;
    _athleteFinancialViewDueDate =
        athleteFinancialActions['view_due_date'] ?? true;
    _athleteFinancialViewDescription =
        athleteFinancialActions['view_description'] ?? true;
    _athleteFinancialUploadReceipt =
        athleteFinancialActions['upload_receipt'] ?? true;
    _athleteFinancialViewReceiptStatus =
        athleteFinancialActions['view_receipt_status'] ?? true;
  }

  void _loadDashboardVisibilityFromProfile() {
    _showAthleteInfo = widget.profile['show_athlete_info'] ?? true;
    _showFinancialAlert = widget.profile['show_financial_alert'] ?? true;
    _showPresenceSummary = widget.profile['show_presence_summary'] ?? true;
    _showWeekEvents = widget.profile['show_week_events'] ?? true;
    _showAgenda = widget.profile['show_agenda'] ?? true;
    _showFinancial = widget.profile['show_financial'] ?? true;
    _showChat = widget.profile['show_chat'] ?? true;
  }

  void _syncPermissionDropdowns() {
    if (!_agendaPage) {
      _agendaPermissionLevel = 'none';
    } else if (_agendaCreate ||
        _agendaEdit ||
        _agendaDelete ||
        _agendaScore ||
        _agendaExport) {
      _agendaPermissionLevel = 'full';
    } else {
      _agendaPermissionLevel = 'view';
    }

    if (!_financialPage) {
      _financialPermissionLevel = 'none';
    } else {
      _financialPermissionLevel = 'view';
    }
  }

  void _applyAgendaPermissionLevel(String value) {
    setState(() {
      _agendaPermissionLevel = value;

      if (value == 'none') {
        _agendaPage = false;
        _agendaCreate = false;
        _agendaEdit = false;
        _agendaDelete = false;
        _agendaScore = false;
        _agendaExport = false;
        _agendaViewConvocados = false;
        _agendaViewCheckin = false;
        _athleteAgendaViewMonthFilter = false;
        _athleteAgendaViewTypeFilter = false;
        _athleteAgendaViewStatusFilter = false;
        _athleteAgendaViewStatusBadge = false;
        _athleteAgendaViewChampionship = false;
        _athleteAgendaViewAddress = false;
        _athleteAgendaRespondConvocation = false;
        _athleteAgendaEditResponse = false;
        _athleteAgendaViewCheckin = false;
        _athleteAgendaDoCheckin = false;
        _athleteAgendaViewDeadlineInfo = false;
        _athleteAgendaViewTreino = false;
        _athleteAgendaViewAmistoso = false;
        _athleteAgendaViewCampeonato = false;
      } else if (value == 'view') {
        _agendaPage = true;
        _agendaCreate = false;
        _agendaEdit = false;
        _agendaDelete = false;
        _agendaScore = false;
        _agendaExport = false;
        _agendaViewConvocados = true;
        _agendaViewCheckin = true;
        _athleteAgendaViewMonthFilter = true;
        _athleteAgendaViewTypeFilter = true;
        _athleteAgendaViewStatusFilter = true;
        _athleteAgendaViewStatusBadge = true;
        _athleteAgendaViewChampionship = true;
        _athleteAgendaViewAddress = true;
        _athleteAgendaRespondConvocation = true;
        _athleteAgendaEditResponse = true;
        _athleteAgendaViewCheckin = true;
        _athleteAgendaDoCheckin = true;
        _athleteAgendaViewDeadlineInfo = true;
        _athleteAgendaViewTreino = true;
        _athleteAgendaViewAmistoso = true;
        _athleteAgendaViewCampeonato = true;
      } else {
        _agendaPage = true;
        _agendaCreate = true;
        _agendaEdit = true;
        _agendaDelete = true;
        _agendaScore = true;
        _agendaExport = true;
        _agendaViewConvocados = true;
        _agendaViewCheckin = true;
        _athleteAgendaViewMonthFilter = true;
        _athleteAgendaViewTypeFilter = true;
        _athleteAgendaViewStatusFilter = true;
        _athleteAgendaViewStatusBadge = true;
        _athleteAgendaViewChampionship = true;
        _athleteAgendaViewAddress = true;
        _athleteAgendaRespondConvocation = true;
        _athleteAgendaEditResponse = true;
        _athleteAgendaViewCheckin = true;
        _athleteAgendaDoCheckin = true;
        _athleteAgendaViewDeadlineInfo = true;
        _athleteAgendaViewTreino = true;
        _athleteAgendaViewAmistoso = true;
        _athleteAgendaViewCampeonato = true;
      }
    });
  }

  void _applyFinancialPermissionLevel(String value) {
    setState(() {
      _financialPermissionLevel = value;

      if (value == 'none') {
        _financialPage = false;
        _athleteFinancialViewMonthFilter = false;
        _athleteFinancialViewYearFilter = false;
        _athleteFinancialViewTypeFilter = false;
        _athleteFinancialViewCounters = false;
        _athleteFinancialViewStatusBadge = false;
        _athleteFinancialViewDueDate = false;
        _athleteFinancialViewDescription = false;
        _athleteFinancialUploadReceipt = false;
        _athleteFinancialViewReceiptStatus = false;
      } else {
        _financialPage = true;
        _athleteFinancialViewMonthFilter = true;
        _athleteFinancialViewYearFilter = true;
        _athleteFinancialViewTypeFilter = true;
        _athleteFinancialViewCounters = true;
        _athleteFinancialViewStatusBadge = true;
        _athleteFinancialViewDueDate = true;
        _athleteFinancialViewDescription = true;
        _athleteFinancialUploadReceipt = true;
        _athleteFinancialViewReceiptStatus = true;
      }
    });
  }

  Map<String, dynamic> _buildPermissionsJson() {
    final pages = <String>[];
    if (_agendaPage) pages.add('agenda');
    if (_financialPage) pages.add('financial');

    return {
      'pages': pages,
      'actions': {
        'agenda': {
          'create': _agendaPage && _agendaCreate,
          'edit': _agendaPage && _agendaEdit,
          'delete': _agendaPage && _agendaDelete,
          'score': _agendaPage && _agendaScore,
          'export': _agendaPage && _agendaExport,
          'view_convocados': _agendaPage && _agendaViewConvocados,
          'view_checkin': _agendaPage && _agendaViewCheckin,
        },
        'athlete_agenda': {
          'view_month_filter': _agendaPage && _athleteAgendaViewMonthFilter,
          'view_type_filter': _agendaPage && _athleteAgendaViewTypeFilter,
          'view_status_filter': _agendaPage && _athleteAgendaViewStatusFilter,
          'view_status_badge': _agendaPage && _athleteAgendaViewStatusBadge,
          'view_championship': _agendaPage && _athleteAgendaViewChampionship,
          'view_address': _agendaPage && _athleteAgendaViewAddress,
          'respond_convocation':
              _agendaPage && _athleteAgendaRespondConvocation,
          'edit_response': _agendaPage && _athleteAgendaEditResponse,
          'view_checkin': _agendaPage && _athleteAgendaViewCheckin,
          'do_checkin': _agendaPage && _athleteAgendaDoCheckin,
          'view_deadline_info': _agendaPage && _athleteAgendaViewDeadlineInfo,
          'view_treino': _agendaPage && _athleteAgendaViewTreino,
          'view_amistoso': _agendaPage && _athleteAgendaViewAmistoso,
          'view_campeonato': _agendaPage && _athleteAgendaViewCampeonato,
        },
        'athlete_financial': {
          'view_month_filter':
              _financialPage && _athleteFinancialViewMonthFilter,
          'view_year_filter': _financialPage && _athleteFinancialViewYearFilter,
          'view_type_filter': _financialPage && _athleteFinancialViewTypeFilter,
          'view_counters': _financialPage && _athleteFinancialViewCounters,
          'view_status_badge':
              _financialPage && _athleteFinancialViewStatusBadge,
          'view_due_date': _financialPage && _athleteFinancialViewDueDate,
          'view_description':
              _financialPage && _athleteFinancialViewDescription,
          'upload_receipt': _financialPage && _athleteFinancialUploadReceipt,
          'view_receipt_status':
              _financialPage && _athleteFinancialViewReceiptStatus,
        },
      },
      'filters': {},
    };
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 600;

    if (isMobile) {
      return Scaffold(
        backgroundColor: futuristicDark,
        appBar: AppBar(
          title: const Text('Editar permissões'),
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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        width: double.infinity,
        constraints: const BoxConstraints(maxWidth: 760),
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
            padding: const EdgeInsets.all(18),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Color(0xFF09111B),
                  Color(0xFF10253A),
                  Color(0xFF1E3A5F),
                ],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.admin_panel_settings, color: olympusGold, size: 28),
                const SizedBox(width: 12),
                const Text(
                  'Editar permissões',
                  style: TextStyle(
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
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildSectionTitle('Permissões principais', Icons.tune),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  value: _agendaPermissionLevel,
                  dropdownColor: futuristicCard,
                  style: const TextStyle(color: Colors.white),
                  iconEnabledColor: olympusGold,
                  decoration: _inputDecorationDark(
                    'Agenda',
                    Icons.event_note,
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'none',
                      child: Text('Sem acesso'),
                    ),
                    DropdownMenuItem(
                      value: 'view',
                      child: Text('Visualização'),
                    ),
                    DropdownMenuItem(
                      value: 'full',
                      child: Text('Acesso completo'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) _applyAgendaPermissionLevel(value);
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: _financialPermissionLevel,
                  dropdownColor: futuristicCard,
                  style: const TextStyle(color: Colors.white),
                  iconEnabledColor: olympusGold,
                  decoration: _inputDecorationDark(
                    'Financeiro',
                    Icons.account_balance_wallet,
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'none',
                      child: Text('Sem acesso'),
                    ),
                    DropdownMenuItem(
                      value: 'view',
                      child: Text('Visualização'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) _applyFinancialPermissionLevel(value);
                  },
                ),
                const SizedBox(height: 18),
                _buildExpansionCard(
                  title: 'Detalhamento da Agenda',
                  icon: Icons.event,
                  enabled: _agendaPage,
                  children: [
                    _checkbox(
                      'Cadastrar evento',
                      _agendaCreate,
                      _agendaPage,
                      (v) => _agendaCreate = v,
                    ),
                    _checkbox(
                      'Editar evento',
                      _agendaEdit,
                      _agendaPage,
                      (v) => _agendaEdit = v,
                    ),
                    _checkbox(
                      'Excluir evento',
                      _agendaDelete,
                      _agendaPage,
                      (v) => _agendaDelete = v,
                    ),
                    _checkbox(
                      'Inserir / editar placar',
                      _agendaScore,
                      _agendaPage,
                      (v) => _agendaScore = v,
                    ),
                    _checkbox(
                      'Exportar convocados',
                      _agendaExport,
                      _agendaPage,
                      (v) => _agendaExport = v,
                    ),
                    _checkbox(
                      'Ver convocados',
                      _agendaViewConvocados,
                      _agendaPage,
                      (v) => _agendaViewConvocados = v,
                    ),
                    _checkbox(
                      'Ver status de check-in',
                      _agendaViewCheckin,
                      _agendaPage,
                      (v) => _agendaViewCheckin = v,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _buildExpansionCard(
                  title: 'Agenda do Atleta',
                  icon: Icons.sports_volleyball,
                  enabled: _agendaPage,
                  children: [
                    _checkbox(
                      'Ver filtro de mês',
                      _athleteAgendaViewMonthFilter,
                      _agendaPage,
                      (v) => _athleteAgendaViewMonthFilter = v,
                    ),
                    _checkbox(
                      'Ver filtro de tipo',
                      _athleteAgendaViewTypeFilter,
                      _agendaPage,
                      (v) => _athleteAgendaViewTypeFilter = v,
                    ),
                    _checkbox(
                      'Ver filtro de status',
                      _athleteAgendaViewStatusFilter,
                      _agendaPage,
                      (v) => _athleteAgendaViewStatusFilter = v,
                    ),
                    _checkbox(
                      'Ver badge de status',
                      _athleteAgendaViewStatusBadge,
                      _agendaPage,
                      (v) => _athleteAgendaViewStatusBadge = v,
                    ),
                    _checkbox(
                      'Ver campeonato',
                      _athleteAgendaViewChampionship,
                      _agendaPage,
                      (v) => _athleteAgendaViewChampionship = v,
                    ),
                    _checkbox(
                      'Ver endereço',
                      _athleteAgendaViewAddress,
                      _agendaPage,
                      (v) => _athleteAgendaViewAddress = v,
                    ),
                    _checkbox(
                      'Responder convocação',
                      _athleteAgendaRespondConvocation,
                      _agendaPage,
                      (v) => _athleteAgendaRespondConvocation = v,
                    ),
                    _checkbox(
                      'Editar resposta',
                      _athleteAgendaEditResponse,
                      _agendaPage,
                      (v) => _athleteAgendaEditResponse = v,
                    ),
                    _checkbox(
                      'Ver check-in',
                      _athleteAgendaViewCheckin,
                      _agendaPage,
                      (v) => _athleteAgendaViewCheckin = v,
                    ),
                    _checkbox(
                      'Permitir check-in',
                      _athleteAgendaDoCheckin,
                      _agendaPage,
                      (v) => _athleteAgendaDoCheckin = v,
                    ),
                    _checkbox(
                      'Ver prazo de edição',
                      _athleteAgendaViewDeadlineInfo,
                      _agendaPage,
                      (v) => _athleteAgendaViewDeadlineInfo = v,
                    ),
                    _checkbox(
                      'Ver Treino',
                      _athleteAgendaViewTreino,
                      _agendaPage,
                      (v) => _athleteAgendaViewTreino = v,
                    ),
                    _checkbox(
                      'Ver Amistoso',
                      _athleteAgendaViewAmistoso,
                      _agendaPage,
                      (v) => _athleteAgendaViewAmistoso = v,
                    ),
                    _checkbox(
                      'Ver Campeonato',
                      _athleteAgendaViewCampeonato,
                      _agendaPage,
                      (v) => _athleteAgendaViewCampeonato = v,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _buildExpansionCard(
                  title: 'Financeiro do Atleta',
                  icon: Icons.payments,
                  enabled: _financialPage,
                  children: [
                    _checkbox(
                      'Ver filtro de mês',
                      _athleteFinancialViewMonthFilter,
                      _financialPage,
                      (v) => _athleteFinancialViewMonthFilter = v,
                    ),
                    _checkbox(
                      'Ver filtro de ano',
                      _athleteFinancialViewYearFilter,
                      _financialPage,
                      (v) => _athleteFinancialViewYearFilter = v,
                    ),
                    _checkbox(
                      'Ver filtro de tipo',
                      _athleteFinancialViewTypeFilter,
                      _financialPage,
                      (v) => _athleteFinancialViewTypeFilter = v,
                    ),
                    _checkbox(
                      'Ver contadores',
                      _athleteFinancialViewCounters,
                      _financialPage,
                      (v) => _athleteFinancialViewCounters = v,
                    ),
                    _checkbox(
                      'Ver badge de status',
                      _athleteFinancialViewStatusBadge,
                      _financialPage,
                      (v) => _athleteFinancialViewStatusBadge = v,
                    ),
                    _checkbox(
                      'Ver vencimento',
                      _athleteFinancialViewDueDate,
                      _financialPage,
                      (v) => _athleteFinancialViewDueDate = v,
                    ),
                    _checkbox(
                      'Ver descrição',
                      _athleteFinancialViewDescription,
                      _financialPage,
                      (v) => _athleteFinancialViewDescription = v,
                    ),
                    _checkbox(
                      'Permitir envio de comprovante',
                      _athleteFinancialUploadReceipt,
                      _financialPage,
                      (v) => _athleteFinancialUploadReceipt = v,
                    ),
                    _checkbox(
                      'Ver status do comprovante',
                      _athleteFinancialViewReceiptStatus,
                      _financialPage,
                      (v) => _athleteFinancialViewReceiptStatus = v,
                    ),
                  ],
                ),
                if ((widget.profile['user_type'] ?? '') == 'athlete') ...[
                  const SizedBox(height: 12),
                  _buildExpansionCard(
                    title: 'Dashboard do Atleta',
                    icon: Icons.dashboard_customize,
                    enabled: true,
                    children: [
                      _checkboxSimple(
                        'Exibir card do atleta',
                        _showAthleteInfo,
                        (v) => _showAthleteInfo = v,
                      ),
                      _checkboxSimple(
                        'Exibir alerta financeiro',
                        _showFinancialAlert,
                        (v) => _showFinancialAlert = v,
                      ),
                      _checkboxSimple(
                        'Exibir resumo de presença',
                        _showPresenceSummary,
                        (v) => _showPresenceSummary = v,
                      ),
                      _checkboxSimple(
                        'Exibir eventos da semana',
                        _showWeekEvents,
                        (v) => _showWeekEvents = v,
                      ),
                      _checkboxSimple(
                        'Exibir card Minha Agenda',
                        _showAgenda,
                        (v) => _showAgenda = v,
                      ),
                      _checkboxSimple(
                        'Exibir card Financeiro',
                        _showFinancial,
                        (v) => _showFinancial = v,
                      ),
                      _checkboxSimple(
                        'Exibir botão Chat',
                        _showChat,
                        (v) => _showChat = v,
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.grey[100],
            borderRadius: MediaQuery.of(context).size.width >= 600
                ? const BorderRadius.only(
                    bottomLeft: Radius.circular(20),
                    bottomRight: Radius.circular(20),
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
                onPressed: _isLoading ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: olympusGold,
                  foregroundColor: olympusBlue,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor:
                              AlwaysStoppedAnimation<Color>(olympusBlue),
                        ),
                      )
                    : const Text(
                        'Salvar permissões',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  InputDecoration _inputDecorationDark(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(color: Colors.white.withOpacity(0.78)),
      prefixIcon: Icon(icon, color: olympusGold),
      filled: true,
      fillColor: const Color(0xFF0E1B2A),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: olympusGold.withOpacity(0.25)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: olympusGold.withOpacity(0.25)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: olympusGold, width: 1.8),
      ),
    );
  }

  Widget _buildSectionTitle(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: olympusGold, size: 20),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: olympusBlue,
          ),
        ),
      ],
    );
  }

  Widget _buildExpansionCard({
    required String title,
    required IconData icon,
    required bool enabled,
    required List<Widget> children,
  }) {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [
            Color(0xFF122235),
            Color(0xFF18324D),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: enabled
              ? olympusGold.withOpacity(0.35)
              : Colors.white.withOpacity(0.08),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.28),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          iconColor: olympusGold,
          collapsedIconColor: olympusGold,
          leading: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: olympusGold.withOpacity(0.14),
              shape: BoxShape.circle,
              border: Border.all(color: olympusGold.withOpacity(0.30)),
            ),
            child: Icon(
              icon,
              color: enabled ? olympusGold : Colors.grey,
              size: 20,
            ),
          ),
          title: Text(
            title,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: enabled ? Colors.white : Colors.white.withOpacity(0.65),
            ),
          ),
          subtitle: Text(
            enabled ? 'Toque para expandir' : 'Habilite no nível principal',
            style: TextStyle(
              fontSize: 12,
              color: Colors.white.withOpacity(0.65),
            ),
          ),
          children: children,
        ),
      ),
    );
  }

  Widget _checkbox(String title, bool value, bool enabled, Function(bool) set) {
    return CheckboxListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      title: Text(
        title,
        style: TextStyle(
          color: enabled ? Colors.white : Colors.white.withOpacity(0.40),
        ),
      ),
      value: value,
      activeColor: olympusGold,
      checkColor: olympusBlue,
      onChanged: enabled ? (v) => setState(() => set(v ?? false)) : null,
      controlAffinity: ListTileControlAffinity.leading,
    );
  }

  Widget _checkboxSimple(String title, bool value, Function(bool) set) {
    return CheckboxListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      title: Text(
        title,
        style: const TextStyle(color: Colors.white),
      ),
      value: value,
      activeColor: olympusGold,
      checkColor: olympusBlue,
      onChanged: (v) => setState(() => set(v ?? false)),
      controlAffinity: ListTileControlAffinity.leading,
    );
  }

  Future<void> _save() async {
    setState(() => _isLoading = true);

    final data = <String, dynamic>{
      'permissions': _buildPermissionsJson(),
      'show_athlete_info': _showAthleteInfo,
      'show_financial_alert': _showFinancialAlert,
      'show_presence_summary': _showPresenceSummary,
      'show_week_events': _showWeekEvents,
      'show_agenda': _showAgenda,
      'show_financial': _showFinancial,
      'show_chat': _showChat,
    };

    await widget.onSave(data);

    if (mounted) {
      Navigator.pop(context);
    }
  }
}
