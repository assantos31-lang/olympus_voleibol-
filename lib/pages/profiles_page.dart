import 'package:flutter/material.dart';
import '../theme/olympus_theme.dart';
import 'dart:ui';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_masked_text2/flutter_masked_text2.dart';
import 'dart:convert';
import 'dart:math';
import '../services/auth_service.dart';
import '../services/permission_service.dart';
import '../services/role_service.dart';
import '../services/organization_context_service.dart';
import '../services/organization_storage_service.dart';
import '../widgets/role_manager_widget.dart';
import 'admin_technical_staff_page.dart';

class ProfilesPage extends StatefulWidget {
  const ProfilesPage({super.key});

  @override
  State<ProfilesPage> createState() => _ProfilesPageState();
}

class _ProfilesPageState extends State<ProfilesPage> {
  final supabase = Supabase.instance.client;
  final PermissionService _permissionService = PermissionService();
  final RoleService _roleService = RoleService();
  List<Map<String, dynamic>> profiles = [];
  bool isLoading = true;
  bool _isCheckingAccess = true;
  String _selectedGenderFilter = 'Todos';
  String _selectedUserTypeFilter = 'Todos';
  bool _showInactiveUsers = false;
  final TextEditingController _profilesSearchController =
      TextEditingController();
  String _profilesSearchQuery = '';
  OlympusBranding get _branding => OlympusBrandingController.instance.branding;
  Color get olympusBlue => _branding.primaryColor;
  Color get olympusGold => _branding.secondaryColor;
  Color get olympusLightBlue =>
      Color.lerp(_branding.primaryColor, _branding.surfaceColor, 0.20)!;

  @override
  void initState() {
    super.initState();
    _checkAdminAccess();
  }

  @override
  void dispose() {
    _profilesSearchController.dispose();
    super.dispose();
  }

  Future<void> _checkAdminAccess() async {
    try {
      final user = supabase.auth.currentUser;
      if (user == null) {
        if (mounted) {
          Navigator.pushNamedAndRemoveUntil(
            context,
            '/login',
            (route) => false,
          );
        }
        return;
      }
      final hasAdminRole = await _roleService.hasRole(user.id, 'admin');
      if (!mounted) return;
      if (!hasAdminRole) {
        Navigator.pushNamedAndRemoveUntil(
          context,
          '/dashboard',
          (route) => false,
        );
        return;
      }
      setState(() {
        _isCheckingAccess = false;
      });
      fetchProfiles();
    } catch (e) {
      debugPrint('Erro ao validar acesso aos perfis: $e');
      if (mounted) {
        Navigator.pushNamedAndRemoveUntil(
          context,
          '/dashboard',
          (route) => false,
        );
      }
    }
  }

  Future<void> fetchProfiles() async {
    try {
      setState(() => isLoading = true);
      final response = await supabase
          .from('profiles')
          .select()
          .order('full_name', ascending: true);

      final loadedProfiles = List<Map<String, dynamic>>.from(response);
      final rolesByUser = <String, List<String>>{};

      try {
        final roleRows = await supabase
            .from('user_roles')
            .select('user_id, role')
            .eq('is_active', true);

        for (final row in List<Map<String, dynamic>>.from(roleRows)) {
          final userId = (row['user_id'] ?? '').toString().trim();
          final role = (row['role'] ?? '').toString().trim();
          if (userId.isEmpty || role.isEmpty) continue;
          rolesByUser.putIfAbsent(userId, () => <String>[]).add(role);
        }
      } catch (e) {
        debugPrint('Nao foi possivel carregar papeis adicionais: $e');
      }

      for (final profile in loadedProfiles) {
        final userId = (profile['id'] ?? '').toString().trim();
        final primaryRole = (profile['user_type'] ?? 'member').toString();
        final roles = rolesByUser[userId] ?? <String>[];
        if (!roles.contains(primaryRole)) roles.add(primaryRole);
        profile['active_roles'] = roles.toSet().toList();
      }

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
        fetchProfiles();
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
        fetchProfiles();
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

  Future<void> deleteProfile(Map<String, dynamic> profile) async {
    final id = (profile['id'] ?? '').toString();
    final email = (profile['email'] ?? '').toString().trim();
    try {
      final session = supabase.auth.currentSession;
      if (session == null) {
        throw Exception('Sessão expirada. Entre novamente.');
      }
      final response = await supabase.functions.invoke(
        'delete-user-account',
        headers: {'Authorization': 'Bearer ${session.accessToken}'},
        body: {
          'user_id': id,
          'confirmation_email': email,
        },
      );
      if (response.status < 200 || response.status >= 300) {
        final data = response.data;
        final message = data is Map && data['error'] != null
            ? data['error'].toString()
            : 'Falha ao excluir a conta no Supabase.';
        throw Exception(message);
      }
      RoleService.invalidateUser(id);
      await fetchProfiles();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Conta, e-mail e dados vinculados removidos.'),
            backgroundColor: Colors.green,
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

  bool _isProfileActive(Map<String, dynamic> profile) {
    return profile['is_active'] != false;
  }

  List<String> _rolesForProfile(Map<String, dynamic> profile) {
    final rawRoles = profile['active_roles'];
    final roles = rawRoles is List
        ? rawRoles
            .map((role) => role.toString().trim())
            .where((role) => role.isNotEmpty)
            .toSet()
            .toList()
        : <String>[];
    final primaryRole = (profile['user_type'] ?? 'member').toString().trim();
    if (primaryRole.isNotEmpty && !roles.contains(primaryRole)) {
      roles.add(primaryRole);
    }
    return roles;
  }

  String _visualRoleForProfile(Map<String, dynamic> profile) {
    final roles = _rolesForProfile(profile);
    if (roles.contains('athlete')) return 'athlete';
    if (roles.contains('coach')) return 'coach';
    if (roles.contains('admin')) return 'admin';
    return roles.isEmpty ? 'member' : roles.first;
  }

  Future<void> _setProfileActive(
    Map<String, dynamic> profile,
    bool isActive,
  ) async {
    final id = (profile['id'] ?? '').toString();
    if (id.isEmpty) return;

    final name = (profile['full_name'] ?? 'usuário').toString();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(isActive ? 'Reativar usuário' : 'Inativar usuário'),
        content: Text(
          isActive
              ? 'Deseja reativar o acesso de $name ao aplicativo?'
              : 'Deseja tornar $name inativo? O acesso ao aplicativo ficará restrito imediatamente.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(isActive ? 'Reativar' : 'Inativar'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    await updateProfile(id, {'is_active': isActive});
  }

  static const Map<int, String> _trainingWeekdayLabels = {
    1: 'Seg',
    2: 'Ter',
    3: 'Qua',
    4: 'Qui',
    5: 'Sex',
    6: 'Sáb',
    7: 'Dom',
  };

  List<int> _profileTrainingWeekdays(Map<String, dynamic> profile) {
    final raw = profile['training_weekdays'];
    if (raw is! List) return <int>[];
    return raw
        .map((value) => int.tryParse(value.toString()))
        .whereType<int>()
        .where((day) => day >= 1 && day <= 7)
        .toSet()
        .toList()
      ..sort();
  }

  Future<void> _showTrainingDaysDialog(Map<String, dynamic> profile) async {
    final userId = (profile['id'] ?? '').toString();
    if (userId.isEmpty) return;

    final selectedDays = _profileTrainingWeekdays(profile).toSet();
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFFF7FAFC),
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          title: Row(
            children: [
              CircleAvatar(
                backgroundColor: Color(0xFFE8F0F8),
                child: Icon(Icons.calendar_month_rounded, color: olympusBlue),
              ),
              SizedBox(width: 12),
              Expanded(child: Text('Dias de treino')),
            ],
          ),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  (profile['full_name'] ?? 'Atleta').toString(),
                  style: TextStyle(
                    color: olympusBlue,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Ao criar um treino, o atleta será selecionado automaticamente conforme o dia e o gênero do evento.',
                  style: TextStyle(color: Colors.black54, fontSize: 13),
                ),
                const SizedBox(height: 18),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _trainingWeekdayLabels.entries.map((entry) {
                    final selected = selectedDays.contains(entry.key);
                    return FilterChip(
                      label: Text(entry.value),
                      selected: selected,
                      selectedColor: olympusGold,
                      checkmarkColor: olympusBlue,
                      onSelected: (value) {
                        setDialogState(() {
                          value
                              ? selectedDays.add(entry.key)
                              : selectedDays.remove(entry.key);
                        });
                      },
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancelar'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(dialogContext, true),
              icon: const Icon(Icons.save_outlined),
              label: const Text('Salvar dias'),
            ),
          ],
        ),
      ),
    );

    if (saved != true) return;
    final orderedDays = selectedDays.toList()..sort();
    await supabase
        .from('profiles')
        .update({'training_weekdays': orderedDays}).eq('id', userId);
    profile['training_weekdays'] = orderedDays;
    await fetchProfiles();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Dias de treino atualizados.'),
        backgroundColor: Colors.green,
      ),
    );
  }

