// lib/widgets/role_manager_widget.dart

import 'package:flutter/material.dart';
import '../services/role_service.dart';

/// Widget reutilizável para gerenciar múltiplos papéis de um usuário.
/// Integrado com RoleService — compatível com Supabase (tabela user_roles + profiles).
/// Pode ser inserido dentro de qualquer dialog ou página de admin.
class RoleManagerWidget extends StatefulWidget {
  final String userId;
  final String userName;
  final String currentPrimaryRole;

  /// Callback opcional chamado após salvar com sucesso.
  /// Recebe o papel primário atualizado.
  final void Function(String newPrimaryRole)? onRolesSaved;

  const RoleManagerWidget({
    super.key,
    required this.userId,
    required this.userName,
    required this.currentPrimaryRole,
    this.onRolesSaved,
  });

  @override
  State<RoleManagerWidget> createState() => _RoleManagerWidgetState();
}

class _RoleManagerWidgetState extends State<RoleManagerWidget> {
  final RoleService _roleService = RoleService();

  // ─── Paleta Olympus ────────────────────────────────────────────────────────
  static const Color _blue = Color(0xFF1E3A5F);
  static const Color _gold = Color(0xFFD4AF37);
  static const Color _lightBlue = Color(0xFF2C5F8D);

  // ─── Estado ────────────────────────────────────────────────────────────────
  List<String> _activeRoles = [];
  String _primaryRole = '';
  bool _isLoading = true;
  bool _isSaving = false;

