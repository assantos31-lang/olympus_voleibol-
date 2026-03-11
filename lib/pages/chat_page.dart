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

  @override
  void initState() {
    super.initState();
    _room = widget.room;
    _loadMyRole();
    _markAsRead();
  }

  Future<void> _loadMyRole() async {
    final role = await _chatService.getMyRoleInRoom(_room.id);
    if (!mounted) return;
    setState(() {
      _myRole = role;
    });
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

                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(fullName),
                            subtitle: Text(
                              phone.isNotEmpty ? '$phone • $role' : role,
                            ),
                            trailing: canManageRoom &&
                                    userId != _chatService.currentUserId
                                ? IconButton(
                                    icon: const Icon(
                                      Icons.remove_circle,
                                      color: Colors.red,
                                    ),
                                    onPressed: loading
                                        ? null
                                        : () async {
                                            setDialogState(() {
                                              loading = true;
                                            });
                                            try {
                                              await _chatService
                                                  .removeParticipantFromRoom(
                                                roomId: _room.id,
                                                userId: userId,
                                              );
                                              await refreshDialog(
                                                  setDialogState);
                                            } catch (e) {
                                              if (!mounted) return;
                                              ScaffoldMessenger.of(context)
                                                  .showSnackBar(
                                                SnackBar(
                                                  content: Text(
                                                    'Erro ao remover: $e',
                                                  ),
                                                ),
                                              );
                                            } finally {
                                              setDialogState(() {
                                                loading = false;
                                              });
                                            }
                                          },
                                  )
                                : role == 'admin'
                                    ? const Icon(Icons.shield,
                                        color: Colors.blue)
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

  List<Map<String, dynamic>> _participants = [];

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

  @override
  Widget build(BuildContext context) {
    final currentUserId = _chatService.currentUserId;
    final canManageRoom = currentUserId == _room.createdBy;
    final isRoomAdmin = _myRole == 'admin';
    final canSend = !_room.isLocked &&
        _room.allowMessages &&
        (!_room.adminOnly || isRoomAdmin);

    return Scaffold(
      appBar: AppBar(
        title: Text(_room.name ?? 'Chat'),
        actions: [
          IconButton(
            onPressed: _showParticipantsDialog,
            tooltip: 'Participantes',
            icon: const Icon(Icons.group),
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
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(
                      _room.adminOnly ? Icons.campaign : Icons.group_work,
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
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(_room.isLocked ? Icons.lock_open : Icons.lock),
            ),
        ],
      ),
      body: Column(
        children: [
          if (_room.isLocked)
            Container(
              width: double.infinity,
              color: Colors.orange.shade100,
              padding: const EdgeInsets.all(12),
              child: const Text(
                'Este chat está bloqueado para envio de mensagens.',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            )
          else if (_room.adminOnly && !isRoomAdmin)
            Container(
              width: double.infinity,
              color: Colors.orange.shade100,
              padding: const EdgeInsets.all(12),
              child: const Text(
                'Somente administradores podem enviar mensagens neste grupo.',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          Expanded(
            child: StreamBuilder<List<ChatMessage>>(
              stream: _chatService.streamMessages(_room.id),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final messages = snapshot.data!;
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _markAsRead();
                });

                if (messages.isEmpty) {
                  return const Center(
                    child: Text('Nenhuma mensagem ainda'),
                  );
                }

                return ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(12),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final msg = messages[index];
                    final isMine = msg.senderId == currentUserId;
                    final localTime = msg.createdAt.toLocal();

                    return Align(
                      alignment:
                          isMine ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        constraints: BoxConstraints(
                          maxWidth: MediaQuery.of(context).size.width * 0.75,
                        ),
                        decoration: BoxDecoration(
                          color: isMine
                              ? Colors.blue.shade100
                              : Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(12),
                        ),
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
                                    fontWeight: FontWeight.bold,
                                    color: Colors.black54,
                                  ),
                                ),
                              ),
                            Text(msg.content ?? ''),
                            const SizedBox(height: 4),
                            Text(
                              '${localTime.hour.toString().padLeft(2, '0')}:${localTime.minute.toString().padLeft(2, '0')}',
                              style: const TextStyle(
                                fontSize: 11,
                                color: Colors.black54,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          if (canSend)
            SafeArea(
              top: false,
              child: Container(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        minLines: 1,
                        maxLines: 4,
                        decoration: const InputDecoration(
                          hintText: 'Digite uma mensagem',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: _sending ? null : _send,
                      icon: _sending
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.send),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
