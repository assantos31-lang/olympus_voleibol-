import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/chat_service.dart';
import 'chat_page.dart';

class ChatRoomsPage extends StatefulWidget {
  final String? initialRoomId;

  const ChatRoomsPage({super.key, this.initialRoomId});

  @override
  State<ChatRoomsPage> createState() => _ChatRoomsPageState();
}

class _ChatRoomsPageState extends State<ChatRoomsPage> {
  final ChatService _chatService = ChatService();
  final TextEditingController _searchController = TextEditingController();
  final ImagePicker _imagePicker = ImagePicker();

  late Future<List<ChatRoomListItem>> _futureRooms;
  late Stream<List<ChatRoomListItem>> _roomsStream;
  bool _isAdmin = false;
  String _searchQuery = '';
  bool _openedInitialRoom = false;
  bool _openedPendingPollRoom = false;
  final Set<String> _pinnedRoomIds = <String>{};

  static const Color _gold = Color(0xFFD4B06A);
  static const Color _navy = Color(0xFF0E2A57);
  static const Color _navyDark = Color(0xFF0A1730);

  @override
  void initState() {
    super.initState();
    _futureRooms = _chatService.getMyRoomListItems();
    _roomsStream = _chatService.streamMyRoomListItems();
    _loadIsAdmin();
    _loadPinnedRooms();
    _openInitialRoomIfNeeded();
    _openPendingPollRoomIfNeeded();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    final value = _searchController.text.trim();
    if (value == _searchQuery) return;
    setState(() {
      _searchQuery = value;
    });
  }

  Future<void> _loadIsAdmin() async {
    try {
      final isAdmin = await _chatService.isCurrentUserAdmin();
      if (!mounted) return;
      setState(() {
        _isAdmin = isAdmin;
      });
    } catch (_) {}
  }

  Future<void> _reload() async {
    setState(() {
      _futureRooms = _chatService.getMyRoomListItems();
      _roomsStream = _chatService.streamMyRoomListItems();
    });
  }

  Future<void> _openInitialRoomIfNeeded() async {
    if (_openedInitialRoom) return;
    final roomId = widget.initialRoomId?.trim();
    if (roomId == null || roomId.isEmpty) return;

    _openedInitialRoom = true;
    await Future<void>.delayed(const Duration(milliseconds: 350));

    try {
      final room = await _chatService.getRoomById(roomId);
      if (!mounted || room == null) return;

      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => ChatPage(room: room)),
      );