  // ─── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _primaryRole = widget.currentPrimaryRole;
    _loadRoles();
  }

  // ─── Lógica ────────────────────────────────────────────────────────────────

  Future<void> _loadRoles() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      final roles = await _roleService.getUserRoles(widget.userId);
      if (!mounted) return;
      setState(() {
        _activeRoles = roles.isNotEmpty ? roles : [widget.currentPrimaryRole];

        // Garante que o papel primário atual é válido dentro dos ativos
        if (!_activeRoles.contains(_primaryRole)) {
          _primaryRole = _activeRoles.first;
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _activeRoles = [widget.currentPrimaryRole];
        _primaryRole = widget.currentPrimaryRole;
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _save() async {
    if (_activeRoles.isEmpty) {
      _showSnack('Selecione pelo menos um papel.', Colors.orange);
      return;
    }

    // Garante consistência: papel primário deve estar na lista ativa
    if (!_activeRoles.contains(_primaryRole)) {
      setState(() => _primaryRole = _activeRoles.first);
    }

    setState(() => _isSaving = true);

    try {
      await _roleService.setRoles(
        userId: widget.userId,
        roles: _activeRoles,
        primaryRole: _primaryRole,
      );

      if (!mounted) return;

      _showSnack('✅ Papéis atualizados com sucesso!', Colors.green);

      // Notifica o pai sobre a mudança (ex: atualizar profiles_page)
      widget.onRolesSaved?.call(_primaryRole);
    } catch (e) {
      if (!mounted) return;
      _showSnack('Erro ao salvar papéis: $e', Colors.red);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _toggleRole(String role) {
    final updated = List<String>.from(_activeRoles);

    if (updated.contains(role)) {
      // Impede remoção do último papel
      if (updated.length == 1) {
        _showSnack(
          'O usuário deve ter pelo menos um papel.',
          Colors.orange,
        );
        return;
      }
      updated.remove(role);

      // Se removeu o papel primário, redefine para o primeiro da lista
      if (_primaryRole == role) {
        setState(() => _primaryRole = updated.first);
      }
    } else {
      updated.add(role);
    }

    setState(() => _activeRoles = updated);
  }

  Future<void> _setPrimary(String role) async {
    if (!_activeRoles.contains(role) || _isSaving) return;

    final previousPrimaryRole = _primaryRole;
    setState(() {
      _primaryRole = role;
      _isSaving = true;
    });

    try {
      await _roleService.setRoles(
        userId: widget.userId,
        roles: _activeRoles,
        primaryRole: role,
      );
      if (!mounted) return;
      widget.onRolesSaved?.call(role);
      _showSnack(
        '⭐ ${RoleService.roleLabels[role] ?? role} definido como papel principal.',
        Colors.green,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _primaryRole = previousPrimaryRole);
      _showSnack('Erro ao definir papel principal: $e', Colors.red);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _showSnack(String message, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  IconData _iconForRole(String role) {
    switch (role) {
      case 'admin':
        return Icons.admin_panel_settings_rounded;
      case 'coach':
        return Icons.sports_rounded;
      case 'athlete':
        return Icons.sports_volleyball_rounded;
      case 'member':
        return Icons.group_rounded;
      default:
        return Icons.person_rounded;
    }
  }

  // ─── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            _blue.withOpacity(0.95),
            _lightBlue.withOpacity(0.88),
          ],
        ),
        border: Border.all(color: _gold.withOpacity(0.45)),
        boxShadow: [
          BoxShadow(
            color: _blue.withOpacity(0.22),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(),
          const SizedBox(height: 16),
          if (_isLoading)
            const Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(_gold),
              ),
            )
          else ...[
            _buildRoleChips(),
            const SizedBox(height: 12),
            if (_activeRoles.length > 1) _buildPrimaryRoleHint(),
            const SizedBox(height: 14),
            _buildSaveButton(),
          ],
        ],
      ),
    );
  }

  // ─── Sub-widgets ───────────────────────────────────────────────────────────

  Widget _buildHeader() {
    return Row(
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
            Icons.switch_account_rounded,
            color: Colors.white,
            size: 23,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.userName,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              const Text(
                'Papéis do usuário',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Um usuário pode ter múltiplos papéis simultâneos.',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.75),
                  fontSize: 11.5,
                  fontWeight: FontWeight.w500,
                  height: 1.25,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildRoleChips() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: RoleService.validRoles.map((role) {
        final isSelected = _activeRoles.contains(role);
        final isPrimary = _primaryRole == role && isSelected;

        return GestureDetector(
          onLongPress: isSelected ? () => _setPrimary(role) : null,
          child: ChoiceChip(
            selected: isSelected,
            showCheckmark: false,
            avatar: Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(
                  _iconForRole(role),
                  size: 17,
                  color: isSelected ? _blue : _blue.withOpacity(0.70),
                ),
                if (isPrimary)
                  Positioned(
                    right: -4,
                    top: -4,
                    child: Container(
                      width: 9,
                      height: 9,
                      decoration: const BoxDecoration(
                        color: Colors.orange,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
              ],
            ),
            label: Text(RoleService.roleLabels[role] ?? role),
            selectedColor: _gold,
            backgroundColor: const Color(0xFFF4F7FB),
            side: BorderSide(
              color: isSelected ? _gold : Colors.white.withOpacity(0.55),
            ),
            labelStyle: TextStyle(
              color: isSelected ? _blue : _blue.withOpacity(0.75),
              fontWeight: FontWeight.w900,
              fontSize: 13,
            ),
            onSelected: (_) => _toggleRole(role),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildPrimaryRoleHint() {
    return Text(
      '🟠 Segure um chip para definir como papel principal  '
      '(atual: ${RoleService.roleLabels[_primaryRole] ?? _primaryRole})',
      style: TextStyle(
        color: Colors.white.withOpacity(0.72),
        fontSize: 11.5,
        fontStyle: FontStyle.italic,
      ),
    );
  }

  Widget _buildSaveButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: _isSaving ? null : _save,
        icon: _isSaving
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(_blue),
                ),
              )
            : const Icon(Icons.save_rounded, size: 18),
        label: Text(
          _isSaving ? 'Salvando...' : 'Salvar papéis',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: _gold,
          foregroundColor: _blue,
          disabledBackgroundColor: _gold.withOpacity(0.55),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(vertical: 13),
          elevation: 0,
        ),
      ),
    );
  }
}
