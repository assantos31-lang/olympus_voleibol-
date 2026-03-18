import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import '../models/chat_message.dart';
import '../models/chat_room.dart';
import '../services/chat_service.dart';

class ChatPage extends StatefulWidget {
  final ChatRoom room;
  const ChatPage({super.key, required this.room});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final ChatService _chatService = ChatService();
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ImagePicker _imagePicker = ImagePicker();
  bool _sending = false;
  bool _updatingRoom = false;
  late ChatRoom _room;
  String? _myRole;
  List<Map<String, dynamic>> _participants = [];
  String? _lastMarkedMessageId;
  final Map<String, String?> _participantPhotoUrls = {};
  final Map<String, String> _participantNames = {};
  Timer? _typingTimer;
  static const Color _gold = Color(0xFFD4B06A);
  static const Color _goldSoft = Color(0xFFE8D19A);
  static const Color _navy = Color(0xFF0E2A57);
  static const Color _navyDark = Color(0xFF091428);

  @override
  void initState() {
    super.initState();
    _room = widget.room;
    _loadMyRole();
    _markAsRead();
    _loadParticipantsForAvatars();
    _chatService.setCurrentUserOnline(true);
    _controller.addListener(_handleTypingChanged);
  }

  @override
  void dispose() {
    _typingTimer?.cancel();
    _controller.removeListener(_handleTypingChanged);
    _chatService.setTypingStatus(roomId: _room.id, isTyping: false);
    _chatService.setCurrentUserOnline(false);
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _handleTypingChanged() {
    final hasText = _controller.text.trim().isNotEmpty;
    _chatService.setTypingStatus(roomId: _room.id, isTyping: hasText);
    _typingTimer?.cancel();
    if (hasText) {
      _typingTimer = Timer(const Duration(seconds: 2), () {
        _chatService.setTypingStatus(roomId: _room.id, isTyping: false);
      });
    }
  }

  Future<void> _loadMyRole() async {
    final role = await _chatService.getMyRoleInRoom(_room.id);
    if (!mounted) return;
    setState(() {
      _myRole = role;
    });
  }

  Future<void> _loadMyRoom() async {
    final updatedRoom = await _chatService.getRoomById(_room.id);
    if (!mounted || updatedRoom == null) return;
    setState(() {
      _room = updatedRoom;
    });
  }

  Future<void> _loadParticipantsForAvatars() async {
    try {
      final participants = await _chatService.getRoomParticipants(_room.id);
      if (!mounted) return;
      final photoMap = <String, String?>{};
      final nameMap = <String, String>{};
      for (final participant in participants) {
        final userId =
            (participant['user_id'] ?? participant['id'] ?? '').toString();
        if (userId.isEmpty) continue;
        final fullName = (participant['full_name'] ??
                participant['name'] ??
                participant['username'] ??
                _extractNestedValue(participant, const [
                  'profiles',
                  'full_name',
                ]) ??
                _extractNestedValue(participant, const [
                  'profile',
                  'full_name',
                ]) ??
                _extractNestedValue(participant, const [
                  'user',
                  'full_name',
                ]) ??
                'Sem nome')
            .toString();
        final photoUrl = _extractParticipantPhoto(participant);
        photoMap[userId] = photoUrl;
        nameMap[userId] = fullName;
      }
      setState(() {
        _participants = participants;
        _participantPhotoUrls
          ..clear()
          ..addAll(photoMap);
        _participantNames
          ..clear()
          ..addAll(nameMap);
      });
    } catch (_) {}
  }

  String? _resolveAvatarUrl(String? rawValue) {
    final value = rawValue?.trim();
    if (value == null || value.isEmpty) return null;
    if (value.startsWith('http://') || value.startsWith('https://')) {
      return value;
    }
    return _chatService.supabase.storage.from('avatars').getPublicUrl(value);
  }

  dynamic _extractNestedValue(
    Map<String, dynamic> source,
    List<String> path,
  ) {
    dynamic current = source;
    for (final key in path) {
      if (current is Map<String, dynamic> && current.containsKey(key)) {
        current = current[key];
      } else {
        return null;
      }
    }
    return current;
  }

  String? _extractParticipantPhoto(Map<String, dynamic> participant) {
    const possibleKeys = [
      'avatar_url',
      'photo_url',
      'profile_image_url',
      'image_url',
      'avatar',
      'photo',
    ];
    for (final key in possibleKeys) {
      final value = participant[key]?.toString();
      final resolved = _resolveAvatarUrl(value);
      if (resolved != null && resolved.isNotEmpty) {
        return resolved;
      }
    }
    const nestedPaths = [
      ['profiles', 'avatar_url'],
      ['profiles', 'photo_url'],
      ['profiles', 'profile_image_url'],
      ['profile', 'avatar_url'],
      ['profile', 'photo_url'],
      ['profile', 'profile_image_url'],
      ['user', 'avatar_url'],
      ['user', 'photo_url'],
      ['user', 'profile_image_url'],
    ];
    for (final path in nestedPaths) {
      final value = _extractNestedValue(participant, path)?.toString();
      final resolved = _resolveAvatarUrl(value);
      if (resolved != null && resolved.isNotEmpty) {
        return resolved;
      }
    }
    return null;
  }

  // ✅ NOVO: Método para obter a URL do avatar correto para exibição no header
  String? _getHeaderAvatarUrl() {
    // Para grupos, usa o avatar da sala
    if (_room.type == 'group') {
      return _resolveAvatarUrl(_room.avatarUrl);
    }

    // Para conversas individuais, usa o avatar do outro participante
    final currentUserId = _chatService.currentUserId;
    for (final entry in _participantPhotoUrls.entries) {
      if (entry.key != currentUserId && entry.value != null) {
        return entry.value;
      }
    }

    // Fallback: tenta pegar do primeiro participante que não é eu
    for (final participant in _participants) {
      final userId = (participant['user_id'] ?? '').toString();
      if (userId.isNotEmpty && userId != currentUserId) {
        final photoUrl = _extractParticipantPhoto(participant);
        if (photoUrl != null) {
          return photoUrl;
        }
      }
    }

    return null;
  }

  // ✅ NOVO: Método para obter o nome correto para exibição no header
  String _getHeaderDisplayName() {
    // Para grupos, usa o nome da sala
    if (_room.type == 'group') {
      return _room.name?.trim().isNotEmpty == true ? _room.name! : 'Grupo';
    }

    // Para conversas individuais, usa o nome do outro participante
    final currentUserId = _chatService.currentUserId;
    for (final entry in _participantNames.entries) {
      if (entry.key != currentUserId && entry.value.isNotEmpty) {
        return entry.value;
      }
    }

    // Fallback: nome da sala
    if (_room.name?.trim().isNotEmpty == true) {
      return _room.name!;
    }

    return 'Conversa';
  }

  Future<void> _markAsRead() async {
    try {
      await _chatService.markRoomMessagesAsRead(_room.id);
    } catch (_) {}
  }

  Future<void> _send() async {
    final text = _controller.text;
    if (text.trim().isEmpty) return;
    setState(() => _sending = true);
    try {
      await _chatService.setTypingStatus(roomId: _room.id, isTyping: false);
      await _chatService.sendMessage(
        roomId: _room.id,
        text: text,
      );
      _controller.clear();
      await Future.delayed(const Duration(milliseconds: 100));
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao enviar: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
    }
  }

  Future<void> _toggleRoomLock() async {
    setState(() => _updatingRoom = true);
    try {
      final nextLocked = !_room.isLocked;
      await _chatService.setRoomLocked(
        roomId: _room.id,
        locked: nextLocked,
      );
      await _loadMyRoom();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            nextLocked
                ? 'Grupo bloqueado com sucesso.'
                : 'Grupo desbloqueado com sucesso.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao atualizar grupo: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _updatingRoom = false);
      }
    }
  }