  Future<void> _confirmDelete(Map<String, dynamic> profile) async {
    final id = (profile['id'] ?? '').toString();
    final email = (profile['email'] ?? '').toString().trim();
    final name = (profile['full_name'] ?? 'Usuário').toString();
    if (id == supabase.auth.currentUser?.id) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Para excluir sua própria conta, use Meu Perfil.',
          ),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    if (email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Este usuário não possui e-mail para confirmação.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final controller = TextEditingController();
    var deleting = false;
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.red),
              SizedBox(width: 10),
              Expanded(child: Text('Exclusão permanente')),
            ],
          ),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    color: olympusBlue,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Esta ação removerá definitivamente a conta de acesso, o e-mail, o perfil, as permissões, os arquivos e os dados vinculados. Não poderá ser desfeita.',
                ),
                const SizedBox(height: 16),
                Text('Digite o e-mail abaixo para confirmar:\n$email'),
                const SizedBox(height: 8),
                TextField(
                  controller: controller,
                  enabled: !deleting,
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: 'E-mail de confirmação',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) => setDialogState(() {}),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed:
                  deleting ? null : () => Navigator.pop(dialogContext, false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton.icon(
              onPressed: deleting ||
                      controller.text.trim().toLowerCase() !=
                          email.toLowerCase()
                  ? null
                  : () {
                      setDialogState(() => deleting = true);
                      Navigator.pop(dialogContext, true);
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              icon: const Icon(Icons.delete_forever_rounded),
              label: const Text('Excluir definitivamente'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (confirmed != true || !mounted) return;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Expanded(child: Text('Excluindo conta e dados...')),
          ],
        ),
      ),
    );
    await deleteProfile(profile);
    if (mounted) Navigator.of(context, rootNavigator: true).pop();
  }

  String _normalizeCoachTeamGender(dynamic value) {
    final normalized = (value ?? '').toString().trim().toLowerCase();
    if (normalized == 'feminino') return 'Feminino';
    if (normalized == 'masculino') return 'Masculino';
    return 'all';
  }

  String _shortCoachTeamGenderLabel(String value) {
    switch (_normalizeCoachTeamGender(value)) {
      case 'Feminino':
        return 'Feminino';
      case 'Masculino':
        return 'Masculino';
      default:
        return 'Ambos';
    }
  }

  Widget _buildCoachTeamPermissionsCard({
    required String selectedValue,
    required ValueChanged<String> onSelected,
  }) {
    final options = const [
      {'value': 'Feminino', 'label': 'Feminino', 'icon': Icons.female_rounded},
      {'value': 'Masculino', 'label': 'Masculino', 'icon': Icons.male_rounded},
      {'value': 'all', 'label': 'Ambos', 'icon': Icons.groups_2_rounded},
    ];

    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            olympusBlue.withOpacity(0.95),
            olympusLightBlue.withOpacity(0.88),
          ],
        ),
        border: Border.all(color: olympusGold.withOpacity(0.45)),
        boxShadow: [
          BoxShadow(
            color: olympusBlue.withOpacity(0.22),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  color: Colors.white.withOpacity(0.12),
                  border: Border.all(color: Colors.white.withOpacity(0.18)),
                ),
                child: const Icon(
                  Icons.manage_accounts_rounded,
                  color: Colors.white,
                  size: 23,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Time do treinador',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Define quais atletas, avaliações e relatórios este técnico acompanha.',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.82),
                        fontSize: 12.2,
                        fontWeight: FontWeight.w600,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: options.map((item) {
              final value = item['value']! as String;
              final label = item['label']! as String;
              final icon = item['icon']! as IconData;
              final selected =
                  _normalizeCoachTeamGender(selectedValue) == value;

              return ChoiceChip(
                selected: selected,
                showCheckmark: false,
                avatar: Icon(
                  icon,
                  size: 17,
                  color: selected ? olympusBlue : olympusBlue.withOpacity(0.88),
                ),
                label: Text(label),
                selectedColor: olympusGold,
                backgroundColor: const Color(0xFFF4F7FB),
                side: BorderSide(
                  color:
                      selected ? olympusGold : Colors.white.withOpacity(0.70),
                ),
                labelStyle: TextStyle(
                  color: selected ? olympusBlue : olympusBlue.withOpacity(0.88),
                  fontWeight: FontWeight.w900,
                ),
                onSelected: (_) => onSelected(value),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Future<void> _copyAdminPasswordMessage({
    required String userName,
    required String email,
    required String password,
  }) async {
    final clubName = _branding.teamName;
    final message = email.trim().isEmpty
        ? 'Olá, $userName!\n\nSua senha temporária de acesso ao $clubName é:\n$password\n\nNo primeiro acesso, o aplicativo solicitará obrigatoriamente uma nova senha.'
        : 'Olá, $userName!\n\nE-mail: $email\nSenha temporária de acesso ao $clubName: $password\n\nNo primeiro acesso, o aplicativo solicitará obrigatoriamente uma nova senha.';

    await Clipboard.setData(ClipboardData(text: message));

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Mensagem com a nova senha copiada!'),
        backgroundColor: olympusBlue,
      ),
    );
  }

  Future<void> _copyAdminPasswordOnly(String password) async {
    await Clipboard.setData(ClipboardData(text: password));

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Senha copiada!'),
        backgroundColor: olympusBlue,
      ),
    );
  }

  Future<String> _resetUserPasswordByFunction({required String userId}) async {
    final session = supabase.auth.currentSession;

    if (session == null) {
      throw Exception('Sessão expirada. Faça login novamente.');
    }

    final response = await supabase.functions.invoke(
      'reset-user-password',
      headers: {'Authorization': 'Bearer ${session.accessToken}'},
      body: {'user_id': userId},
    );

    if (response.status < 200 || response.status >= 300) {
      final data = response.data;
      final errorMessage = data is Map && data['error'] != null
          ? data['error'].toString()
          : 'Falha ao atualizar senha no Supabase.';
      throw Exception(errorMessage);
    }

    final data = response.data;
    final password = data is Map ? data['password']?.toString().trim() : null;

    if (password == null || password.isEmpty) {
      throw Exception(
        'A função reset-user-password não retornou a senha gerada.',
      );
    }

    return password;
  }

  Future<void> _showResetPasswordDialog(Map<String, dynamic> profile) async {
    final userId = (profile['id'] ?? '').toString().trim();
    final userName = (profile['full_name'] ?? 'Usuário').toString().trim();
    final email =
        (profile['email'] ?? profile['email_address'] ?? '').toString().trim();

    if (userId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Usuário inválido: ID não encontrado.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    String generatedPassword = '';
    bool isLoading = true;
    bool isSaved = false;
    String? errorMessage;

    Future<void> executeReset(StateSetter setDialogState) async {
      setDialogState(() {
        isLoading = true;
        isSaved = false;
        errorMessage = null;
        generatedPassword = '';
      });

      try {
        final functionPassword = await _resetUserPasswordByFunction(
          userId: userId,
        );

        if (!mounted) return;

        setDialogState(() {
          generatedPassword = functionPassword;
          isLoading = false;
          isSaved = true;
        });

        await _copyAdminPasswordMessage(
          userName: userName,
          email: email,
          password: functionPassword,
        );

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Senha de $userName atualizada no Supabase.'),
            backgroundColor: Colors.green,
          ),
        );
      } catch (e) {
        debugPrint('❌ Erro ao redefinir senha pelo admin: $e');

        if (!mounted) return;

        setDialogState(() {
          isLoading = false;
          isSaved = false;
          errorMessage = e.toString().replaceFirst('Exception: ', '');
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao redefinir senha: $errorMessage'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        bool started = false;

        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            if (!started) {
              started = true;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                executeReset(setDialogState);
              });
            }

            return AlertDialog(
              title: Row(
                children: [
                  Icon(
                    isSaved
                        ? Icons.check_circle_outline
                        : Icons.lock_reset_rounded,
                    color: isSaved ? Colors.green : olympusGold,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      isLoading
                          ? 'Resetando senha'
                          : isSaved
                              ? 'Senha atualizada'
                              : 'Erro ao atualizar senha',
                    ),
                  ),
                ],
              ),
              content: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      userName,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: olympusBlue,
                      ),
                    ),
                    if (email.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        email,
                        style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                      ),
                    ],
                    const SizedBox(height: 16),
                    if (isLoading) ...[
                      Row(
                        children: [
                          SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.4,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                olympusGold,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Text(
                              'A função reset-user-password está gerando e salvando a senha no Supabase...',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                    ] else if (errorMessage != null) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.red.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.redAccent),
                        ),
                        child: Text(
                          errorMessage!,
                          style: const TextStyle(
                            color: Colors.red,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'A senha só será exibida quando a Edge Function confirmar que ela foi gravada no Supabase.',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ] else ...[
                      const Text(
                        'Nova senha salva no Supabase:',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF4F6FA),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: olympusGold.withOpacity(0.65),
                          ),
                        ),
                        child: SelectableText(
                          generatedPassword,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.1,
                            color: olympusBlue,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: generatedPassword.isEmpty
                                  ? null
                                  : () => _copyAdminPasswordOnly(
                                        generatedPassword,
                                      ),
                              icon: const Icon(Icons.copy),
                              label: const Text('Copiar senha'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: generatedPassword.isEmpty
                                  ? null
                                  : () => _copyAdminPasswordMessage(
                                        userName: userName,
                                        email: email,
                                        password: generatedPassword,
                                      ),
                              icon: const Icon(Icons.message_outlined),
                              label: const Text('Copiar mensagem'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Esta é a senha ativa retornada pela Edge Function e gravada no Supabase.',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.green[700],
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed:
                      isLoading ? null : () => Navigator.pop(dialogContext),
                  child: const Text('Fechar'),
                ),
                if (!isLoading && errorMessage != null)
                  ElevatedButton.icon(
                    onPressed: () {
                      executeReset(setDialogState);
                    },
                    icon: const Icon(Icons.refresh),
                    label: const Text('Tentar novamente'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: olympusGold,
                      foregroundColor: olympusBlue,
                    ),
                  ),
                if (!isLoading && isSaved)
                  ElevatedButton.icon(
                    onPressed: () async {
                      await executeReset(setDialogState);
                    },
                    icon: const Icon(Icons.refresh),
                    label: const Text('Resetar novamente'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: olympusGold,
                      foregroundColor: olympusBlue,
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _showPermissionsDialog(Map<String, dynamic> profile) async {
    final userId = profile['id'];
    final userName = profile['full_name'] ?? 'Usuário';

    final currentPermissions = await _permissionService.getUserPermissions(
      userId,
    );
    final visibilityPermissions =
        await _permissionService.getRankingEvaluationVisibility(userId);
    final agendaFilters = await _permissionService.getAgendaFilters(userId);
    var activeRoles = await _roleService.getUserRoles(userId);

    Map<String, dynamic> financialFilters = {};
    try {
      financialFilters = Map<String, dynamic>.from(
        await (_permissionService as dynamic).getFinancialFilters(userId),
      );
    } catch (_) {
      financialFilters = {};
    }

    final permissionItems = [
      {
        'pageName': 'agenda',
        'title': 'Acesso à Agenda',
        'subtitle': 'Permitir visualizar e usar a agenda',
      },
      {
        'pageName': 'checkin',
        'title': 'Acesso ao Check-in',
        'subtitle': 'Permitir realizar check-in nos eventos',
      },
      {
        'pageName': 'financeiro',
        'title': 'Acesso ao Financeiro',
        'subtitle': 'Permitir visualizar recursos financeiros',
      },
      {
        'pageName': 'chat',
        'title': 'Acesso ao Chat',
        'subtitle': 'Permitir conversar em chats e grupos',
      },
      {
        'pageName': 'treinos',
        'title': 'Acesso aos Treinos',
        'subtitle': 'Permitir visualizar e usar os treinos',
      },
      {
        'pageName': 'campeonatos',
        'title': 'Acesso aos Campeonatos',
        'subtitle': 'Permitir visualizar os campeonatos',
      },
      {
        'pageName': 'perfil',
        'title': 'Acesso ao Perfil',
        'subtitle': 'Permitir visualizar e editar o perfil',
      },
      {
        'pageName': 'birthdays',
        'title': 'Acesso aos Aniversariantes',
        'subtitle': 'Permitir visualizar a página de aniversários',
      },
    ];

    final adminPermissionItems = [
      {
        'pageName': 'admin_evaluations',
        'title': 'Avaliações dos treinadores',
        'subtitle': 'Visualizar as avaliações recebidas pelos treinadores',
      },
      {
        'pageName': 'admin_agenda',
        'title': 'Agenda administrativa',
        'subtitle': 'Visualizar todos os eventos cadastrados',
      },
      {
        'pageName': 'admin_training_plans',
        'title': 'Planejamentos de treino',
        'subtitle': 'Visualizar os planejamentos dos treinadores',
      },
      {
        'pageName': 'admin_statistics',
        'title': 'Estatísticas dos atletas',
        'subtitle': 'Visualizar estatísticas e indicadores dos atletas',
      },
      {
        'pageName': 'admin_birthdays',
        'title': 'Aniversariantes',
        'subtitle': 'Visualizar aniversariantes no modo administrador',
      },
      {
        'pageName': 'admin_competitions',
        'title': 'Jogos e competições',
        'subtitle': 'Visualizar os jogos cadastrados pela administração',
      },
      {
        'pageName': 'admin_financial',
        'title': 'Financeiro administrativo',
        'subtitle': 'Visualizar cobranças, pagamentos e comprovantes',
      },
      {
        'pageName': 'admin_users',
        'title': 'Gerenciar usuários',
        'subtitle': 'Visualizar perfis e alterar permissões',
      },
      {
        'pageName': 'admin_messages',
        'title': 'Mensagens administrativas',
        'subtitle': 'Acessar as mensagens da administração',
      },
    ];

    final permissionValues = <String, bool>{
      for (final item in [...permissionItems, ...adminPermissionItems])
        item['pageName'] as String:
            currentPermissions[item['pageName']] ?? true,
    };

    bool showInRanking = visibilityPermissions['show_in_ranking'] ?? false;
    bool showInEvaluations =
        visibilityPermissions['show_in_evaluations'] ?? false;

    bool notifyEventResponses = false;
    bool savingEventResponsePreference = false;
    if (activeRoles.contains('admin')) {
      try {
        final preference = await supabase
            .from('admin_notification_preferences')
            .select('notify_event_responses')
            .eq('admin_id', userId)
            .maybeSingle();
        notifyEventResponses = preference?['notify_event_responses'] == true;
      } catch (error) {
        debugPrint('Erro ao carregar avisos do administrador: $error');
      }
    }

    String selectedCoachTeamGender = _normalizeCoachTeamGender(
      profile['coach_team_gender'],
    );

    // ── Estado local reativo para o papel primário ───────────────────────────
    String currentUserType =
        (profile['user_type'] ?? 'member').toString().trim();
    // ────────────────────────────────────────────────────────────────────────

    bool showMonthFilter = agendaFilters['show_month_filter'] ?? true;
    bool showStatusFilter = agendaFilters['show_status_filter'] ?? true;
    final allowedEventTypes = List<String>.from(
      agendaFilters['allowed_event_types'] ??
          ['treino', 'amistoso', 'campeonato'],
    );
    final allowedConvocationStatuses = List<String>.from(
      agendaFilters['allowed_convocation_statuses'] ??
          ['accepted', 'rejected', 'pending'],
    );
    bool verConvocados = agendaFilters['ver_convocados'] == true;
    bool exportarDadosJogo = agendaFilters['exportar_dados_jogo'] == true;
    String selectedPermissionSection = 'access';
    bool rolesExpanded = false;
    final allowedFinancialTypes = List<String>.from(
      financialFilters['allowed_financial_types'] ??
          ['monthly', 'games', 'maintenance', 'other'],
    );

    Future<void> saveAgendaFilters() async {
      await _permissionService.updateAgendaFilters(
        userId: userId,
        showMonthFilter: showMonthFilter,
        showStatusFilter: showStatusFilter,
        allowedEventTypes: allowedEventTypes,
        allowedConvocationStatuses: allowedConvocationStatuses,
      );
    }

    Future<void> saveFinancialFilters() async {
      await (_permissionService as dynamic).updateFinancialFilters(
        userId: userId,
        allowedFinancialTypes: allowedFinancialTypes,
      );
    }

    Future<void> saveAgendaActionPermissions() async {
      await _permissionService.updateAgendaActionPermissions(
        userId: userId,
        verConvocados: verConvocados,
        exportarDadosJogo: exportarDadosJogo,
      );
    }

    Future<void> saveRankingEvaluationVisibility() async {
      await _permissionService.updateRankingEvaluationVisibility(
        userId: userId,
        showInRanking: showInRanking,
        showInEvaluations: showInEvaluations,
      );
    }

    Future<void> saveCoachTeamGender() async {
      await _permissionService.updateCoachTeamGender(
        userId: userId,
        coachTeamGender: selectedCoachTeamGender,
      );
      profile['coach_team_gender'] = selectedCoachTeamGender;
      await fetchProfiles();
    }

    Future<void> saveEventResponsePreference(bool enabled) async {
      final organizationId = OrganizationContextService.instance.currentId;
      if (organizationId.isEmpty) {
        throw Exception(
            'Clube não identificado. Atualize a tela e tente novamente.');
      }
      await supabase.from('admin_notification_preferences').upsert({
        'admin_id': userId,
        'organization_id': organizationId,
        'notify_event_responses': enabled,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'admin_id');
    }

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFFF7FAFC),
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          titlePadding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
          contentPadding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
          actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
          title: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  gradient: LinearGradient(
                    colors: [olympusBlue, olympusLightBlue],
                  ),
                ),
                child: const Icon(Icons.lock_outline, color: Colors.white),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Gerenciar Permissões',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFE4EDF5)),
                    ),
                    child: ExpansionTile(
                      initiallyExpanded: rolesExpanded,
                      onExpansionChanged: (value) {
                        setDialogState(() => rolesExpanded = value);
                      },
                      leading: CircleAvatar(
                        backgroundColor: Color(0xFFE8F0F8),
                        child: Icon(Icons.badge_outlined, color: olympusBlue),
                      ),
                      title: Text(
                        userName,
                        style: TextStyle(
                          color: olympusBlue,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      subtitle: Text(
                        'Papéis • ${_getTypeLabel(currentUserType)}',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      childrenPadding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                      children: [
                        RoleManagerWidget(
                          userId: userId,
                          userName: userName,
                          currentPrimaryRole: currentUserType,
                          onRolesSaved: (newPrimaryRole) async {
                            final refreshedRoles =
                                await _roleService.getUserRoles(userId);
                            if (!context.mounted) return;
                            setDialogState(() {
                              activeRoles = refreshedRoles;
                              currentUserType = newPrimaryRole;
                              profile['user_type'] = newPrimaryRole;
                              selectedPermissionSection = 'access';
                            });
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Papéis atualizados! Perfil principal: ${_getTypeLabel(newPrimaryRole)}.',
                                ),
                                backgroundColor: Colors.green,
                              ),
                            );
                            fetchProfiles();
                          },
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 12),

                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ('access', 'Acessos', Icons.grid_view_rounded),
                      if (activeRoles.contains('admin'))
                        (
                          'admin',
                          'Admin',
                          Icons.admin_panel_settings_outlined,
                        ),
                      if (activeRoles.contains('coach'))
                        ('coach', 'Técnico', Icons.sports_rounded),
                      if (activeRoles.contains('athlete'))
                        ('visibility', 'Atleta', Icons.visibility_outlined),
                      if (permissionValues['agenda'] == true)
                        ('agenda', 'Agenda', Icons.calendar_month_outlined),
                      if (permissionValues['financeiro'] == true)
                        ('finance', 'Financeiro', Icons.payments_outlined),
                    ].map((item) {
                      final selected = selectedPermissionSection == item.$1;
                      return ChoiceChip(
                        avatar: Icon(
                          item.$3,
                          size: 16,
                          color: selected ? Colors.white : olympusBlue,
                        ),
                        label: Text(item.$2),
                        labelPadding: const EdgeInsets.symmetric(
                          horizontal: 2,
                        ),
                        selected: selected,
                        showCheckmark: false,
                        selectedColor: olympusBlue,
                        backgroundColor: Colors.white,
                        side: BorderSide(
                          color:
                              selected ? olympusBlue : const Color(0xFFE4EDF5),
                        ),
                        labelStyle: TextStyle(
                          color: selected ? Colors.white : olympusBlue,
                          fontWeight: FontWeight.w800,
                        ),
                        onSelected: (_) {
                          setDialogState(() {
                            selectedPermissionSection = item.$1;
                          });
                        },
                      );
                    }).toList(),
                  ),

                  const SizedBox(height: 12),

                  // ✅ USA currentUserType — reativo ao RoleManagerWidget
                  if (activeRoles.contains('coach') &&
                      selectedPermissionSection == 'coach')
                    _buildCoachTeamPermissionsCard(
                      selectedValue: selectedCoachTeamGender,
                      onSelected: (value) async {
                        setDialogState(() {
                          selectedCoachTeamGender = value;
                        });
                        try {
                          await saveCoachTeamGender();
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Time do treinador atualizado para ${_shortCoachTeamGenderLabel(value)}.',
                                ),
                                backgroundColor: Colors.green,
                              ),
                            );
                          }
                        } catch (e) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Erro ao atualizar time do treinador: $e',
                                ),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
                        }
                      },
                    ),

                  if (selectedPermissionSection == 'access') ...[
                    const Text(
                      'Permissões de Acesso:',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 12),
                    ...permissionItems.map((item) {
                      final pageName = item['pageName'] as String;
                      final title = item['title'] as String;
                      final subtitle = item['subtitle'] as String;
                      return SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(title),
                        subtitle: Text(subtitle),
                        value: permissionValues[pageName] ?? true,
                        activeColor: olympusGold,
                        onChanged: (value) async {
                          try {
                            await _permissionService.updatePermission(
                              userId: userId,
                              pageName: pageName,
                              canAccess: value,
                            );
                            setDialogState(() {
                              permissionValues[pageName] = value;
                            });
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    'Permissão de ${title.toLowerCase()} ${value ? 'concedida' : 'revogada'} com sucesso!',
                                  ),
                                  backgroundColor:
                                      value ? Colors.green : Colors.orange,
                                ),
                              );
                            }
                          } catch (e) {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    'Erro ao atualizar permissão: $e',
                                  ),
                                  backgroundColor: Colors.red,
                                ),
                              );
                            }
                          }
                        },
                      );
                    }).toList(),
                  ],

                  if (selectedPermissionSection == 'admin' &&
                      activeRoles.contains('admin')) ...[
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFE4EDF5)),
                      ),
                      child: SwitchListTile.adaptive(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 3,
                        ),
                        secondary: Icon(
                          Icons.notifications_active_outlined,
                          color: olympusBlue,
                        ),
                        title: Text(
                          'Avisar aceite ou recusa',
                          style: TextStyle(
                            color: olympusBlue,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        subtitle: Text(
                          'Este administrador receberá um aviso quando um atleta responder a um evento.',
                          style: TextStyle(
                            color: Colors.grey[700],
                            fontSize: 12,
                          ),
                        ),
                        value: notifyEventResponses,
                        activeColor: olympusGold,
                        onChanged: savingEventResponsePreference
                            ? null
                            : (enabled) async {
                                setDialogState(() {
                                  savingEventResponsePreference = true;
                                  notifyEventResponses = enabled;
                                });
                                try {
                                  await saveEventResponsePreference(enabled);
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          enabled
                                              ? 'Avisos de aceite e recusa habilitados para $userName.'
                                              : 'Avisos de aceite e recusa desabilitados para $userName.',
                                        ),
                                        backgroundColor: enabled
                                            ? Colors.green
                                            : Colors.blueGrey,
                                      ),
                                    );
                                  }
                                } catch (error) {
                                  setDialogState(() {
                                    notifyEventResponses = !enabled;
                                  });
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          'Não foi possível salvar os avisos: $error',
                                        ),
                                        backgroundColor: Colors.red,
                                      ),
                                    );
                                  }
                                } finally {
                                  if (context.mounted) {
                                    setDialogState(() {
                                      savingEventResponsePreference = false;
                                    });
                                  }
                                }
                              },
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'Acessos no modo Administrador:',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Escolha exatamente quais áreas este administrador pode visualizar.',
                      style: TextStyle(fontSize: 12, color: Colors.black54),
                    ),
                    const SizedBox(height: 8),
                    ...adminPermissionItems.map((item) {
                      final pageName = item['pageName'] as String;
                      final title = item['title'] as String;
                      final subtitle = item['subtitle'] as String;
                      return SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        title: Text(title),
                        subtitle: Text(subtitle),
                        value: permissionValues[pageName] ?? true,
                        activeColor: olympusGold,
                        onChanged: (value) async {
                          await _permissionService.updatePermission(
                            userId: userId,
                            pageName: pageName,
                            canAccess: value,
                          );
                          setDialogState(() {
                            permissionValues[pageName] = value;
                          });
                        },
                      );
                    }),
                  ],

                  // ✅ USA currentUserType — reativo ao RoleManagerWidget
                  if (activeRoles.contains('athlete') &&
                      selectedPermissionSection == 'visibility') ...[
                    const SizedBox(height: 16),
                    Divider(color: Colors.grey[300]),
                    const SizedBox(height: 8),
                    const Text(
                      'Visibilidade do Atleta:',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 8),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Mostrar no ranking'),
                      subtitle: const Text(
                        'Permitir que este atleta apareça no ranking dos atletas',
                      ),
                      value: showInRanking,
                      activeColor: olympusGold,
                      onChanged: (value) async {
                        try {
                          setDialogState(() {
                            showInRanking = value;
                          });
                          await saveRankingEvaluationVisibility();
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Visibilidade no ranking ${value ? 'habilitada' : 'desabilitada'} com sucesso!',
                                ),
                                backgroundColor:
                                    value ? Colors.green : Colors.orange,
                              ),
                            );
                          }
                        } catch (e) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Erro ao atualizar visibilidade no ranking: $e',
                                ),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
                        }
                      },
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Mostrar nas avaliações'),
                      subtitle: const Text(
                        'Permitir que este atleta apareça na seleção de avaliações',
                      ),
                      value: showInEvaluations,
                      activeColor: olympusGold,
                      onChanged: (value) async {
                        try {
                          setDialogState(() {
                            showInEvaluations = value;
                          });
                          await saveRankingEvaluationVisibility();
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Visibilidade nas avaliações ${value ? 'habilitada' : 'desabilitada'} com sucesso!',
                                ),
                                backgroundColor:
                                    value ? Colors.green : Colors.orange,
                              ),
                            );
                          }
                        } catch (e) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Erro ao atualizar visibilidade nas avaliações: $e',
                                ),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
                        }
                      },
                    ),
                  ],

                  if (permissionValues['agenda'] == true &&
                      selectedPermissionSection == 'agenda') ...[
                    const SizedBox(height: 16),
                    Divider(color: Colors.grey[300]),
                    const SizedBox(height: 8),
                    const Text(
                      'Filtros da Agenda:',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 8),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Mostrar filtro de mês'),
                      subtitle: const Text(
                        'Permitir que o atleta veja o filtro Mês',
                      ),
                      value: showMonthFilter,
                      activeColor: olympusGold,
                      onChanged: (value) async {
                        try {
                          setDialogState(() {
                            showMonthFilter = value;
                          });
                          await saveAgendaFilters();
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Filtro de mês ${value ? 'habilitado' : 'desabilitado'} com sucesso!',
                                ),
                                backgroundColor:
                                    value ? Colors.green : Colors.orange,
                              ),
                            );
                          }
                        } catch (e) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Erro ao atualizar filtro de mês: $e',
                                ),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
                        }
                      },
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Tipos de evento permitidos',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        {'value': 'treino', 'label': 'Treino'},
                        {'value': 'amistoso', 'label': 'Amistoso'},
                        {'value': 'campeonato', 'label': 'Campeonatos'},
                      ].map((item) {
                        final value = item['value']!;
                        final selected = allowedEventTypes.contains(value);
                        return FilterChip(
                          label: Text(item['label']!),
                          selected: selected,
                          selectedColor: olympusGold.withOpacity(0.2),
                          checkmarkColor: olympusBlue,
                          onSelected: (enabled) async {
                            final updated = List<String>.from(
                              allowedEventTypes,
                            );
                            if (enabled) {
                              if (!updated.contains(value)) updated.add(value);
                            } else {
                              updated.remove(value);
                            }
                            if (updated.isEmpty) {
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Selecione pelo menos um tipo de evento.',
                                    ),
                                    backgroundColor: Colors.orange,
                                  ),
                                );
                              }
                              return;
                            }
                            try {
                              setDialogState(() {
                                allowedEventTypes
                                  ..clear()
                                  ..addAll(updated);
                              });
                              await saveAgendaFilters();
                            } catch (e) {
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'Erro ao atualizar tipos de evento: $e',
                                    ),
                                    backgroundColor: Colors.red,
                                  ),
                                );
                              }
                            }
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Mostrar filtro de status'),
                      subtitle: const Text(
                        'Permitir que o atleta veja o filtro Status da Convocação',
                      ),
                      value: showStatusFilter,
                      activeColor: olympusGold,
                      onChanged: (value) async {
                        try {
                          setDialogState(() {
                            showStatusFilter = value;
                          });
                          await saveAgendaFilters();
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Filtro de status ${value ? 'habilitado' : 'desabilitado'} com sucesso!',
                                ),
                                backgroundColor:
                                    value ? Colors.green : Colors.orange,
                              ),
                            );
                          }
                        } catch (e) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Erro ao atualizar filtro de status: $e',
                                ),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
                        }
                      },
                    ),
                    if (showStatusFilter) ...[
                      const SizedBox(height: 8),
                      const Text(
                        'Status permitidos',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          {'value': 'accepted', 'label': 'Aceitou'},
                          {'value': 'rejected', 'label': 'Recusou'},
                          {'value': 'pending', 'label': 'Pendentes'},
                        ].map((item) {
                          final value = item['value']!;
                          final selected =
                              allowedConvocationStatuses.contains(value);
                          return FilterChip(
                            label: Text(item['label']!),
                            selected: selected,
                            selectedColor: olympusGold.withOpacity(0.2),
                            checkmarkColor: olympusBlue,
                            onSelected: (enabled) async {
                              final updated = List<String>.from(
                                allowedConvocationStatuses,
                              );
                              if (enabled) {
                                if (!updated.contains(value)) {
                                  updated.add(value);
                                }
                              } else {
                                updated.remove(value);
                              }
                              if (updated.isEmpty) {
                                if (mounted) {
                                  ScaffoldMessenger.of(
                                    context,
                                  ).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Selecione pelo menos um status de convocação.',
                                      ),
                                      backgroundColor: Colors.orange,
                                    ),
                                  );
                                }
                                return;
                              }
                              try {
                                setDialogState(() {
                                  allowedConvocationStatuses
                                    ..clear()
                                    ..addAll(updated);
                                });
                                await saveAgendaFilters();
                              } catch (e) {
                                if (mounted) {
                                  ScaffoldMessenger.of(
                                    context,
                                  ).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        'Erro ao atualizar status permitidos: $e',
                                      ),
                                      backgroundColor: Colors.red,
                                    ),
                                  );
                                }
                              }
                            },
                          );
                        }).toList(),
                      ),
                    ],
                  ],

                  if (permissionValues['agenda'] == true &&
                      selectedPermissionSection == 'agenda') ...[
                    const SizedBox(height: 16),
                    Divider(color: Colors.grey[300]),
                    const SizedBox(height: 8),
                    const Text(
                      'Opções dos 3 pontinhos na Agenda:',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 8),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Ver convocados'),
                      subtitle: const Text(
                        'Mostrar a opção Ver convocados no perfil do usuário',
                      ),
                      value: verConvocados,
                      activeColor: olympusGold,
                      onChanged: (value) async {
                        try {
                          setDialogState(() {
                            verConvocados = value;
                          });
                          await saveAgendaActionPermissions();
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Opção Ver convocados ${value ? 'habilitada' : 'desabilitada'} com sucesso!',
                                ),
                                backgroundColor:
                                    value ? Colors.green : Colors.orange,
                              ),
                            );
                          }
                        } catch (e) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Erro ao atualizar opção Ver convocados: $e',
                                ),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
                        }
                      },
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Exportar dados do jogo'),
                      subtitle: const Text(
                        'Mostrar a opção Exportar dados do jogo no perfil do usuário',
                      ),
                      value: exportarDadosJogo,
                      activeColor: olympusGold,
                      onChanged: (value) async {
                        try {
                          setDialogState(() {
                            exportarDadosJogo = value;
                          });
                          await saveAgendaActionPermissions();
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Opção Exportar dados do jogo ${value ? 'habilitada' : 'desabilitada'} com sucesso!',
                                ),
                                backgroundColor:
                                    value ? Colors.green : Colors.orange,
                              ),
                            );
                          }
                        } catch (e) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Erro ao atualizar opção Exportar dados do jogo: $e',
                                ),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
                        }
                      },
                    ),
                  ],

                  if (permissionValues['financeiro'] == true &&
                      selectedPermissionSection == 'finance') ...[
                    const SizedBox(height: 16),
                    Divider(color: Colors.grey[300]),
                    const SizedBox(height: 8),
                    const Text(
                      'Filtros do Financeiro:',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Tipos financeiros permitidos',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        {'value': 'monthly', 'label': 'Mensalidade'},
                        {'value': 'games', 'label': 'Jogos'},
                        {'value': 'maintenance', 'label': 'Manutenção'},
                        {'value': 'other', 'label': 'Outros'},
                      ].map((item) {
                        final value = item['value']!;
                        final selected = allowedFinancialTypes.contains(
                          value,
                        );
                        return FilterChip(
                          label: Text(item['label']!),
                          selected: selected,
                          selectedColor: olympusGold.withOpacity(0.2),
                          checkmarkColor: olympusBlue,
                          onSelected: (enabled) async {
                            final updated = List<String>.from(
                              allowedFinancialTypes,
                            );
                            if (enabled) {
                              if (!updated.contains(value)) updated.add(value);
                            } else {
                              updated.remove(value);
                            }
                            if (updated.isEmpty) {
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Selecione pelo menos um tipo financeiro.',
                                    ),
                                    backgroundColor: Colors.orange,
                                  ),
                                );
                              }
                              return;
                            }
                            try {
                              setDialogState(() {
                                allowedFinancialTypes
                                  ..clear()
                                  ..addAll(updated);
                              });
                              await saveFinancialFilters();
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Tipos do financeiro atualizados com sucesso!',
                                    ),
                                    backgroundColor: Colors.green,
                                  ),
                                );
                              }
                            } catch (e) {
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'Erro ao atualizar tipos financeiros: $e',
                                    ),
                                    backgroundColor: Colors.red,
                                  ),
                                );
                              }
                            }
                          },
                        );
                      }).toList(),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Fechar'),
            ),
          ],
        ),
      ),
    );
  }

  Future<String?> _getCurrentUserType() async {
    try {
      final user = supabase.auth.currentUser;
      if (user == null) return null;
      final response = await supabase
          .from('profiles')
          .select('user_type')
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
    return List.generate(
      12,
      (index) => chars[random.nextInt(chars.length)],
    ).join();
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
              style: TextStyle(
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
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'monospace',
                        color: olympusBlue,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.copy, color: olympusGold),
                    tooltip: 'Copiar e-mail e senha',
                    onPressed: () {
                      Clipboard.setData(
                        ClipboardData(text: 'E-mail: $email\nSenha: $password'),
                      );
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('E-mail e senha copiados!'),
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
              'Envie esta senha temporária para o usuário. No primeiro acesso, '
              'ele será obrigado a criar uma senha pessoal.',
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
    bool isSubmitting = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
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
                  enabled: !isSubmitting,
                  decoration: InputDecoration(
                    labelText: 'Nome Completo',
                    prefixIcon: Icon(Icons.person, color: olympusGold),
                    border: const OutlineInputBorder(),
                    focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(
                        color: olympusGold,
                        width: 2,
                      ),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: emailCtrl,
                  enabled: !isSubmitting,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                    labelText: 'E-mail',
                    prefixIcon: Icon(Icons.email, color: olympusGold),
                    border: const OutlineInputBorder(),
                    focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(
                        color: olympusGold,
                        width: 2,
                      ),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: phoneCtrl,
                  enabled: !isSubmitting,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                    labelText: 'Telefone',
                    prefixIcon: Icon(Icons.phone, color: olympusGold),
                    border: const OutlineInputBorder(),
                    focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(
                        color: olympusGold,
                        width: 2,
                      ),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: selectedType,
                  decoration: InputDecoration(
                    labelText: 'Tipo de Usuário',
                    prefixIcon: Icon(Icons.badge, color: olympusGold),
                    border: const OutlineInputBorder(),
                    focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(
                        color: olympusGold,
                        width: 2,
                      ),
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
                  onChanged: isSubmitting
                      ? null
                      : (val) {
                          if (val != null) {
                            setDialogState(() => selectedType = val);
                          }
                        },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed:
                  isSubmitting ? null : () => Navigator.pop(dialogContext),
              child: const Text('Cancelar'),
            ),
            ElevatedButton.icon(
              onPressed: isSubmitting
                  ? null
                  : () async {
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

                      setDialogState(() => isSubmitting = true);

                      try {
                        final organization = await OrganizationContextService
                            .instance
                            .initialize(force: true);
                        if (organization == null || !organization.canManage) {
                          throw Exception(
                            'Não foi possível confirmar o clube administrado.',
                          );
                        }

                        final response = await supabase.functions.invoke(
                          'create-organization-user',
                          body: {
                            'organization_id': organization.id,
                            'email': email,
                            'password': password,
                            'full_name': nameCtrl.text.trim(),
                            'phone': phoneCtrl.text.replaceAll(
                              RegExp(r'\D'),
                              '',
                            ),
                            'user_type': selectedType,
                          },
                        );
                        final payload = response.data;
                        if (response.status < 200 ||
                            response.status >= 300 ||
                            payload is! Map ||
                            payload['success'] != true) {
                          final message = payload is Map
                              ? payload['error']?.toString()
                              : null;
                          throw Exception(
                            message ?? 'Usuário não foi criado.',
                          );
                        }

                        if (!mounted) return;

                        Navigator.pop(dialogContext);
                        _showPasswordResultDialog(password, email);
                        fetchProfiles();
                      } catch (e) {
                        debugPrint('❌ Erro ao cadastrar: $e');

                        if (!mounted) return;

                        String errorMessage =
                            e.toString().replaceFirst('Exception: ', '');
                        if (e.toString().contains('already registered') ||
                            e.toString().contains('já possui conta')) {
                          errorMessage = 'E-mail já cadastrado.';
                        }

                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(errorMessage),
                            backgroundColor: Colors.red,
                          ),
                        );
                      } finally {
                        if (mounted) {
                          setDialogState(() => isSubmitting = false);
                        }
                      }
                    },
              icon: isSubmitting
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(olympusBlue),
                      ),
                    )
                  : const Icon(Icons.save),
              label: Text(isSubmitting ? 'Cadastrando...' : 'Cadastrar'),
              style: ElevatedButton.styleFrom(
                backgroundColor: olympusGold,
                foregroundColor: olympusBlue,
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Map<String, dynamic>> _getFilteredProfiles() {
    final filtered = profiles.where((profile) {
      final gender = (profile['gender'] ?? '').toString().trim();
      final roles = _rolesForProfile(profile);
      final isActive = _isProfileActive(profile);
      final searchText = [
        profile['full_name'],
        profile['phone'],
        profile['cpf'],
        profile['email'],
      ].whereType<Object>().join(' ').toLowerCase();

      final matchesStatus = _showInactiveUsers ? !isActive : isActive;
      final matchesGender =
          _selectedGenderFilter == 'Todos' || gender == _selectedGenderFilter;
      final matchesUserType = _selectedUserTypeFilter == 'Todos' ||
          roles.contains(_selectedUserTypeFilter);
      final matchesSearch = _profilesSearchQuery.trim().isEmpty ||
          searchText.contains(_profilesSearchQuery.trim().toLowerCase());

      return matchesStatus && matchesGender && matchesUserType && matchesSearch;
    }).toList();

    filtered.sort((a, b) {
      final nameA = (a['full_name'] ?? '').toString().trim().toLowerCase();
      final nameB = (b['full_name'] ?? '').toString().trim().toLowerCase();
      return nameA.compareTo(nameB);
    });

    return filtered;
  }

  String _getSelectedFiltersLabel() {
    if (_selectedGenderFilter == 'Todos' &&
        _selectedUserTypeFilter == 'Todos') {
      return _showInactiveUsers ? 'Usuários inativos' : 'Usuários ativos';
    }
    if (_selectedGenderFilter != 'Todos' &&
        _selectedUserTypeFilter != 'Todos') {
      return '${_showInactiveUsers ? 'Inativos' : 'Ativos'} • ${_getTypeLabel(_selectedUserTypeFilter)} • $_selectedGenderFilter';
    }
    if (_selectedUserTypeFilter != 'Todos') {
      return '${_showInactiveUsers ? 'Inativos' : 'Ativos'} • ${_getTypeLabel(_selectedUserTypeFilter)}';
    }
    return '${_showInactiveUsers ? 'Inativos' : 'Ativos'} • $_selectedGenderFilter';
  }

  Widget _buildFilterDropdown({
    required IconData icon,
    required String label,
    required String value,
    required List<DropdownMenuItem<String>> items,
    required void Function(String?) onChanged,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.12),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withOpacity(0.18)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: olympusGold, size: 18),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Colors.white.withOpacity(0.92),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: value,
              iconEnabledColor: olympusGold,
              dropdownColor: olympusBlue.withOpacity(0.96),
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
              decoration: InputDecoration(
                isDense: true,
                filled: true,
                fillColor: Colors.white.withOpacity(0.10),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: Colors.white.withOpacity(0.12)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: Colors.white.withOpacity(0.12)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: olympusGold, width: 1.8),
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              items: items,
              onChanged: onChanged,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusToggleButton({
    required IconData icon,
    required String title,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: selected
                ? [olympusGold.withOpacity(0.34), olympusGold.withOpacity(0.18)]
                : [
                    Colors.white.withOpacity(0.10),
                    Colors.white.withOpacity(0.06),
                  ],
          ),
          border: Border.all(
            color: selected
                ? olympusGold.withOpacity(0.70)
                : Colors.white.withOpacity(0.16),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 18,
              color: selected ? olympusGold : Colors.white.withOpacity(0.80),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
                  fontSize: 12.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showCompactFiltersSheet() async {
    var gender = _selectedGenderFilter;
    var userType = _selectedUserTypeFilter;

    final apply = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => Container(
          padding: EdgeInsets.fromLTRB(
            20,
            12,
            20,
            20 + MediaQuery.paddingOf(context).bottom,
          ),
          decoration: const BoxDecoration(
            color: Color(0xFFF7FAFC),
            borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
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
                    color: Colors.black12,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Icon(Icons.tune_rounded, color: olympusBlue),
                  SizedBox(width: 10),
                  Text(
                    'Filtrar perfis',
                    style: TextStyle(
                      color: olympusBlue,
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              DropdownButtonFormField<String>(
                initialValue: gender,
                decoration: const InputDecoration(
                  labelText: 'Gênero',
                  prefixIcon: Icon(Icons.wc_rounded),
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 'Todos', child: Text('Todos')),
                  DropdownMenuItem(
                    value: 'Masculino',
                    child: Text('Masculino'),
                  ),
                  DropdownMenuItem(value: 'Feminino', child: Text('Feminino')),
                ],
                onChanged: (value) {
                  if (value != null) setSheetState(() => gender = value);
                },
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                initialValue: userType,
                decoration: const InputDecoration(
                  labelText: 'Tipo de usuário',
                  prefixIcon: Icon(Icons.badge_outlined),
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 'Todos', child: Text('Todos')),
                  DropdownMenuItem(value: 'member', child: Text('Membro')),
                  DropdownMenuItem(value: 'athlete', child: Text('Atleta')),
                  DropdownMenuItem(value: 'coach', child: Text('Técnico')),
                  DropdownMenuItem(
                    value: 'admin',
                    child: Text('Administrador'),
                  ),
                ],
                onChanged: (value) {
                  if (value != null) setSheetState(() => userType = value);
                },
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        setSheetState(() {
                          gender = 'Todos';
                          userType = 'Todos';
                        });
                      },
                      child: const Text('Limpar'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.pop(sheetContext, true),
                      style: FilledButton.styleFrom(
                        backgroundColor: olympusBlue,
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('Aplicar filtros'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (apply == true && mounted) {
      setState(() {
        _selectedGenderFilter = gender;
        _selectedUserTypeFilter = userType;
      });
    }
  }

  Widget _buildCompactFiltersBar(int resultsCount) {
    final appliedFilters = (_selectedGenderFilter != 'Todos' ? 1 : 0) +
        (_selectedUserTypeFilter != 'Todos' ? 1 : 0);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      child: Column(
        children: [
          TextField(
            controller: _profilesSearchController,
            onChanged: (value) => setState(() => _profilesSearchQuery = value),
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Buscar por nome, telefone ou CPF',
              hintStyle: TextStyle(color: Colors.white.withOpacity(0.60)),
              prefixIcon: Icon(Icons.search_rounded, color: olympusGold),
              suffixIcon: _profilesSearchQuery.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Limpar busca',
                      onPressed: () {
                        _profilesSearchController.clear();
                        setState(() => _profilesSearchQuery = '');
                      },
                      icon: const Icon(
                        Icons.close_rounded,
                        color: Colors.white70,
                      ),
                    ),
              filled: true,
              fillColor: Colors.white.withOpacity(0.11),
              contentPadding: const EdgeInsets.symmetric(vertical: 13),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: Colors.white.withOpacity(0.14)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: Colors.white.withOpacity(0.14)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: olympusGold, width: 1.5),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(
                      value: false,
                      icon: Icon(Icons.verified_user_outlined, size: 17),
                      label: Text('Ativos'),
                    ),
                    ButtonSegment(
                      value: true,
                      icon: Icon(Icons.person_off_outlined, size: 17),
                      label: Text('Inativos'),
                    ),
                  ],
                  selected: {_showInactiveUsers},
                  showSelectedIcon: false,
                  style: ButtonStyle(
                    visualDensity: VisualDensity.compact,
                    foregroundColor: WidgetStateProperty.resolveWith(
                      (states) => states.contains(WidgetState.selected)
                          ? olympusBlue
                          : Colors.white,
                    ),
                    backgroundColor: WidgetStateProperty.resolveWith(
                      (states) => states.contains(WidgetState.selected)
                          ? olympusGold
                          : Colors.white.withOpacity(0.08),
                    ),
                  ),
                  onSelectionChanged: (value) {
                    setState(() => _showInactiveUsers = value.first);
                  },
                ),
              ),
              const SizedBox(width: 8),
              Badge(
                isLabelVisible: appliedFilters > 0,
                label: Text('$appliedFilters'),
                backgroundColor: olympusGold,
                textColor: olympusBlue,
                child: IconButton.filledTonal(
                  tooltip: 'Filtros',
                  onPressed: _showCompactFiltersSheet,
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.white.withOpacity(0.12),
                    foregroundColor: Colors.white,
                  ),
                  icon: const Icon(Icons.tune_rounded),
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          Row(
            children: [
              Expanded(
                child: Text(
                  _getSelectedFiltersLabel(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.74),
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ),
              Text(
                '$resultsCount perfil${resultsCount == 1 ? '' : 'is'}',
                style: TextStyle(
                  color: olympusGold,
                  fontWeight: FontWeight.w900,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ignore: unused_element
  Widget _buildFiltersBar(int resultsCount) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
      child: Column(
        children: [
          Row(
            children: [
              _buildFilterDropdown(
                icon: Icons.filter_alt_outlined,
                label: 'Gênero',
                value: _selectedGenderFilter,
                items: const [
                  DropdownMenuItem(value: 'Todos', child: Text('Todos')),
                  DropdownMenuItem(
                    value: 'Masculino',
                    child: Text('Masculino'),
                  ),
                  DropdownMenuItem(value: 'Feminino', child: Text('Feminino')),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  setState(() => _selectedGenderFilter = value);
                },
              ),
              const SizedBox(width: 10),
              _buildFilterDropdown(
                icon: Icons.badge_outlined,
                label: 'Tipo de usuário',
                value: _selectedUserTypeFilter,
                items: const [
                  DropdownMenuItem(value: 'Todos', child: Text('Todos')),
                  DropdownMenuItem(value: 'member', child: Text('Membro')),
                  DropdownMenuItem(value: 'athlete', child: Text('Atleta')),
                  DropdownMenuItem(value: 'coach', child: Text('Técnico')),
                  DropdownMenuItem(
                    value: 'admin',
                    child: Text('Administrador'),
                  ),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  setState(() => _selectedUserTypeFilter = value);
                },
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _buildStatusToggleButton(
                  icon: Icons.verified_user_outlined,
                  title: 'Usuários Ativos',
                  selected: !_showInactiveUsers,
                  onTap: () => setState(() => _showInactiveUsers = false),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildStatusToggleButton(
                  icon: Icons.person_off_outlined,
                  title: 'Usuários Inativos',
                  selected: _showInactiveUsers,
                  onTap: () => setState(() => _showInactiveUsers = true),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.10),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withOpacity(0.14)),
            ),
            child: Row(
              children: [
                Icon(Icons.people_alt_outlined, color: olympusGold, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _getSelectedFiltersLabel(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: olympusGold.withOpacity(0.18),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: olympusGold.withOpacity(0.28)),
                  ),
                  child: Text(
                    '$resultsCount resultado${resultsCount == 1 ? '' : 's'}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String? _resolveProfileAvatarUrl(dynamic rawValue) {
    final value = (rawValue ?? '').toString().trim();
    if (value.isEmpty) return null;
    if (value.startsWith('http://') || value.startsWith('https://')) {
      return value;
    }
    return supabase.storage.from('avatars').getPublicUrl(value);
  }

  int _roleSortIndex(String role) {
    const order = <String>['athlete', 'coach', 'admin', 'member'];
    final index = order.indexOf(role);
    return index < 0 ? order.length : index;
  }

  IconData _iconForRole(String role) {
    switch (role) {
      case 'athlete':
        return Icons.sports_volleyball_rounded;
      case 'coach':
        return Icons.sports_rounded;
      case 'admin':
        return Icons.admin_panel_settings_rounded;
      default:
        return Icons.person_outline_rounded;
    }
  }

  Widget _profileAvatarFallback(
    Map<String, dynamic> profile,
    String visualRole,
  ) {
    final name = (profile['full_name'] ?? '').toString().trim();
    return Container(
      color: _getColorForType(visualRole).withOpacity(0.18),
      alignment: Alignment.center,
      child: Text(
        name.isEmpty ? '?' : name[0].toUpperCase(),
        style: TextStyle(
          color: _getColorForType(visualRole),
          fontWeight: FontWeight.w900,
          fontSize: 19,
        ),
      ),
    );
  }

  Widget _buildProfileCard(Map<String, dynamic> profile) {
    final avatarUrl = _resolveProfileAvatarUrl(profile['avatar_url']);
    final activeRoles = _rolesForProfile(profile)
      ..sort((a, b) => _roleSortIndex(a).compareTo(_roleSortIndex(b)));
    final userType = _visualRoleForProfile(profile);
    final isAthlete = activeRoles.contains('athlete');
    final isTechnicalProfessional = userType.toLowerCase() == 'coach' ||
        activeRoles.any(
          (role) => const {
            'coach',
            'treinador',
            'technical_coordinator',
            'head_coach',
            'assistant_coach',
            'intern',
          }.contains(role.toLowerCase()),
        );
    final phone = (profile['phone'] ?? '').toString();
    final cpf = (profile['cpf'] ?? '').toString();
    final gender = (profile['gender'] ?? '').toString();
    final coachTeamGender = (profile['coach_team_gender'] ?? '').toString();
    final isActive = _isProfileActive(profile);

    final cardColor = isActive ? olympusBlue : Colors.grey;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 6),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  cardColor.withOpacity(0.25),
                  cardColor.withOpacity(0.15),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: cardColor.withOpacity(0.35),
                width: 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.16),
                  blurRadius: 16,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: () => showProfileDialog(profile: profile),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 11, 6, 11),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: _getColorForType(userType).withOpacity(0.35),
                          width: 2,
                        ),
                      ),
                      child: ClipOval(
                        child: avatarUrl == null
                            ? _profileAvatarFallback(profile, userType)
                            : CachedNetworkImage(
                                imageUrl: avatarUrl,
                                fit: BoxFit.cover,
                                alignment: Alignment.topCenter,
                                width: 50,
                                height: 50,
                                memCacheWidth: 240,
                                filterQuality: FilterQuality.high,
                                fadeInDuration: const Duration(
                                  milliseconds: 120,
                                ),
                                placeholder: (_, __) => Container(
                                  color: _getColorForType(
                                    userType,
                                  ).withOpacity(0.12),
                                ),
                                errorWidget: (_, __, ___) =>
                                    _profileAvatarFallback(profile, userType),
                              ),
                      ),
                    ),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            profile['full_name'] ?? 'Sem nome',
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                              fontSize: 18,
                              height: 1.1,
                            ),
                          ),
                          const SizedBox(height: 7),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              ...activeRoles.map(
                                (role) => _buildBadge(
                                  icon: _iconForRole(role),
                                  label: _getTypeLabel(role),
                                  color: _getColorForType(role),
                                ),
                              ),
                              if (!isActive)
                                _buildBadge(
                                  icon: Icons.block_rounded,
                                  label: 'Inativo',
                                  color: Colors.redAccent,
                                ),
                              if (gender.isNotEmpty)
                                _buildBadge(
                                  icon: Icons.wc,
                                  label: gender,
                                  color: cardColor,
                                ),
                              if (userType == 'coach')
                                _buildBadge(
                                  icon: Icons.groups_2_outlined,
                                  label: _getCoachTeamGenderLabel(
                                    coachTeamGender,
                                  ),
                                  color: olympusGold,
                                ),
                            ],
                          ),
                          if (phone.isNotEmpty || cpf.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 12,
                              runSpacing: 5,
                              children: [
                                if (phone.isNotEmpty)
                                  _buildProfileInfoLine(
                                    icon: Icons.phone_outlined,
                                    text: _formatPhone(phone),
                                  ),
                                if (cpf.isNotEmpty)
                                  _buildProfileInfoLine(
                                    icon: Icons.credit_card_outlined,
                                    text: 'CPF: ${_formatCpf(cpf)}',
                                  ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                    PopupMenuButton<String>(
                      icon: Icon(Icons.more_vert_rounded, color: olympusGold),
                      tooltip: 'Ações do perfil',
                      color: Color.lerp(olympusBlue, Colors.black, 0.28),
                      surfaceTintColor: Colors.transparent,
                      elevation: 14,
                      offset: const Offset(-8, 8),
                      constraints: const BoxConstraints(
                        minWidth: 220,
                        maxWidth: 260,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                        side: BorderSide(color: olympusGold.withOpacity(0.28)),
                      ),
                      onSelected: (value) {
                        if (value == 'edit') {
                          showProfileDialog(profile: profile);
                        } else if (value == 'delete') {
                          _confirmDelete(profile);
                        } else if (value == 'permissions') {
                          _showPermissionsDialog(profile);
                        } else if (value == 'technical_access') {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => AdminTechnicalStaffPage(
                                initialUserId: profile['id']?.toString(),
                              ),
                            ),
                          ).then((_) => fetchProfiles());
                        } else if (value == 'training_days') {
                          _showTrainingDaysDialog(profile);
                        } else if (value == 'reset_password') {
                          _showResetPasswordDialog(profile);
                        } else if (value == 'toggle_active') {
                          _setProfileActive(
                            profile,
                            !_isProfileActive(profile),
                          );
                        }
                      },
                      itemBuilder: (context) => [
                        _buildProfileMenuItem(
                          value: 'edit',
                          icon: Icons.edit_outlined,
                          label: 'Editar perfil',
                        ),
                        _buildProfileMenuItem(
                          value: 'permissions',
                          icon: Icons.lock_person_outlined,
                          label: 'Permissões',
                        ),
                        if (isTechnicalProfessional)
                          _buildProfileMenuItem(
                            value: 'technical_access',
                            icon: Icons.account_tree_rounded,
                            label: 'Função e acessos técnicos',
                            color: olympusGold,
                          ),
                        if (isAthlete)
                          _buildProfileMenuItem(
                            value: 'training_days',
                            icon: Icons.calendar_month_outlined,
                            label: 'Dias de treino',
                          ),
                        _buildProfileMenuItem(
                          value: 'reset_password',
                          icon: Icons.password_rounded,
                          label: 'Resetar senha',
                        ),
                        const PopupMenuDivider(height: 10),
                        _buildProfileMenuItem(
                          value: 'toggle_active',
                          icon: isActive
                              ? Icons.person_off_outlined
                              : Icons.person_add_alt_1_rounded,
                          label: isActive
                              ? 'Inativar usuário'
                              : 'Reativar usuário',
                          color: isActive
                              ? const Color(0xFFFFC857)
                              : const Color(0xFF73E2A7),
                        ),
                        _buildProfileMenuItem(
                          value: 'delete',
                          icon: Icons.delete_outline_rounded,
                          label: 'Excluir definitivamente',
                          color: const Color(0xFFFF7B7B),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  PopupMenuItem<String> _buildProfileMenuItem({
    required String value,
    required IconData icon,
    required String label,
    Color color = Colors.white,
  }) {
    return PopupMenuItem<String>(
      value: value,
      height: 48,
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: color.withOpacity(0.10),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 19, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBadge({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.20)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileInfoLine({required IconData icon, required String text}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: olympusGold),
        const SizedBox(width: 6),
        Text(
          text,
          style: TextStyle(
            fontSize: 12.5,
            color: Colors.white.withOpacity(0.85),
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildPremiumBackground() {
    return Stack(
      children: [
        Positioned.fill(
          child: OlympusBrandBackgroundImage(
            fit: BoxFit.cover,
            alignment: Alignment.center,
            errorBuilder: (context, error, stackTrace) =>
                Container(color: const Color(0xFF102845)),
          ),
        ),
        Positioned.fill(
          child: Container(color: Colors.black.withOpacity(0.14)),
        ),
        Positioned.fill(
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  olympusBlue.withOpacity(0.56),
                  olympusLightBlue.withOpacity(0.26),
                  Colors.black.withOpacity(0.62),
                ],
              ),
            ),
          ),
        ),
        Positioned.fill(
          child: Container(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(0, -0.78),
                radius: 1.08,
                colors: [
                  olympusGold.withOpacity(0.12),
                  Colors.transparent,
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildGlassContentShell({required Widget child}) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 420;
        final horizontal = isCompact ? 10.0 : 14.0;
        final top = isCompact ? 10.0 : 14.0;
        return Padding(
          padding: EdgeInsets.fromLTRB(horizontal, top, horizontal, 18),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.white.withOpacity(0.14),
                      Colors.white.withOpacity(0.08),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.20),
                    width: 1.1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.16),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: child,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildProfilesEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.people_outline, size: 80, color: Colors.white70),
          const SizedBox(height: 16),
          Text(
            'Nenhum perfil encontrado para os filtros selecionados',
            style: TextStyle(
              fontSize: 16,
              color: Colors.white.withOpacity(0.92),
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final branding = OlympusBrandingController.instance.branding;
    final primary = branding.primaryColor;
    final secondary = branding.secondaryColor;
    final onPrimary = Theme.of(context).colorScheme.onPrimary;
    final filteredProfiles = _getFilteredProfiles();

    if (_isCheckingAccess) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Perfis - ${branding.teamName}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            FutureBuilder<String?>(
              future: _getCurrentUserType(),
              builder: (context, snapshot) {
                if (snapshot.hasData && snapshot.data != null) {
                  return Text(
                    '👤 ${_getUserTypeLabel(snapshot.data)}',
                    style: TextStyle(
                      fontSize: 12,
                      color: secondary.withOpacity(0.9),
                    ),
                  );
                }
                return const SizedBox.shrink();
              },
            ),
          ],
        ),
        centerTitle: false,
        backgroundColor: primary,
        foregroundColor: onPrimary,
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
          IconButton(icon: const Icon(Icons.refresh), onPressed: fetchProfiles),
        ],
      ),
      body: Stack(
        children: [
          Positioned.fill(child: _buildPremiumBackground()),
          isLoading
              ? Center(
                  child: CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(secondary),
                  ),
                )
              : _buildGlassContentShell(
                  child: Column(
                    children: [
                      _buildCompactFiltersBar(filteredProfiles.length),
                      Expanded(
                        child: filteredProfiles.isEmpty
                            ? _buildProfilesEmptyState()
                            : ListView.builder(
                                itemCount: filteredProfiles.length,
                                padding: const EdgeInsets.fromLTRB(8, 4, 8, 92),
                                itemBuilder: (context, index) {
                                  return _buildProfileCard(
                                    filteredProfiles[index],
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showProfileDialog(),
        icon: const Icon(Icons.person_add),
        label: const Text('Novo Perfil'),
        backgroundColor: secondary,
        foregroundColor: primary,
        elevation: 4,
      ),
    );
  }

  String _getCoachTeamGenderLabel(String? value) {
    switch ((value ?? '').trim().toLowerCase()) {
      case 'masculino':
        return 'Time masculino';
      case 'feminino':
        return 'Time feminino';
      case 'ambos':
      case 'all':
        return 'Times masculino e feminino';
      default:
        return 'Time não definido';
    }
  }

  String _formatCpf(String? cpf) {
    if (cpf == null) return '';
    final numbers = cpf.toString().replaceAll(RegExp(r'\D'), '');
    if (numbers.length != 11) return cpf.toString();
    return '${numbers.substring(0, 3)}.${numbers.substring(3, 6)}.${numbers.substring(6, 9)}-${numbers.substring(9)}';
  }

  String _formatPhone(String? phone) {
    if (phone == null) return '';
    final numbers = phone.toString().replaceAll(RegExp(r'\D'), '');
    if (numbers.length == 11) {
      return '(${numbers.substring(0, 2)}) ${numbers.substring(2, 7)}-${numbers.substring(7)}';
    } else if (numbers.length == 10) {
      return '(${numbers.substring(0, 2)}) ${numbers.substring(2, 6)}-${numbers.substring(6)}';
    }
    return phone.toString();
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

// ════════════════════════════════════════════════════════════════════════════
// ProfileFormDialog
// ════════════════════════════════════════════════════════════════════════════

class ProfileFormDialog extends StatefulWidget {
  final Map<String, dynamic>? profile;
  final Future<void> Function(Map<String, dynamic> data) onSave;

  const ProfileFormDialog({super.key, this.profile, required this.onSave});

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

  OlympusBranding get _branding => OlympusBrandingController.instance.branding;
  Color get olympusBlue => _branding.primaryColor;
  Color get olympusGold => _branding.secondaryColor;
  Color get olympusLightBlue =>
      Color.lerp(_branding.primaryColor, _branding.surfaceColor, 0.20)!;

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
    _fullNameController = TextEditingController(
      text: widget.profile?['full_name'] ?? '',
    );
    _phoneController = MaskedTextController(
      mask: '(00) 00000-0000',
      text: widget.profile?['phone'] ?? '',
    );
    _birthDateController = TextEditingController(
      text: widget.profile?['birth_date'] ?? '',
    );
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
    _streetController = TextEditingController(
      text: widget.profile?['street'] ?? '',
    );
    _streetNumberController = TextEditingController(
      text: widget.profile?['street_number'] ?? '',
    );
    _complementController = TextEditingController(
      text: widget.profile?['complement'] ?? '',
    );
    _neighborhoodController = TextEditingController(
      text: widget.profile?['neighborhood'] ?? '',
    );
    _cityController = TextEditingController(
      text: widget.profile?['city'] ?? '',
    );
    _stateController = TextEditingController(
      text: widget.profile?['state'] ?? '',
    );
    _avatarUrlController = TextEditingController(
      text: widget.profile?['avatar_url'] ?? '',
    );
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
      final response = await http.get(
        Uri.parse('https://viacep.com.br/ws/$cep/json/'),
      );
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
            SnackBar(
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
      if (mounted) setState(() => _isFetchingCep = false);
    }
  }

  Future<void> _pickImage() async {
    try {
      final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
      if (image != null) setState(() => _selectedImage = image);
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
    if (mounted) setState(() => _isUploading = true);
    try {
      final sessionUserId = Supabase.instance.client.auth.currentUser?.id;
      if (sessionUserId == null) {
        throw StateError(
            'Sessão expirada. Entre novamente para salvar a foto.');
      }
      final profileOwnerId =
          (widget.profile?['id'] ?? sessionUserId).toString().trim();
      await OrganizationContextService.instance.initialize(force: true);
      final fileName = OrganizationStorageService.scopedPath(
        'avatars/$profileOwnerId/${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      final supabase = Supabase.instance.client;
      final sourceBytes = await _selectedImage!.readAsBytes();
      final decoded = img.decodeImage(sourceBytes);
      if (decoded == null) {
        throw const FormatException('Formato de imagem nao suportado.');
      }

      final oriented = img.bakeOrientation(decoded);
      const maxSide = 1600;
      final normalized = oriented.width >= oriented.height
          ? oriented.width > maxSide
              ? img.copyResize(
                  oriented,
                  width: maxSide,
                  interpolation: img.Interpolation.cubic,
                )
              : oriented
          : oriented.height > maxSide
              ? img.copyResize(
                  oriented,
                  height: maxSide,
                  interpolation: img.Interpolation.cubic,
                )
              : oriented;
      final fileBytes = Uint8List.fromList(
        img.encodeJpg(normalized, quality: 88),
      );

      await supabase.storage.from('avatars').uploadBinary(
            fileName,
            fileBytes,
            fileOptions: const FileOptions(
              upsert: true,
              contentType: 'image/jpeg',
            ),
          );
      return supabase.storage.from('avatars').getPublicUrl(fileName);
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
      if (mounted) setState(() => _isUploading = false);
    }
  }

  Future<void> _selectDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: ColorScheme.light(
            primary: olympusGold,
            onPrimary: Colors.white,
          ),
        ),
        child: child!,
      ),
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
            decoration: BoxDecoration(
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
                        child: ClipOval(child: _getAvatarImage()),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Center(
                    child: TextButton.icon(
                      onPressed: _pickImage,
                      icon: Icon(Icons.photo_camera, color: olympusGold),
                      label: Text(
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
                      olympusGold,
                    ),
                    validator: (v) =>
                        v?.isEmpty ?? true ? 'Campo obrigatório' : null,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: _selectedUserType,
                    decoration: _inputDecoration(
                      'Tipo de Usuário *',
                      Icons.badge,
                      olympusGold,
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
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() {
                        _selectedUserType = value;
                        if (_selectedUserType != 'athlete') {
                          _selectedPosition = '';
                        }
                      });
                    },
                    validator: (v) => v == null ? 'Campo obrigatório' : null,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _cpfController,
                          decoration: _inputDecoration(
                            'CPF *',
                            Icons.credit_card,
                            olympusGold,
                          ),
                          keyboardType: TextInputType.number,
                          validator: (v) => _removeMask(v).length != 11
                              ? 'CPF inválido'
                              : null,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextFormField(
                          controller: _rgController,
                          decoration: _inputDecoration(
                            'RG *',
                            Icons.credit_card,
                            olympusGold,
                          ),
                          keyboardType: TextInputType.number,
                          validator: (v) =>
                              v?.isEmpty ?? true ? 'Campo obrigatório' : null,
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
                          decoration: _inputDecoration(
                            'Telefone *',
                            Icons.phone,
                            olympusGold,
                          ),
                          keyboardType: TextInputType.phone,
                          validator: (v) => _removeMask(v).length < 10
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
                          decoration: _inputDecoration(
                            'Gênero *',
                            Icons.transgender,
                            olympusGold,
                          ),
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
                          onChanged: (value) => setState(() {
                            _selectedGender = value ?? '';
                            _selectedPosition = '';
                          }),
                          validator: (v) =>
                              v == null ? 'Campo obrigatório' : null,
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
                      prefixIcon: Icon(
                        Icons.calendar_today,
                        color: olympusGold,
                      ),
                      suffixIcon: IconButton(
                        icon: Icon(
                          Icons.calendar_today,
                          color: olympusGold,
                        ),
                        onPressed: _selectDate,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderSide: BorderSide(
                          color: olympusGold,
                          width: 2,
                        ),
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
                      decoration: _inputDecoration(
                        'Posição na Quadra',
                        Icons.sports_volleyball,
                        olympusGold,
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
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Icon(
                        Icons.location_on,
                        color: olympusGold,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
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
                      prefixIcon: Icon(
                        Icons.location_on,
                        color: olympusGold,
                      ),
                      suffixIcon: _isFetchingCep
                          ? SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  olympusGold,
                                ),
                              ),
                            )
                          : null,
                      focusedBorder: OutlineInputBorder(
                        borderSide: BorderSide(
                          color: olympusGold,
                          width: 2,
                        ),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    keyboardType: TextInputType.number,
                    maxLength: 9,
                    validator: (v) =>
                        _removeMask(v).length != 8 ? 'CEP inválido' : null,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: TextFormField(
                          controller: _streetController,
                          decoration: _inputDecoration(
                            'Rua *',
                            Icons.home,
                            olympusGold,
                          ),
                          validator: (v) =>
                              v?.isEmpty ?? true ? 'Campo obrigatório' : null,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextFormField(
                          controller: _streetNumberController,
                          decoration: _inputDecoration(
                            'Número *',
                            Icons.numbers,
                            olympusGold,
                          ),
                          keyboardType: TextInputType.number,
                          validator: (v) =>
                              v?.isEmpty ?? true ? 'Campo obrigatório' : null,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _complementController,
                    decoration: _inputDecoration(
                      'Complemento',
                      Icons.info_outline,
                      olympusGold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _neighborhoodController,
                    decoration: _inputDecoration(
                      'Bairro *',
                      Icons.location_city,
                      olympusGold,
                    ),
                    validator: (v) =>
                        v?.isEmpty ?? true ? 'Campo obrigatório' : null,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: TextFormField(
                          controller: _cityController,
                          decoration: _inputDecoration(
                            'Cidade *',
                            Icons.location_city,
                            olympusGold,
                          ),
                          validator: (v) =>
                              v?.isEmpty ?? true ? 'Campo obrigatório' : null,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextFormField(
                          controller: _stateController,
                          decoration: _inputDecoration(
                            'Estado *',
                            Icons.map,
                            olympusGold,
                          ),
                          maxLength: 2,
                          validator: (v) =>
                              v?.isEmpty ?? true ? 'Campo obrigatório' : null,
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: _isLoading || _isUploading
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            olympusBlue,
                          ),
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

  InputDecoration _inputDecoration(
    String label,
    IconData icon,
    Color iconColor,
  ) {
    return InputDecoration(
      labelText: label,
      border: const OutlineInputBorder(),
      prefixIcon: Icon(icon, color: iconColor),
      focusedBorder: OutlineInputBorder(
        borderSide: BorderSide(color: iconColor, width: 2),
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }

  Widget _getAvatarImage() {
    if (_selectedImage != null) {
      return FutureBuilder<Uint8List?>(
        future: _selectedImage!.readAsBytes(),
        builder: (context, snapshot) {
          if (snapshot.hasData && snapshot.data != null) {
            return Image.memory(
              snapshot.data!,
              fit: BoxFit.cover,
              alignment: Alignment.topCenter,
              cacheWidth: 800,
              filterQuality: FilterQuality.high,
            );
          }
          return const Icon(Icons.person, size: 60, color: Colors.grey);
        },
      );
    }
    if (widget.profile?['avatar_url'] != null &&
        widget.profile!['avatar_url'].toString().isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: widget.profile!['avatar_url'].toString(),
        fit: BoxFit.cover,
        alignment: Alignment.topCenter,
        memCacheWidth: 320,
        maxWidthDiskCache: 640,
        filterQuality: FilterQuality.high,
        fadeInDuration: const Duration(milliseconds: 120),
        errorWidget: (c, o, s) =>
            const Icon(Icons.person, size: 60, color: Colors.grey),
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
      if (uploadedUrl != null) avatarUrl = uploadedUrl;
    }
    if (!mounted) return;
    final data = <String, dynamic>{
      'full_name': _fullNameController.text.trim(),
      'user_type': _selectedUserType,
      if (widget.profile == null) 'is_active': true,
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
    if (mounted) Navigator.pop(context);
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
