import 'package:flutter/material.dart';
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

  bool _sending = false;
  bool _updatingRoom = false;
  late ChatRoom _room;
  String? _myRole;
  List<Map<String, dynamic>> _participants = [];
  String? _lastMarkedMessageId;
  final Map<String, String?> _participantPhotoUrls = {};
  final Map<String, String> _participantNames = {};

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
  }

  Future<void> _loadMyRole() async {
    final role = await _chatService.getMyRoleInRoom(_room.id);
    if (!mounted) return;
    setState(() {
      _myRole = role;
    });
  }

  Future<void> _loadParticipantsForAvatars() async {
    try {
      final participants = await _chatService.getRoomParticipants(_room.id);
      if (!mounted) return;

      final photoMap = <String, String?>{};
      final nameMap = <String, String>{};

      for (final participant in participants) {
        final userId = (participant['user_id'] ?? '').toString();
        if (userId.isEmpty) continue;

        final fullName =
            (participant['full_name'] ?? participant['name'] ?? 'Sem nome')
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

    return null;
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

      final updatedRoom = await _chatService.getRoomById(_room.id);

      if (!mounted) return;

      if (updatedRoom != null) {
        setState(() {
          _room = updatedRoom;
        });
      }

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

      final updatedRoom = await _chatService.getRoomById(_room.id);

      if (!mounted) return;

      if (updatedRoom != null) {
        setState(() {
          _room = updatedRoom;
        });
      }

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
        final userId = (participant['user_id'] ?? '').toString();
        if (userId.isEmpty) continue;
        photoMap[userId] = _extractParticipantPhoto(participant);
        nameMap[userId] =
            (participant['full_name'] ?? participant['name'] ?? 'Sem nome')
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
                          final userId =
                              (participant['user_id'] ?? '').toString();
                          final fullName =
                              (participant['full_name'] ?? 'Sem nome')
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
      builder: (dialogContext) {
        bool saving = false;

        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Adicionar participantes'),
              content: SizedBox(
                width: double.maxFinite,
                child: users.isEmpty
                    ? const Text('Não há usuários disponíveis para adicionar.')
                    : ListView.builder(
                        shrinkWrap: true,
                        itemCount: users.length,
                        itemBuilder: (context, index) {
                          final user = users[index];
                          final userId = (user['id'] ?? '').toString();
                          final fullName =
                              (user['full_name'] ?? 'Sem nome').toString();
                          final phone = (user['phone'] ?? '').toString().trim();
                          final userType =
                              (user['user_type'] ?? '').toString().trim();

                          String subtitle = '';
                          if (phone.isNotEmpty && userType.isNotEmpty) {
                            subtitle = '$phone • $userType';
                          } else if (phone.isNotEmpty) {
                            subtitle = phone;
                          } else {
                            subtitle = userType;
                          }

                          return CheckboxListTile(
                            value: selectedUserIds.contains(userId),
                            onChanged: saving
                                ? null
                                : (checked) {
                                    setDialogState(() {
                                      if (checked == true) {
                                        selectedUserIds.add(userId);
                                      } else {
                                        selectedUserIds.remove(userId);
                                      }
                                    });
                                  },
                            title: Text(fullName),
                            subtitle: Text(subtitle),
                            controlAffinity: ListTileControlAffinity.leading,
                            contentPadding: EdgeInsets.zero,
                          );
                        },
                      ),
              ),
              actions: [
                TextButton(
                  onPressed:
                      saving ? null : () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancelar'),
                ),
                ElevatedButton(
                  onPressed: saving || selectedUserIds.isEmpty
                      ? null
                      : () async {
                          setDialogState(() {
                            saving = true;
                          });

                          try {
                            await _chatService.addParticipantsToRoom(
                              roomId: _room.id,
                              userIds: selectedUserIds.toList(),
                            );

                            if (!mounted) return;
                            Navigator.of(dialogContext).pop();
                            await _loadParticipantsForAvatars();
                          } catch (e) {
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Erro ao adicionar: $e'),
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
                      : const Text('Adicionar'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  String _timeText(DateTime dateTime) {
    final localTime = dateTime.toLocal();
    return '${localTime.hour.toString().padLeft(2, '0')}:${localTime.minute.toString().padLeft(2, '0')}';
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
            if (!isMine &&
                msg.senderName != null &&
                msg.senderName!.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  msg.senderName!,
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

    return Scaffold(
      backgroundColor: _navy,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.white,
        title: Text(
          _room.name ?? 'Chat',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
        actions: [
          IconButton(
            onPressed: _showParticipantsDialog,
            tooltip: 'Participantes',
            icon: const Icon(Icons.group, color: _gold),
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

                    final messages = snapshot.data!;

                    if (messages.isNotEmpty) {
                      final lastMessageId = messages.last.id;
                      if (_lastMarkedMessageId != lastMessageId) {
                        _lastMarkedMessageId = lastMessageId;
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          _markAsRead();
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