      if (!mounted) return;
      await _reload();
    } catch (_) {}
  }

  Future<void> _showCreateConversationDialog() async {
    List<Map<String, dynamic>> users = [];
    String? selectedUserId;
    String? selectedUserName;

    try {
      users = await _chatService.getSelectableUsers();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao carregar usuários: $e')),
      );
      return;
    }

    if (!mounted) return;

    await showDialog(
      context: context,
      builder: (dialogContext) {
        bool isSaving = false;

        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFFF2EEF5),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
              contentPadding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              actionsPadding: const EdgeInsets.fromLTRB(12, 8, 12, 14),
              title: const Text(
                'Nova conversa',
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                ),
              ),
              content: SizedBox(
                width: double.maxFinite,
                child: users.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Text('Nenhum usuário disponível'),
                      )
                    : ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 380),
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: users.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            final user = users[index];
                            final userId = (user['id'] ?? '').toString();
                            final fullName = (user['display_name'] ??
                                    user['full_name'] ??
                                    'Sem nome')
                                .toString();
                            final photoUrl = _resolveAvatarUrl(
                              (user['avatar_url'] ?? '').toString(),
                            );
                            final isSelected = selectedUserId == userId;
                            const phone = '';
                            const userType = '';

                            String subtitle = '';
                            if (phone.isNotEmpty && userType.isNotEmpty) {
                              subtitle = '$phone • $userType';
                            } else if (phone.isNotEmpty) {
                              subtitle = phone;
                            } else {
                              subtitle = userType;
                            }

                            return Material(
                              color: Colors.transparent,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(18),
                                onTap: isSaving
                                    ? null
                                    : () {
                                        setDialogState(() {
                                          selectedUserId = userId;
                                          selectedUserName = fullName;
                                        });
                                      },
                                child: Ink(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(18),
                                    color: isSelected
                                        ? _gold.withValues(alpha: 0.16)
                                        : Colors.white.withValues(alpha: 0.75),
                                    border: Border.all(
                                      color: isSelected
                                          ? _gold
                                          : Colors.black
                                              .withValues(alpha: 0.08),
                                      width: isSelected ? 1.6 : 1,
                                    ),
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 12,
                                    ),
                                    child: Row(
                                      children: [
                                        _buildUserAvatar(
                                          fullName: fullName,
                                          photoUrl: photoUrl,
                                          size: 52,
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                fullName,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  fontSize: 17,
                                                  fontWeight: FontWeight.w600,
                                                  color: Color(0xFF2F2A35),
                                                ),
                                              ),
                                              if (subtitle.isNotEmpty) ...[
                                                const SizedBox(height: 4),
                                                Text(
                                                  subtitle,
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: TextStyle(
                                                    fontSize: 13,
                                                    color: Colors.black
                                                        .withValues(
                                                            alpha: 0.55),
                                                    fontWeight: FontWeight.w500,
                                                  ),
                                                ),
                                              ],
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
                        ),
                      ),
              ),
              actions: [
                TextButton(
                  onPressed:
                      isSaving ? null : () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancelar'),
                ),
                ElevatedButton(
                  onPressed: isSaving || selectedUserId == null
                      ? null
                      : () async {
                          setDialogState(() {
                            isSaving = true;
                          });

                          try {
                            final room = await _chatService.createDirectRoom(
                              otherUserId: selectedUserId!,
                              otherUserName: selectedUserName,
                            );

                            if (!mounted) return;
                            Navigator.of(dialogContext).pop();

                            await _reload();

                            if (!mounted) return;
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => ChatPage(room: room),
                              ),
                            );

                            if (!mounted) return;
                            await _reload();
                          } catch (e) {
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Erro ao criar conversa: $e'),
                              ),
                            );
                            setDialogState(() {
                              isSaving = false;
                            });
                          }
                        },
                  child: isSaving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Criar'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _showCreateGroupDialog() async {
    final nameController = TextEditingController();
    List<Map<String, dynamic>> users = [];
    final Set<String> selectedUserIds = {};
    File? selectedImage;

    try {
      users = await _chatService.getSelectableUsers();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao carregar usuários: $e')),
      );
      return;
    }

    if (!mounted) return;

    await showDialog(
      context: context,
      builder: (dialogContext) {
        bool isSaving = false;

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
            return AlertDialog(
              backgroundColor: const Color(0xFFF7F4EC),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(28),
              ),
              titlePadding: const EdgeInsets.fromLTRB(22, 20, 22, 8),
              contentPadding: const EdgeInsets.fromLTRB(18, 4, 18, 0),
              actionsPadding: const EdgeInsets.fromLTRB(18, 8, 18, 16),
              title: const Row(
                children: [
                  CircleAvatar(
                    backgroundColor: _navy,
                    child: Icon(Icons.groups_rounded, color: _gold),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Criar grupo',
                      style: TextStyle(
                        color: _navy,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: double.maxFinite,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      GestureDetector(
                        onTap:
                            isSaving ? null : () => pickImage(setDialogState),
                        child: Container(
                          width: 84,
                          height: 84,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _gold.withValues(alpha: 0.18),
                            border: Border.all(
                              color: _gold.withValues(alpha: 0.55),
                              width: 1.2,
                            ),
                          ),
                          child: CircleAvatar(
                            radius: 40,
                            backgroundColor: Colors.transparent,
                            backgroundImage: selectedImage != null
                                ? FileImage(selectedImage!)
                                : null,
                            child: selectedImage == null
                                ? const Icon(
                                    Icons.add_a_photo_rounded,
                                    color: _navy,
                                  )
                                : null,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: nameController,
                        decoration: InputDecoration(
                          labelText: 'Nome do grupo',
                          filled: true,
                          fillColor: Colors.white,
                          prefixIcon: const Icon(Icons.edit_rounded),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(18),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          selectedUserIds.isEmpty
                              ? 'Selecionar participantes'
                              : '${selectedUserIds.length} participante(s) selecionado(s)',
                          style: const TextStyle(
                            color: _navy,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (users.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: Text('Nenhum usuário disponível'),
                        )
                      else
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 320),
                          child: ListView.builder(
                            shrinkWrap: true,
                            itemCount: users.length,
                            itemBuilder: (context, index) {
                              final user = users[index];
                              final userId = (user['id'] ?? '').toString();
                              final fullName = (user['display_name'] ??
                                      user['full_name'] ??
                                      'Sem nome')
                                  .toString();
                              const phone = '';
                              const userTypeLabel = '';

                              String subtitle = '';
                              if (phone.isNotEmpty &&
                                  userTypeLabel.isNotEmpty) {
                                subtitle = '$phone • $userTypeLabel';
                              } else if (phone.isNotEmpty) {
                                subtitle = phone;
                              } else {
                                subtitle = userTypeLabel;
                              }

                              final checked = selectedUserIds.contains(userId);

                              return Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(16),
                                  onTap: isSaving
                                      ? null
                                      : () {
                                          setDialogState(() {
                                            if (checked) {
                                              selectedUserIds.remove(userId);
                                            } else {
                                              selectedUserIds.add(userId);
                                            }
                                          });
                                        },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 9,
                                    ),
                                    decoration: BoxDecoration(
                                      color: checked
                                          ? _gold.withValues(alpha: 0.22)
                                          : Colors.white,
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(
                                        color: checked ? _gold : Colors.black12,
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        Checkbox(
                                          value: checked,
                                          activeColor: _navy,
                                          onChanged: isSaving
                                              ? null
                                              : (value) {
                                                  setDialogState(() {
                                                    if (value == true) {
                                                      selectedUserIds
                                                          .add(userId);
                                                    } else {
                                                      selectedUserIds
                                                          .remove(userId);
                                                    }
                                                  });
                                                },
                                        ),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                fullName,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  color: _navy,
                                                  fontWeight: FontWeight.w800,
                                                ),
                                              ),
                                              if (subtitle.isNotEmpty)
                                                Text(
                                                  subtitle,
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: TextStyle(
                                                    color: _navy.withValues(
                                                      alpha: 0.62,
                                                    ),
                                                    fontSize: 12,
                                                  ),
                                                ),
                                            ],
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
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed:
                      isSaving ? null : () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancelar'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _gold,
                    foregroundColor: _navy,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  onPressed: isSaving
                      ? null
                      : () async {
                          final groupName = nameController.text.trim();

                          if (groupName.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Informe um nome para o grupo'),
                              ),
                            );
                            return;
                          }

                          if (selectedUserIds.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Selecione pelo menos um participante',
                                ),
                              ),
                            );
                            return;
                          }

                          setDialogState(() {
                            isSaving = true;
                          });

                          try {
                            String? avatarPath;
                            if (selectedImage != null) {
                              avatarPath = await _chatService.uploadRoomAvatar(
                                roomId:
                                    'grupo_${DateTime.now().millisecondsSinceEpoch}',
                                file: selectedImage!,
                              );
                            }

                            final room = await _chatService.createGroupRoom(
                              name: groupName,
                              participantUserIds: selectedUserIds.toList(),
                              avatarUrl: avatarPath,
                            );

                            if (!mounted) return;
                            Navigator.of(dialogContext).pop();

                            await _reload();

                            if (!mounted) return;
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => ChatPage(room: room),
                              ),
                            );

                            if (!mounted) return;
                            await _reload();
                          } catch (e) {
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Erro ao criar grupo: $e'),
                              ),
                            );
                            setDialogState(() {
                              isSaving = false;
                            });
                          }
                        },
                  child: isSaving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Criar grupo'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  String? _resolveAvatarUrl(String? rawValue) {
    final value = rawValue?.trim();
    if (value == null || value.isEmpty) return null;

    if (value.startsWith('http://') || value.startsWith('https://')) {
      return value;
    }

    return _chatService.supabase.storage.from('avatars').getPublicUrl(value);
  }

  Widget _buildUserAvatar({
    required String fullName,
    String? photoUrl,
    double size = 50,
  }) {
    final initial =
        fullName.trim().isNotEmpty ? fullName.trim()[0].toUpperCase() : 'U';

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: _gold, width: 1.6),
        color: Colors.white.withValues(alpha: 0.08),
      ),
      child: ClipOval(
        child: photoUrl != null && photoUrl.isNotEmpty
            ? Image.network(
                photoUrl,
                fit: BoxFit.cover,
                gaplessPlayback: true,
                errorBuilder: (_, __, ___) => Center(
                  child: Text(
                    initial,
                    style: const TextStyle(
                      color: _gold,
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              )
            : Center(
                child: Text(
                  initial,
                  style: const TextStyle(
                    color: _gold,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
      ),
    );
  }

  String? _extractRoomPhoto(ChatRoomListItem item) {
    return _resolveAvatarUrl(item.avatarUrl);
  }

  String _buildRoomSubtitle(ChatRoomListItem item) {
    final room = item.room;

    if (item.lastMessageText != null &&
        item.lastMessageText!.trim().isNotEmpty) {
      final senderName = item.lastMessageSenderName?.trim();
      if (senderName != null && senderName.isNotEmpty) {
        return '$senderName: ${item.lastMessageText!}';
      }
      return item.lastMessageText!;
    }

    if (room.isLocked) return 'Bloqueado';
    if (room.adminOnly) return 'Somente admin envia';
    return room.type == 'group' ? 'Grupo' : 'Conversa';
  }

  String get _pinnedRoomsKey {
    final userId = _chatService.currentUserId ?? 'anon';
    return 'olympus_pinned_chat_rooms_$userId';
  }

  Future<void> _loadPinnedRooms() async {
    final prefs = await SharedPreferences.getInstance();
    final ids = prefs.getStringList(_pinnedRoomsKey) ?? const <String>[];
    if (!mounted) return;
    setState(() {
      _pinnedRoomIds
        ..clear()
        ..addAll(ids.take(2));
    });
  }

  Future<void> _savePinnedRooms() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_pinnedRoomsKey, _pinnedRoomIds.take(2).toList());
  }

  Future<void> _togglePinnedRoom(ChatRoomListItem item) async {
    final roomId = item.room.id;
    final isPinned = _pinnedRoomIds.contains(roomId);

    if (!isPinned && _pinnedRoomIds.length >= 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Você pode fixar até 2 conversas no topo.'),
        ),
      );
      return;
    }

    setState(() {
      if (isPinned) {
        _pinnedRoomIds.remove(roomId);
      } else {
        _pinnedRoomIds.add(roomId);
      }
    });

    await _savePinnedRooms();
  }

  Future<void> _hideRoomForMe(ChatRoomListItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: const Text('Apagar conversa'),
        content: const Text(
          'A conversa será apagada apenas para você. A outra pessoa continua '
          'com a conversa normalmente. Se ela mandar uma nova mensagem, você '
          'recebe a notificação e a conversa aparece de novo.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _gold,
              foregroundColor: _navy,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Apagar para mim'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await _chatService.deleteRoomForCurrentUser(item.room.id);
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Conversa apagada para você.')),
      );
      await _reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao apagar conversa: $e')),
      );
    }
  }

  Future<void> _openPendingPollRoomIfNeeded() async {
    if (_openedPendingPollRoom || widget.initialRoomId != null) return;
    _openedPendingPollRoom = true;

    await Future<void>.delayed(const Duration(milliseconds: 700));
    if (!mounted) return;

    try {
      final rooms = await _chatService.getMyRoomListItems();
      for (final item in rooms) {
        if (item.room.type != 'group') continue;
        final pendingPolls =
            await _chatService.getPendingPollsForRoom(item.room.id);
        if (pendingPolls.isEmpty) continue;

        if (!mounted) return;
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => ChatPage(room: item.room)),
        );
        if (!mounted) return;
        await _reload();
        return;
      }
    } catch (_) {}
  }

  String _translatedUserType(String value) {
    switch (value.toLowerCase().trim()) {
      case 'admin':
        return 'Administrador';
      case 'coach':
        return 'Técnico';
      case 'athlete':
        return 'Atleta';
      case 'member':
        return 'Membro';
      default:
        return value;
    }
  }

  String _formatLastMessageTime(DateTime? dateTime) {
    if (dateTime == null) return '';
    final local = dateTime.toLocal();
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  Widget? _buildTrailing(ChatRoomListItem item) {
    final room = item.room;

    if (item.unreadCount > 0) {
      return Container(
        constraints: const BoxConstraints(minWidth: 46, minHeight: 30),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: _gold,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          item.unreadCount > 99 ? '99+' : item.unreadCount.toString(),
          style: const TextStyle(
            color: _navyDark,
            fontWeight: FontWeight.w800,
            fontSize: 13,
          ),
        ),
      );
    }

    if (room.isLocked) {
      return const Icon(Icons.lock_outline_rounded, color: _gold, size: 22);
    }

    if (room.adminOnly) {
      return const Icon(Icons.campaign_outlined, color: _gold, size: 22);
    }

    return null;
  }

  Widget _buildAvatar(ChatRoomListItem item) {
    final name = (item.room.name ?? 'C').trim();
    final photoUrl = _extractRoomPhoto(item);

    return _buildUserAvatar(
      fullName: name.isNotEmpty ? name : 'C',
      photoUrl: photoUrl,
      size: 58,
    );
  }

  Widget _buildCenterRoomIcon(ChatRoomListItem item, int index) {
    if (item.room.adminOnly) {
      return const Icon(Icons.shield_outlined, color: _gold, size: 36);
    }
    if (item.room.isLocked) {
      return const Icon(Icons.lock_outline_rounded, color: _gold, size: 34);
    }
    if (index.isOdd) {
      return const Icon(
        Icons.volunteer_activism_outlined,
        color: _gold,
        size: 36,
      );
    }
    return const Icon(Icons.sports_volleyball_outlined, color: _gold, size: 40);
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _gold.withValues(alpha: 0.35), width: 1.1),
          color: Colors.white.withValues(alpha: 0.06),
        ),
        child: TextField(
          controller: _searchController,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Pesquisar conversas',
            hintStyle: TextStyle(
              color: Colors.white.withValues(alpha: 0.65),
            ),
            prefixIcon: const Icon(Icons.search, color: _gold),
            suffixIcon: _searchQuery.isNotEmpty
                ? IconButton(
                    onPressed: () {
                      _searchController.clear();
                    },
                    icon: const Icon(Icons.close_rounded, color: _gold),
                  )
                : null,
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 14,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRoomTile(ChatRoomListItem item, int index) {
    final room = item.room;
    final subtitle = _buildRoomSubtitle(item);
    final trailingWidget = _buildTrailing(item);
    final isPinned = _pinnedRoomIds.contains(room.id);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () async {
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ChatPage(room: room),
              ),
            );

            if (!mounted) return;
            await _reload();
          },
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.22),
                width: 1,
              ),
              color: Colors.white.withValues(alpha: 0.92),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.16),
                  blurRadius: 18,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Stack(
              children: [
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  child: Row(
                    children: [
                      _buildAvatar(item),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              room.name ?? 'Chat',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: _navy,
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            if (isPinned) ...[
                              const SizedBox(height: 4),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: const [
                                  Icon(
                                    Icons.push_pin_rounded,
                                    size: 13,
                                    color: _gold,
                                  ),
                                  SizedBox(width: 4),
                                  Text(
                                    'Fixado',
                                    style: TextStyle(
                                      color: _gold,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                            const SizedBox(height: 4),
                            Text(
                              subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: _navy.withValues(alpha: 0.64),
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              _formatLastMessageTime(item.lastMessageAt),
                              style: TextStyle(
                                color: _navy.withValues(alpha: 0.62),
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          if (trailingWidget != null)
                            trailingWidget
                          else
                            const SizedBox(height: 30),
                        ],
                      ),
                      PopupMenuButton<String>(
                        onSelected: (value) async {
                          if (value == 'pin') {
                            await _togglePinnedRoom(item);
                          } else if (value == 'hide') {
                            await _hideRoomForMe(item);
                          }
                        },
                        itemBuilder: (context) => [
                          PopupMenuItem<String>(
                            value: 'pin',
                            child: Text(
                              isPinned
                                  ? 'Desafixar conversa'
                                  : 'Fixar conversa',
                            ),
                          ),
                          const PopupMenuItem<String>(
                            value: 'hide',
                            child: Text('Apagar conversa'),
                          ),
                        ],
                        icon: const Icon(
                          Icons.more_vert,
                          color: _navy,
                        ),
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
  }

  List<ChatRoomListItem> _filterRooms(List<ChatRoomListItem> rooms) {
    final query = _searchQuery.trim().toLowerCase();
    final filtered = query.isEmpty
        ? List<ChatRoomListItem>.from(rooms)
        : rooms.where((item) {
            final roomName = (item.room.name ?? '').toLowerCase();
            final subtitle = _buildRoomSubtitle(item).toLowerCase();
            final sender = (item.lastMessageSenderName ?? '').toLowerCase();
            return roomName.contains(query) ||
                subtitle.contains(query) ||
                sender.contains(query);
          }).toList();

    filtered.sort((a, b) {
      final aPinned = _pinnedRoomIds.contains(a.room.id);
      final bPinned = _pinnedRoomIds.contains(b.room.id);
      if (aPinned != bPinned) return aPinned ? -1 : 1;

      final aDate = a.lastMessageAt ?? a.room.createdAt;
      final bDate = b.lastMessageAt ?? b.room.createdAt;
      return bDate.compareTo(aDate);
    });

    return filtered;
  }

  Widget _buildContent(List<ChatRoomListItem> rooms) {
    final filteredRooms = _filterRooms(rooms);

    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 120),
      itemCount: filteredRooms.isEmpty ? 2 : filteredRooms.length + 1,
      separatorBuilder: (_, __) => const SizedBox(height: 2),
      itemBuilder: (context, index) {
        if (index == 0) {
          return _buildSearchBar();
        }

        if (filteredRooms.isEmpty) {
          return Padding(
            padding: const EdgeInsets.only(top: 180),
            child: Center(
              child: Text(
                _searchQuery.isEmpty
                    ? 'Você não participa de nenhum chat'
                    : 'Nenhuma conversa encontrada',
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 15,
                ),
              ),
            ),
          );
        }

        final item = filteredRooms[index - 1];
        return _buildRoomTile(item, index - 1);
      },
    );
  }

  Widget _buildEdgeGlow({
    required double top,
    double? left,
    double? right,
    double size = 50,
  }) {
    return Positioned(
      top: top,
      left: left,
      right: right,
      child: IgnorePointer(
        child: Container(
          width: size,
          height: size,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Color(0x88FFD77A),
                blurRadius: 28,
                spreadRadius: 2,
                offset: Offset(0, 0),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFloatingParticles() {
    return IgnorePointer(
      child: CustomPaint(
        painter: _SparklePainter(),
        size: Size.infinite,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _navy,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        titleSpacing: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: _gold,
            size: 28,
          ),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: const Text(
          'Conversas',
          style: TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.w800,
          ),
        ),
        centerTitle: true,
      ),
      floatingActionButton: SafeArea(
        minimum: const EdgeInsets.only(bottom: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_isAdmin) ...[
              FloatingActionButton(
                heroTag: 'create_group',
                onPressed: _showCreateGroupDialog,
                backgroundColor: _gold,
                child: const Icon(
                  Icons.groups_rounded,
                  color: _navy,
                ),
              ),
              const SizedBox(height: 12),
            ],
            FloatingActionButton.extended(
              heroTag: 'create_chat',
              onPressed: _showCreateConversationDialog,
              backgroundColor: _gold,
              foregroundColor: _navy,
              icon: const Icon(Icons.add_comment_rounded),
              label: const Text('Nova conversa'),
            ),
          ],
        ),
      ),
      body: Container(
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
        child: Stack(
          children: [
            Positioned.fill(
              child: Opacity(
                opacity: 0.24,
                child: Image.asset(
                  'assets/images/monte_olimpo_v2.png',
                  fit: BoxFit.cover,
                ),
              ),
            ),
            Positioned.fill(
              child: Container(
                color: _navyDark.withValues(alpha: 0.56),
              ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(26),
                          border: Border.all(
                            color: _gold.withValues(alpha: 0.45),
                            width: 1.3,
                          ),
                          color: Colors.white.withValues(alpha: 0.03),
                        ),
                      ),
                    ),
                    _buildEdgeGlow(top: 188, left: -10, size: 48),
                    _buildEdgeGlow(top: 335, left: -14, size: 46),
                    _buildEdgeGlow(top: 98, right: -10, size: 46),
                    _buildFloatingParticles(),
                    StreamBuilder<List<ChatRoomListItem>>(
                      stream: _roomsStream,
                      builder: (context, snapshot) {
                        if (snapshot.connectionState ==
                                ConnectionState.waiting &&
                            !snapshot.hasData) {
                          return const Center(
                            child: CircularProgressIndicator(color: _gold),
                          );
                        }

                        if (snapshot.hasError) {
                          return Center(
                            child: Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 28),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(14),
                                    decoration: BoxDecoration(
                                      color: _gold.withValues(alpha: 0.16),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.wifi_off_rounded,
                                      color: _gold,
                                      size: 34,
                                    ),
                                  ),
                                  const SizedBox(height: 14),
                                  const Text(
                                    'Não foi possível carregar as conversas.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 16,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    'Verifique a conexão e toque para atualizar.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color:
                                          Colors.white.withValues(alpha: 0.72),
                                      fontSize: 13,
                                    ),
                                  ),
                                  const SizedBox(height: 14),
                                  ElevatedButton.icon(
                                    onPressed: _reload,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: _gold,
                                      foregroundColor: _navy,
                                    ),
                                    icon: const Icon(Icons.refresh_rounded),
                                    label: const Text('Atualizar'),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }

                        final rooms = snapshot.data ?? [];

                        return RefreshIndicator(
                          color: _gold,
                          backgroundColor: _navy,
                          onRefresh: _reload,
                          child: Padding(
                            padding: const EdgeInsets.only(top: 14),
                            child: _buildContent(rooms),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SparklePainter extends CustomPainter {
  const _SparklePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final soft = Paint()
      ..color = const Color(0x66D4B06A)
      ..style = PaintingStyle.fill;

    final strong = Paint()
      ..color = const Color(0x99FFE29A)
      ..style = PaintingStyle.fill;

    final points = <Offset>[
      Offset(size.width * 0.03, size.height * 0.80),
      Offset(size.width * 0.05, size.height * 0.84),
      Offset(size.width * 0.07, size.height * 0.88),
      Offset(size.width * 0.10, size.height * 0.86),
      Offset(size.width * 0.92, size.height * 0.12),
      Offset(size.width * 0.95, size.height * 0.10),
      Offset(size.width * 0.97, size.height * 0.14),
    ];

    for (final p in points) {
      canvas.drawCircle(p, 1.4, soft);
    }

    canvas.drawCircle(
      Offset(size.width * 0.055, size.height * 0.83),
      2.0,
      strong,
    );
    canvas.drawCircle(
      Offset(size.width * 0.945, size.height * 0.115),
      1.8,
      strong,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