  Future<void> _toggleAdminOnly() async {
    setState(() => _updatingRoom = true);
    try {
      final nextAdminOnly = !_room.adminOnly;
      await _chatService.setRoomAdminOnly(
        roomId: _room.id,
        adminOnly: nextAdminOnly,
      );
      await _loadMyRoom();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            nextAdminOnly
                ? 'Grupo configurado para somente admin enviar.'
                : 'Grupo configurado para todos enviarem.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao atualizar grupo: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _updatingRoom = false);
      }
    }
  }

  Future<void> _showEditGroupDialog() async {
    if (_myRole != 'admin') return;
    final nameController = TextEditingController(text: _room.name ?? '');
    File? selectedImage;
    await showDialog(
      context: context,
      builder: (dialogContext) {
        bool saving = false;
        Future<void> pickImage(StateSetter setDialogState) async {
          final picked =
              await _imagePicker.pickImage(source: ImageSource.gallery);
          if (picked == null) return;
          setDialogState(() {
            selectedImage = File(picked.path);
          });
        }

        return StatefulBuilder(
          builder: (context, setDialogState) {
            final currentAvatar = _resolveAvatarUrl(_room.avatarUrl);
            return AlertDialog(
              title: const Text('Editar grupo'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  GestureDetector(
                    onTap: saving ? null : () => pickImage(setDialogState),
                    child: CircleAvatar(
                      radius: 36,
                      backgroundColor: _gold.withValues(alpha: 0.18),
                      backgroundImage: selectedImage != null
                          ? FileImage(selectedImage!)
                          : (currentAvatar != null
                              ? NetworkImage(currentAvatar)
                              : null),
                      child: selectedImage == null && currentAvatar == null
                          ? const Icon(Icons.camera_alt, color: _gold)
                          : null,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: 'Nome do grupo',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed:
                      saving ? null : () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancelar'),
                ),
                ElevatedButton(
                  onPressed: saving
                      ? null
                      : () async {
                          final nextName = nameController.text.trim();
                          if (nextName.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Informe um nome para o grupo'),
                              ),
                            );
                            return;
                          }
                          setDialogState(() {
                            saving = true;
                          });
                          try {
                            if (nextName != (_room.name ?? '').trim()) {
                              await _chatService.updateRoomName(
                                roomId: _room.id,
                                name: nextName,
                              );
                            }
                            if (selectedImage != null) {
                              final avatarPath =
                                  await _chatService.uploadRoomAvatar(
                                roomId: _room.id,
                                file: selectedImage!,
                              );
                              await _chatService.updateRoomAvatar(
                                roomId: _room.id,
                                avatarUrl: avatarPath,
                              );
                            }
                            await _loadMyRoom();
                            if (!mounted) return;
                            Navigator.of(dialogContext).pop();
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Grupo atualizado com sucesso.'),
                              ),
                            );
                          } catch (e) {
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Erro ao atualizar grupo: $e'),
                              ),
                            );
                            setDialogState(() {
                              saving = false;
                            });
                          }
                        },
                  child: saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Salvar'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _showParticipantsDialog() async {
    final canManageRoom = _chatService.currentUserId == _room.createdBy;
    Future<void> refreshDialog(StateSetter setDialogState) async {
      final participants = await _chatService.getRoomParticipants(_room.id);
      setDialogState(() {
        _participants = participants;
      });
      final photoMap = <String, String?>{};
      final nameMap = <String, String>{};
      for (final participant in participants) {
        final userId =
            (participant['user_id'] ?? participant['id'] ?? '').toString();
        if (userId.isEmpty) continue;
        photoMap[userId] = _extractParticipantPhoto(participant);
        nameMap[userId] = (participant['full_name'] ??
                participant['name'] ??
                participant['username'] ??
                _extractNestedValue(participant, const [
                  'profiles',
                  'full_name',
                ]) ??
                _extractNestedValue(participant, const [
                  'profile',
                  'full_name',
                ]) ??
                _extractNestedValue(participant, const [
                  'user',
                  'full_name',
                ]) ??
                'Sem nome')
            .toString();
      }
      if (!mounted) return;
      setState(() {
        _participantPhotoUrls
          ..clear()
          ..addAll(photoMap);
        _participantNames
          ..clear()
          ..addAll(nameMap);
      });
    }

    _participants = await _chatService.getRoomParticipants(_room.id);
    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (dialogContext) {
        bool loading = false;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Participantes'),
              content: SizedBox(
                width: double.maxFinite,
                child: _participants.isEmpty
                    ? const Text('Nenhum participante encontrado.')
                    : ListView.separated(
                        shrinkWrap: true,
                        itemCount: _participants.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final participant = _participants[index];
                          final userId = (participant['user_id'] ??
                                  participant['id'] ??
                                  '')
                              .toString();
                          final fullName = (participant['full_name'] ??
                                  participant['name'] ??
                                  participant['username'] ??
                                  _extractNestedValue(participant, const [
                                    'profiles',
                                    'full_name',
                                  ]) ??
                                  _extractNestedValue(participant, const [
                                    'profile',
                                    'full_name',
                                  ]) ??
                                  _extractNestedValue(participant, const [
                                    'user',
                                    'full_name',
                                  ]) ??
                                  'Sem nome')
                              .toString();
                          final role =
                              (participant['role'] ?? 'member').toString();
                          final phone = (participant['phone'] ?? '').toString();
                          final isMuted =
                              participant['is_muted'] as bool? ?? false;
                          final isBanned =
                              participant['is_banned'] as bool? ?? false;
                          final isCreator = userId == _room.createdBy;
                          final isSelf = userId == _chatService.currentUserId;
                          String subtitle =
                              phone.isNotEmpty ? '$phone • $role' : role;
                          if (isMuted) subtitle += ' • silenciado';
                          if (isBanned) subtitle += ' • banido';
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(fullName),
                            subtitle: Text(subtitle),
                            trailing: canManageRoom && !isCreator && !isSelf
                                ? PopupMenuButton<String>(
                                    onSelected: loading
                                        ? null
                                        : (value) async {
                                            setDialogState(() {
                                              loading = true;
                                            });
                                            try {
                                              if (value == 'promote_admin') {
                                                await _chatService
                                                    .setParticipantRole(
                                                  roomId: _room.id,
                                                  userId: userId,
                                                  role: 'admin',
                                                );
                                              } else if (value ==
                                                  'remove_admin') {
                                                await _chatService
                                                    .setParticipantRole(
                                                  roomId: _room.id,
                                                  userId: userId,
                                                  role: 'member',
                                                );
                                              } else if (value == 'mute') {
                                                await _chatService
                                                    .setParticipantMuted(
                                                  roomId: _room.id,
                                                  userId: userId,
                                                  muted: true,
                                                );
                                              } else if (value == 'unmute') {
                                                await _chatService
                                                    .setParticipantMuted(
                                                  roomId: _room.id,
                                                  userId: userId,
                                                  muted: false,
                                                );
                                              } else if (value == 'ban') {
                                                await _chatService
                                                    .setParticipantBanned(
                                                  roomId: _room.id,
                                                  userId: userId,
                                                  banned: true,
                                                );
                                              } else if (value == 'unban') {
                                                await _chatService
                                                    .setParticipantBanned(
                                                  roomId: _room.id,
                                                  userId: userId,
                                                  banned: false,
                                                );
                                              } else if (value == 'remove') {
                                                await _chatService
                                                    .removeParticipantFromRoom(
                                                  roomId: _room.id,
                                                  userId: userId,
                                                );
                                              }
                                              await refreshDialog(
                                                setDialogState,
                                              );
                                            } catch (e) {
                                              if (!mounted) return;
                                              ScaffoldMessenger.of(context)
                                                  .showSnackBar(
                                                SnackBar(
                                                  content: Text(
                                                    'Erro ao atualizar participante: $e',
                                                  ),
                                                ),
                                              );
                                            } finally {
                                              setDialogState(() {
                                                loading = false;
                                              });
                                            }
                                          },
                                    itemBuilder: (context) => [
                                      if (role != 'admin')
                                        const PopupMenuItem(
                                          value: 'promote_admin',
                                          child: Text('Tornar admin'),
                                        ),
                                      if (role == 'admin')
                                        const PopupMenuItem(
                                          value: 'remove_admin',
                                          child: Text('Remover admin'),
                                        ),
                                      if (!isMuted)
                                        const PopupMenuItem(
                                          value: 'mute',
                                          child: Text('Silenciar'),
                                        ),
                                      if (isMuted)
                                        const PopupMenuItem(
                                          value: 'unmute',
                                          child: Text('Remover silêncio'),
                                        ),
                                      if (!isBanned)
                                        const PopupMenuItem(
                                          value: 'ban',
                                          child: Text('Banir'),
                                        ),
                                      if (isBanned)
                                        const PopupMenuItem(
                                          value: 'unban',
                                          child: Text('Desbanir'),
                                        ),
                                      const PopupMenuItem(
                                        value: 'remove',
                                        child: Text('Remover do grupo'),
                                      ),
                                    ],
                                  )
                                : role == 'admin'
                                    ? const Icon(
                                        Icons.shield,
                                        color: Colors.blue,
                                      )
                                    : null,
                          );
                        },
                      ),
              ),
              actions: [
                if (canManageRoom)
                  TextButton.icon(
                    onPressed: loading
                        ? null
                        : () async {
                            await _showAddParticipantsDialog();
                            await refreshDialog(setDialogState);
                          },
                    icon: const Icon(Icons.person_add),
                    label: const Text('Adicionar'),
                  ),
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Fechar'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _showAddParticipantsDialog() async {
    final users = await _chatService.getAvailableUsersForRoom(_room.id);
    final selectedUserIds = <String>{};
    if (!mounted) return;
    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        bool saving = false;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final media = MediaQuery.of(context);
            final size = media.size;
            final isMobile = size.width < 600;
            final maxDialogWidth = isMobile ? size.width : 420.0;
            final maxDialogHeight = size.height * (isMobile ? 0.88 : 0.76);
            return Dialog(
              insetPadding: EdgeInsets.symmetric(
                horizontal: isMobile ? 12 : 24,
                vertical: isMobile ? 16 : 24,
              ),
              backgroundColor: const Color(0xFFF1EEF4),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(26),
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: maxDialogWidth,
                  maxHeight: maxDialogHeight,
                ),
                child: SafeArea(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      isMobile ? 12 : 16,
                      12,
                      isMobile ? 12 : 16,
                      12,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(4, 2, 4, 12),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'Nova conversa',
                              style: TextStyle(
                                fontSize: isMobile ? 16 : 18,
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFF2D2A32),
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: users.isEmpty
                              ? const Center(
                                  child: Text(
                                    'Não há usuários disponíveis para adicionar.',
                                  ),
                                )
                              : ListView.separated(
                                  itemCount: users.length,
                                  padding: EdgeInsets.zero,
                                  separatorBuilder: (_, __) =>
                                      const SizedBox(height: 10),
                                  itemBuilder: (context, index) {
                                    final user = users[index];
                                    final userId =
                                        (user['id'] ?? '').toString();
                                    final fullName =
                                        (user['full_name'] ?? 'Sem nome')
                                            .toString();
                                    final phone =
                                        (user['phone'] ?? '').toString().trim();
                                    final userType = (user['user_type'] ?? '')
                                        .toString()
                                        .trim();
                                    final isSelected =
                                        selectedUserIds.contains(userId);
                                    String subtitle = '';
                                    if (phone.isNotEmpty &&
                                        userType.isNotEmpty) {
                                      subtitle = '$phone • $userType';
                                    } else if (phone.isNotEmpty) {
                                      subtitle = phone;
                                    } else {
                                      subtitle = userType;
                                    }
                                    final initial = fullName.trim().isNotEmpty
                                        ? fullName.trim()[0].toUpperCase()
                                        : 'U';
                                    return Material(
                                      color: Colors.transparent,
                                      child: InkWell(
                                        borderRadius: BorderRadius.circular(18),
                                        onTap: saving
                                            ? null
                                            : () {
                                                setDialogState(() {
                                                  if (isSelected) {
                                                    selectedUserIds.remove(
                                                      userId,
                                                    );
                                                  } else {
                                                    selectedUserIds.add(userId);
                                                  }
                                                });
                                              },
                                        child: AnimatedContainer(
                                          duration:
                                              const Duration(milliseconds: 180),
                                          padding: EdgeInsets.symmetric(
                                            horizontal: isMobile ? 12 : 14,
                                            vertical: isMobile ? 10 : 12,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.white,
                                            borderRadius:
                                                BorderRadius.circular(18),
                                            border: Border.all(
                                              color: isSelected
                                                  ? _gold
                                                  : const Color(0xFFE3DDE8),
                                              width: isSelected ? 1.4 : 1,
                                            ),
                                            boxShadow: [
                                              BoxShadow(
                                                color: Colors.black
                                                    .withValues(alpha: 0.04),
                                                blurRadius: 8,
                                                offset: const Offset(0, 2),
                                              ),
                                            ],
                                          ),
                                          child: Row(
                                            children: [
                                              Container(
                                                width: isMobile ? 46 : 50,
                                                height: isMobile ? 46 : 50,
                                                decoration: BoxDecoration(
                                                  shape: BoxShape.circle,
                                                  border: Border.all(
                                                    color: _gold,
                                                    width: 1.2,
                                                  ),
                                                  color: const Color(
                                                    0xFFF8F4EC,
                                                  ),
                                                ),
                                                alignment: Alignment.center,
                                                child: Text(
                                                  initial,
                                                  style: TextStyle(
                                                    fontSize:
                                                        isMobile ? 22 : 24,
                                                    fontWeight: FontWeight.w600,
                                                    color: _gold,
                                                  ),
                                                ),
                                              ),
                                              SizedBox(
                                                width: isMobile ? 12 : 14,
                                              ),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    Text(
                                                      fullName,
                                                      maxLines: 1,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      style: TextStyle(
                                                        fontSize:
                                                            isMobile ? 15 : 16,
                                                        fontWeight:
                                                            FontWeight.w700,
                                                        color: const Color(
                                                          0xFF35313A,
                                                        ),
                                                      ),
                                                    ),
                                                    if (subtitle
                                                        .isNotEmpty) ...[
                                                      const SizedBox(height: 2),
                                                      Text(
                                                        subtitle,
                                                        maxLines: 1,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                        style: TextStyle(
                                                          fontSize: isMobile
                                                              ? 12
                                                              : 13,
                                                          color: const Color(
                                                            0xFF7B7482,
                                                          ),
                                                          fontWeight:
                                                              FontWeight.w500,
                                                        ),
                                                      ),
                                                    ],
                                                  ],
                                                ),
                                              ),
                                              if (isSelected)
                                                const Padding(
                                                  padding:
                                                      EdgeInsets.only(left: 8),
                                                  child: Icon(
                                                    Icons.check_circle,
                                                    color: _gold,
                                                    size: 22,
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(top: 14),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              TextButton(
                                onPressed: saving
                                    ? null
                                    : () => Navigator.of(dialogContext).pop(),
                                style: TextButton.styleFrom(
                                  foregroundColor: const Color(0xFF6E55B5),
                                  textStyle: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                child: const Text('Cancelar'),
                              ),
                              const SizedBox(width: 8),
                              ElevatedButton(
                                onPressed: saving || selectedUserIds.isEmpty
                                    ? null
                                    : () async {
                                        final messenger =
                                            ScaffoldMessenger.of(context);
                                        setDialogState(() {
                                          saving = true;
                                        });
                                        try {
                                          await _chatService
                                              .addParticipantsToRoom(
                                            roomId: _room.id,
                                            userIds: selectedUserIds.toList(),
                                          );
                                          if (!mounted) return;
                                          Navigator.of(dialogContext).pop();
                                          await _loadParticipantsForAvatars();
                                        } catch (e) {
                                          if (!mounted) return;
                                          messenger.showSnackBar(
                                            SnackBar(
                                              content: Text(
                                                'Erro ao adicionar: $e',
                                              ),
                                            ),
                                          );
                                          setDialogState(() {
                                            saving = false;
                                          });
                                        }
                                      },
                                style: ElevatedButton.styleFrom(
                                  elevation: 0,
                                  backgroundColor: const Color(0xFFE0DBE5),
                                  foregroundColor: const Color(0xFF8C8693),
                                  disabledBackgroundColor:
                                      const Color(0xFFE0DBE5),
                                  disabledForegroundColor:
                                      const Color(0xFF8C8693),
                                  minimumSize: Size(
                                    isMobile ? 92 : 100,
                                    44,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(22),
                                  ),
                                ),
                                child: saving
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Text('Criar'),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  String _timeText(DateTime dateTime) {
    return DateFormat('HH:mm').format(dateTime.toLocal());
  }

  String _lastSeenText(DateTime? dateTime) {
    if (dateTime == null) return 'offline';
    final local = dateTime.toLocal();
    return 'visto ${DateFormat('HH:mm').format(local)}';
  }

  String _buildPresenceSubtitle(
    List<Map<String, dynamic>> presenceRows,
    List<Map<String, dynamic>> typingRows,
  ) {
    final currentUserId = _chatService.currentUserId;
    final activeTyping = typingRows.where((row) {
      final userId = (row['user_id'] ?? '').toString();
      final isTyping = row['is_typing'] as bool? ?? false;
      return userId.isNotEmpty && userId != currentUserId && isTyping;
    }).toList();
    if (activeTyping.isNotEmpty) {
      final typingNames = activeTyping.map((row) {
        final userId = (row['user_id'] ?? '').toString();
        return _participantNames[userId] ?? 'Alguém';
      }).toList();
      if (_room.type == 'group') {
        return typingNames.length == 1
            ? '${typingNames.first} está digitando...'
            : 'Alguém está digitando...';
      }
      return '${typingNames.first} está digitando...';
    }
    final otherParticipantIds = _participants
        .map((e) => (e['user_id'] ?? '').toString())
        .where((id) => id.isNotEmpty && id != currentUserId)
        .toList();
    if (_room.type == 'group') {
      if (otherParticipantIds.isEmpty) return 'offline';
      final presenceMap = <String, Map<String, dynamic>>{
        for (final row in presenceRows) (row['user_id'] ?? '').toString(): row,
      };
      final onlineCount = otherParticipantIds.where((id) {
        final row = presenceMap[id];
        return row != null && (row['is_online'] as bool? ?? false);
      }).length;
      if (onlineCount > 0) {
        return onlineCount == 1 ? '1 online' : '$onlineCount online';
      }
      return 'offline';
    }
    if (otherParticipantIds.isEmpty) return 'offline';
    final presenceMap = <String, Map<String, dynamic>>{
      for (final row in presenceRows) (row['user_id'] ?? '').toString(): row,
    };
    final otherId = otherParticipantIds.first;
    final otherPresence = presenceMap[otherId];
    if (otherPresence == null) return 'offline';
    final isOnline = otherPresence['is_online'] as bool? ?? false;
    if (isOnline) return 'online';
    final lastSeenRaw = otherPresence['last_seen']?.toString();
    final lastSeen = lastSeenRaw != null && lastSeenRaw.isNotEmpty
        ? DateTime.tryParse(lastSeenRaw)
        : null;
    return _lastSeenText(lastSeen);
  }

  Widget _buildStatusBanner(String text) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(14, 10, 14, 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: _gold.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _gold.withValues(alpha: 0.5)),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: _goldSoft,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildParticipantAvatar(ChatMessage msg) {
    final photoUrl = _participantPhotoUrls[msg.senderId];
    final displayName =
        _participantNames[msg.senderId] ?? msg.senderName?.trim() ?? 'U';
    final initial = displayName.isNotEmpty ? displayName[0].toUpperCase() : 'U';
    return Container(
      width: 34,
      height: 34,
      margin: const EdgeInsets.only(right: 8, bottom: 2),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: _gold.withValues(alpha: 0.65), width: 1.2),
        color: Colors.white.withValues(alpha: 0.08),
      ),
      child: ClipOval(
        child: photoUrl != null && photoUrl.isNotEmpty
            ? Image.network(
                photoUrl,
                fit: BoxFit.cover,
                gaplessPlayback: true,
                loadingBuilder: (context, child, progress) {
                  if (progress == null) return child;
                  return Center(
                    child: Text(
                      initial,
                      style: const TextStyle(
                        color: _goldSoft,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  );
                },
                errorBuilder: (_, __, ___) {
                  return Center(
                    child: Text(
                      initial,
                      style: const TextStyle(
                        color: _goldSoft,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  );
                },
              )
            : Center(
                child: Text(
                  initial,
                  style: const TextStyle(
                    color: _goldSoft,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
      ),
    );
  }

  Widget _buildMessageBubble({
    required ChatMessage msg,
    required bool isMine,
  }) {
    final bubbleColor =
        isMine ? const Color(0x26D4B06A) : Colors.white.withValues(alpha: 0.08);
    final bubbleBorderColor = isMine
        ? _gold.withValues(alpha: 0.55)
        : Colors.white.withValues(alpha: 0.12);
    final senderDisplayName =
        _participantNames[msg.senderId] ?? msg.senderName?.trim() ?? '';
    final bubble = Container(
      margin: const EdgeInsets.symmetric(vertical: 5),
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width * 0.76,
      ),
      decoration: BoxDecoration(
        color: bubbleColor,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(18),
          topRight: const Radius.circular(18),
          bottomLeft: Radius.circular(isMine ? 18 : 6),
          bottomRight: Radius.circular(isMine ? 6 : 18),
        ),
        border: Border.all(color: bubbleBorderColor, width: 1),
        boxShadow: [
          BoxShadow(
            color: isMine ? const Color(0x22D4B06A) : const Color(0x12000000),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!isMine && senderDisplayName.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  senderDisplayName,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: _goldSoft,
                  ),
                ),
              ),
            Text(
              msg.content ?? '',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                height: 1.25,
              ),
            ),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.bottomRight,
              child: Text(
                _timeText(msg.createdAt),
                style: TextStyle(
                  fontSize: 11.5,
                  color: isMine ? _goldSoft : Colors.white70,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
    if (isMine) {
      return Align(
        alignment: Alignment.centerRight,
        child: bubble,
      );
    }
    return Align(
      alignment: Alignment.centerLeft,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildParticipantAvatar(msg),
          Flexible(child: bubble),
        ],
      ),
    );
  }

  Widget _buildComposer(bool canSend) {
    if (!canSend) return const SizedBox.shrink();
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        decoration: BoxDecoration(
          color: _navyDark.withValues(alpha: 0.75),
          border: Border(
            top: BorderSide(
              color: _gold.withValues(alpha: 0.18),
            ),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: _gold.withValues(alpha: 0.35),
                  ),
                ),
                child: TextField(
                  controller: _controller,
                  minLines: 1,
                  maxLines: 4,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Digite uma mensagem',
                    hintStyle: TextStyle(
                      color: Colors.white.withValues(alpha: 0.65),
                    ),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 14,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _gold,
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x44D4B06A),
                    blurRadius: 12,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: IconButton(
                onPressed: _sending ? null : _send,
                icon: _sending
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: _navy,
                        ),
                      )
                    : const Icon(
                        Icons.send_rounded,
                        color: _navy,
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = _chatService.currentUserId;
    final canManageRoom = currentUserId == _room.createdBy;
    final isRoomAdmin = _myRole == 'admin';
    final canSend = !_room.isLocked &&
        _room.allowMessages &&
        (!_room.adminOnly || isRoomAdmin);

    // ✅ CORREÇÃO: Usa os novos métodos para obter avatar e nome corretos
    final headerPhotoUrl = _getHeaderAvatarUrl();
    final headerDisplayName = _getHeaderDisplayName();

    final otherParticipantIds = _participants
        .map((e) => (e['user_id'] ?? '').toString())
        .where((id) => id.isNotEmpty && id != currentUserId)
        .toList();
    return Scaffold(
      backgroundColor: _navy,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.white,
        title: StreamBuilder<List<Map<String, dynamic>>>(
          stream: _chatService.streamUsersPresence(otherParticipantIds),
          builder: (context, presenceSnapshot) {
            return StreamBuilder<List<Map<String, dynamic>>>(
              stream: _chatService.streamTypingStatus(_room.id),
              builder: (context, typingSnapshot) {
                final subtitle = _buildPresenceSubtitle(
                  presenceSnapshot.data ?? const [],
                  typingSnapshot.data ?? const [],
                );
                return Row(
                  children: [
                    CircleAvatar(
                      radius: 16,
                      backgroundColor: Colors.white.withValues(alpha: 0.08),
                      backgroundImage: headerPhotoUrl != null
                          ? NetworkImage(headerPhotoUrl)
                          : null,
                      child: headerPhotoUrl == null
                          ? Text(
                              (headerDisplayName.trim().isNotEmpty
                                      ? headerDisplayName.trim()[0]
                                      : 'C')
                                  .toUpperCase(),
                              style: const TextStyle(
                                color: _goldSoft,
                                fontWeight: FontWeight.w700,
                              ),
                            )
                          : null,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            headerDisplayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if (subtitle.isNotEmpty)
                            Text(
                              subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: _goldSoft,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            );
          },
        ),
        actions: [
          IconButton(
            onPressed: _showParticipantsDialog,
            tooltip: 'Participantes',
            icon: const Icon(Icons.group, color: _gold),
          ),
          if (isRoomAdmin)
            IconButton(
              onPressed: _showEditGroupDialog,
              tooltip: 'Editar grupo',
              icon: const Icon(Icons.edit, color: _gold),
            ),
          if (canManageRoom)
            IconButton(
              onPressed: _updatingRoom ? null : _toggleAdminOnly,
              tooltip: _room.adminOnly
                  ? 'Permitir todos enviarem'
                  : 'Somente admin envia',
              icon: _updatingRoom
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: _gold,
                      ),
                    )
                  : Icon(
                      _room.adminOnly ? Icons.campaign : Icons.group_work,
                      color: _gold,
                    ),
            ),
          if (canManageRoom)
            IconButton(
              onPressed: _updatingRoom ? null : _toggleRoomLock,
              tooltip: _room.isLocked ? 'Desbloquear grupo' : 'Bloquear grupo',
              icon: _updatingRoom
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: _gold,
                      ),
                    )
                  : Icon(
                      _room.isLocked ? Icons.lock_open : Icons.lock,
                      color: _gold,
                    ),
            ),
        ],
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    _navy,
                    _navyDark,
                  ],
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: Center(
              child: Opacity(
                opacity: 0.08,
                child: Image.asset(
                  'assets/images/olympus_logo.png',
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _ChatLensPainter(gold: _gold),
              ),
            ),
          ),
          Column(
            children: [
              if (_room.isLocked)
                _buildStatusBanner(
                  'Este chat está bloqueado para envio de mensagens.',
                )
              else if (_room.adminOnly && !isRoomAdmin)
                _buildStatusBanner(
                  'Somente administradores podem enviar mensagens neste grupo.',
                ),
              Expanded(
                child: StreamBuilder<List<ChatMessage>>(
                  stream: _chatService.streamMessages(_room.id),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return const Center(
                        child: CircularProgressIndicator(color: _gold),
                      );
                    }
                    final messages = [...snapshot.data!]
                      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
                    if (messages.isNotEmpty) {
                      final lastMessageId = messages.last.id;
                      if (_lastMarkedMessageId != lastMessageId) {
                        _lastMarkedMessageId = lastMessageId;
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          _markAsRead();
                          if (_scrollController.hasClients) {
                            _scrollController.jumpTo(
                              _scrollController.position.maxScrollExtent,
                            );
                          }
                        });
                      }
                    }
                    if (messages.isEmpty) {
                      return const Center(
                        child: Text(
                          'Nenhuma mensagem ainda',
                          style: TextStyle(color: Colors.white70),
                        ),
                      );
                    }
                    return ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                      itemCount: messages.length,
                      itemBuilder: (context, index) {
                        final msg = messages[index];
                        final isMine = msg.senderId == currentUserId;
                        return _buildMessageBubble(
                          msg: msg,
                          isMine: isMine,
                        );
                      },
                    );
                  },
                ),
              ),
              _buildComposer(canSend),
            ],
          ),
        ],
      ),
    );
  }
}

class _ChatLensPainter extends CustomPainter {
  final Color gold;
  const _ChatLensPainter({required this.gold});

  @override
  void paint(Canvas canvas, Size size) {
    _drawLeftLightLeak(canvas, size);
    _drawTopGlow(canvas, size);
  }

  void _drawLeftLightLeak(Canvas canvas, Size size) {
    final Rect pillRect = Rect.fromLTWH(14, 86, 18, size.height * 0.55);
    final RRect pill =
        RRect.fromRectAndRadius(pillRect, const Radius.circular(12));
    final Paint pillPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color(0xFF183A72),
          Color(0xFF264A7A),
          Color(0xFF16325F),
        ],
      ).createShader(pillRect);
    canvas.drawRRect(pill, pillPaint);
    final Rect innerGlowRect = Rect.fromLTWH(20, 110, 10, size.height * 0.46);
    final Paint innerGlow = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.transparent,
          Color(0x33FFD978),
          Color(0x88FFE29A),
          Color(0x33FFD978),
          Colors.transparent,
        ],
        stops: [0.0, 0.32, 0.5, 0.68, 1.0],
      ).createShader(innerGlowRect)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7);
    canvas.drawRRect(
      RRect.fromRectAndRadius(innerGlowRect, const Radius.circular(10)),
      innerGlow,
    );
    final Offset flareCenter = Offset(19, size.height * 0.40);
    final Rect flareRect =
        Rect.fromCenter(center: flareCenter, width: 70, height: 110);
    final Paint flareGlow = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFFFFF2C7).withValues(alpha: 0.9),
          const Color(0xFFFFD978).withValues(alpha: 0.55),
          const Color(0x44FFD978).withValues(alpha: 0.18),
          Colors.transparent,
        ],
      ).createShader(flareRect)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
    canvas.drawOval(flareRect, flareGlow);
    final Paint flareLine = Paint()
      ..shader = const LinearGradient(
        colors: [
          Colors.transparent,
          Color(0xAAFFD978),
          Color(0xFFFFE7A8),
          Color(0xAAFFD978),
          Colors.transparent,
        ],
      ).createShader(
        Rect.fromCenter(center: flareCenter, width: 90, height: 4),
      )
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: flareCenter, width: 90, height: 3.5),
        const Radius.circular(3),
      ),
      flareLine,
    );
    final Paint core = Paint()..color = const Color(0xFFFFE6A6);
    canvas.drawCircle(flareCenter, 2.8, core);
  }

  void _drawTopGlow(Canvas canvas, Size size) {
    final Rect topBand = Rect.fromLTWH(0, 0, size.width, 76);
    final Paint topPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.black.withValues(alpha: 0.22),
          Colors.transparent,
        ],
      ).createShader(topBand);
    canvas.drawRect(topBand, topPaint);
    final Paint smallParticles = Paint()
      ..color = const Color(0x66FFE29A)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
    final particles = <Offset>[
      Offset(size.width * 0.07, 26),
      Offset(size.width * 0.11, 18),
      Offset(size.width * 0.15, 30),
    ];
    for (final p in particles) {
      canvas.drawCircle(p, 1.4, smallParticles);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
