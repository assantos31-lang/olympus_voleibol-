import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../theme/olympus_theme.dart';
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
  final FocusNode _searchFocusNode = FocusNode();
  final ImagePicker _imagePicker = ImagePicker();

  late Future<List<ChatRoomListItem>> _futureRooms;
  late Stream<List<ChatRoomListItem>> _roomsStream;
  bool _isAdmin = false;
  String _searchQuery = '';
  bool _searchExpanded = false;
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
    _searchFocusNode.dispose();
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Erro ao carregar usuários: $e')));
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
              backgroundColor: _navyDark,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(28),
                side: BorderSide(color: _gold.withValues(alpha: 0.55)),
              ),
              titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
              contentPadding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              actionsPadding: const EdgeInsets.fromLTRB(12, 8, 12, 14),
              title: const Text(
                'Nova conversa',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 19,
                  fontWeight: FontWeight.w900,
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
                                        : Colors.white.withValues(alpha: 0.08),
                                    border: Border.all(
                                      color: isSelected
                                          ? _gold
                                          : Colors.black.withValues(
                                              alpha: 0.18,
                                            ),
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
                                                  color: Colors.white,
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
                                                    color:
                                                        Colors.black.withValues(
                                                      alpha: 0.55,
                                                    ),
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
                  child: const Text(
                    'Cancelar',
                    style: TextStyle(color: Colors.white70),
                  ),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _gold,
                    foregroundColor: _navy,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Erro ao carregar usuários: $e')));
      return;
    }

    if (!mounted) return;

    await showDialog(
      context: context,
      builder: (dialogContext) {
        bool isSaving = false;

        Future<void> pickImage(StateSetter setDialogState) async {
          final picked = await _imagePicker.pickImage(
            source: ImageSource.gallery,
          );
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
                                                      selectedUserIds.add(
                                                        userId,
                                                      );
                                                    } else {
                                                      selectedUserIds.remove(
                                                        userId,
                                                      );
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
            ? CachedNetworkImage(
                imageUrl: photoUrl,
                fit: BoxFit.cover,
                memCacheWidth: 240,
                memCacheHeight: 240,
                fadeInDuration: const Duration(milliseconds: 120),
                errorWidget: (_, __, ___) => Center(
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

  Future<void> _showRoomActions(ChatRoomListItem item) async {
    final isPinned = _pinnedRoomIds.contains(item.room.id);
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => SafeArea(
        child: Container(
          margin: const EdgeInsets.all(12),
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
          decoration: BoxDecoration(
            color: _navyDark,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: _gold.withValues(alpha: 0.5)),
            boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 24)],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 42,
                height: 4,
                margin: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              ListTile(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
                tileColor: Colors.white.withValues(alpha: 0.06),
                leading: Icon(
                  isPinned ? Icons.push_pin_outlined : Icons.push_pin_rounded,
                  color: _gold,
                ),
                title: Text(
                  isPinned ? 'Desafixar conversa' : 'Fixar conversa',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                onTap: () => Navigator.pop(sheetContext, 'pin'),
              ),
              const SizedBox(height: 8),
              ListTile(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
                tileColor: Colors.redAccent.withValues(alpha: 0.10),
                leading: const Icon(
                  Icons.delete_outline_rounded,
                  color: Colors.redAccent,
                ),
                title: const Text(
                  'Apagar conversa',
                  style: TextStyle(
                    color: Colors.redAccent,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                subtitle: const Text(
                  'Remove somente para você',
                  style: TextStyle(color: Colors.white60),
                ),
                onTap: () => Navigator.pop(sheetContext, 'hide'),
              ),
            ],
          ),
        ),
      ),
    );

    if (action == 'pin') {
      await _togglePinnedRoom(item);
    } else if (action == 'hide') {
      await _hideRoomForMe(item);
    }
  }

  Future<void> _hideRoomForMe(ChatRoomListItem item) async {
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => SafeArea(
        child: Container(
          margin: const EdgeInsets.all(12),
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
          decoration: BoxDecoration(
            color: _navyDark,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: _gold.withValues(alpha: 0.55)),
            boxShadow: const [
              BoxShadow(
                color: Colors.black45,
                blurRadius: 28,
                offset: Offset(0, 12),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 42,
                height: 4,
                margin: const EdgeInsets.only(bottom: 18),
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              Container(
                width: 62,
                height: 62,
                decoration: BoxDecoration(
                  color: Colors.redAccent.withValues(alpha: 0.13),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.redAccent.withValues(alpha: 0.45),
                  ),
                ),
                child: const Icon(
                  Icons.delete_outline_rounded,
                  color: Colors.redAccent,
                  size: 32,
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'Apagar conversa?',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Ela será removida somente para você. A outra pessoa continuará '
                'com a conversa e, se enviar uma nova mensagem, o chat aparecerá novamente.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.68),
                  fontSize: 14,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: BorderSide(
                          color: Colors.white.withValues(alpha: 0.24),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      onPressed: () => Navigator.pop(sheetContext, false),
                      child: const Text('Cancelar'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _gold,
                        foregroundColor: _navy,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      onPressed: () => Navigator.pop(sheetContext, true),
                      icon: const Icon(Icons.delete_outline_rounded, size: 19),
                      label: const Text(
                        'Apagar para mim',
                        style: TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Erro ao apagar conversa: $e')));
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
        final pendingPolls = await _chatService.getPendingPollsForRoom(
          item.room.id,
        );
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
        constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
        padding: const EdgeInsets.symmetric(horizontal: 7),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: _gold,
          borderRadius: BorderRadius.circular(999),
          boxShadow: [
            BoxShadow(color: _gold.withValues(alpha: 0.28), blurRadius: 9),
          ],
        ),
        child: Text(
          item.unreadCount > 99 ? '99+' : item.unreadCount.toString(),
          style: const TextStyle(
            color: _navyDark,
            fontWeight: FontWeight.w800,
            fontSize: 11.5,
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
      size: 54,
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
      padding: const EdgeInsets.fromLTRB(4, 2, 4, 10),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _gold.withValues(alpha: 0.28)),
          color: const Color(0xFF132F52).withValues(alpha: 0.94),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.16),
              blurRadius: 14,
              offset: const Offset(0, 7),
            ),
          ],
        ),
        child: TextField(
          controller: _searchController,
          focusNode: _searchFocusNode,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Pesquisar conversas',
            hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.65)),
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
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 11,
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
    final hasUnread = item.unreadCount > 0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () async {
            await Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => ChatPage(room: room)),
            );

            if (!mounted) return;
            await _reload();
          },
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: hasUnread
                    ? _gold.withValues(alpha: 0.62)
                    : Colors.white.withValues(alpha: 0.11),
                width: hasUnread ? 1.3 : 1,
              ),
              gradient: LinearGradient(
                colors: hasUnread
                    ? const [Color(0xFF193E68), Color(0xFF102B4B)]
                    : const [Color(0xE8122E50), Color(0xE80B213D)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.20),
                  blurRadius: 14,
                  offset: const Offset(0, 7),
                ),
              ],
            ),
            child: Stack(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 11,
                  ),
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
                                color: Colors.white,
                                fontSize: 15.5,
                                fontWeight: FontWeight.w900,
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
                                color: Colors.white.withValues(
                                  alpha: hasUnread ? 0.86 : 0.62,
                                ),
                                fontSize: 12.5,
                                fontWeight: hasUnread
                                    ? FontWeight.w700
                                    : FontWeight.w500,
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
                                color: hasUnread
                                    ? _gold
                                    : Colors.white.withValues(alpha: 0.50),
                                fontSize: 11.5,
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
                      IconButton(
                        tooltip: 'Opções da conversa',
                        onPressed: () => _showRoomActions(item),
                        visualDensity: VisualDensity.compact,
                        constraints: const BoxConstraints(
                          minWidth: 34,
                          minHeight: 38,
                        ),
                        icon: Icon(
                          Icons.more_vert_rounded,
                          color: Colors.white.withValues(alpha: 0.72),
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

  Widget _buildConversationOverview(List<ChatRoomListItem> rooms) {
    final unreadTotal = rooms.fold<int>(
      0,
      (total, item) => total + item.unreadCount,
    );
    final pinnedTotal =
        rooms.where((item) => _pinnedRoomIds.contains(item.room.id)).length;

    return Container(
      margin: const EdgeInsets.fromLTRB(4, 4, 4, 12),
      padding: const EdgeInsets.fromLTRB(16, 15, 14, 15),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: const LinearGradient(
          colors: [Color(0xFF173D69), Color(0xFF0B2545)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: _gold.withValues(alpha: 0.35)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.22),
            blurRadius: 18,
            offset: const Offset(0, 9),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: _gold.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: _gold.withValues(alpha: 0.36)),
            ),
            child: const Icon(Icons.forum_rounded, color: _gold, size: 25),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Suas conversas',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  unreadTotal > 0
                      ? '$unreadTotal mensagem${unreadTotal == 1 ? '' : 's'} não lida${unreadTotal == 1 ? '' : 's'}'
                      : 'Tudo em dia por aqui',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.68),
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          if (pinnedTotal > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.push_pin_rounded, color: _gold, size: 14),
                  const SizedBox(width: 4),
                  Text(
                    '$pinnedTotal',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildContent(List<ChatRoomListItem> rooms) {
    final filteredRooms = _filterRooms(rooms);
    final headerCount = _searchExpanded ? 2 : 1;

    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 120),
      itemCount: filteredRooms.isEmpty
          ? headerCount + 1
          : filteredRooms.length + headerCount,
      separatorBuilder: (_, __) => const SizedBox(height: 2),
      itemBuilder: (context, index) {
        if (index == 0) {
          return _buildConversationOverview(rooms);
        }

        if (_searchExpanded && index == 1) {
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
                style: const TextStyle(color: Colors.white70, fontSize: 15),
              ),
            ),
          );
        }

        final roomIndex = index - headerCount;
        final item = filteredRooms[roomIndex];
        return _buildRoomTile(item, roomIndex);
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
      child: CustomPaint(painter: _SparklePainter(), size: Size.infinite),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _navy,
      extendBodyBehindAppBar: false,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: _navyDark,
        foregroundColor: Colors.white,
        titleSpacing: 4,
        surfaceTintColor: Colors.transparent,
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
        centerTitle: false,
        actions: [
          IconButton(
            tooltip: _searchExpanded ? 'Fechar pesquisa' : 'Pesquisar',
            onPressed: () {
              setState(() {
                _searchExpanded = !_searchExpanded;
                if (!_searchExpanded) _searchController.clear();
              });
              if (_searchExpanded) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) _searchFocusNode.requestFocus();
                });
              } else {
                _searchFocusNode.unfocus();
              }
            },
            icon: Icon(
              _searchExpanded ? Icons.close_rounded : Icons.search_rounded,
              color: _gold,
            ),
          ),
          const SizedBox(width: 6),
        ],
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
                child: const Icon(Icons.groups_rounded, color: _navy),
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
            colors: [_navy, _navyDark],
          ),
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: Opacity(
                opacity: 0.24,
                child: const OlympusBrandBackgroundImage(
                  fit: BoxFit.cover,
                ),
              ),
            ),
            Positioned.fill(
              child: Container(color: _navyDark.withValues(alpha: 0.56)),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: EdgeInsets.zero,
                child: Stack(
                  children: [
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
                              padding: const EdgeInsets.symmetric(
                                horizontal: 28,
                              ),
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
                                      color: Colors.white.withValues(
                                        alpha: 0.72,
                                      ),
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
                          child: _buildContent(rooms),
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
