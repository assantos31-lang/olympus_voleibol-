import 'package:flutter/material.dart';
import '../models/chat_room.dart';
import '../services/chat_service.dart';
import 'chat_page.dart';

class ChatRoomsPage extends StatefulWidget {
  const ChatRoomsPage({super.key});

  @override
  State<ChatRoomsPage> createState() => _ChatRoomsPageState();
}

class _ChatRoomsPageState extends State<ChatRoomsPage> {
  final ChatService _chatService = ChatService();
  late Future<List<ChatRoomListItem>> _futureRooms;
  bool _isAdmin = false;

  @override
  void initState() {
    super.initState();
    _futureRooms = _chatService.getMyRoomListItems();
    _loadIsAdmin();
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
    });
  }

  Future<void> _showCreateGroupDialog() async {
    final nameController = TextEditingController();
    List<Map<String, dynamic>> users = [];
    final Set<String> selectedUserIds = {};

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
              title: const Text('Criar grupo'),
              content: SizedBox(
                width: double.maxFinite,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: nameController,
                        decoration: const InputDecoration(
                          labelText: 'Nome do grupo',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Selecionar participantes',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
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
                              final fullName =
                                  (user['full_name'] ?? 'Sem nome').toString();
                              final phone =
                                  (user['phone'] ?? '').toString().trim();
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
                                onChanged: (checked) {
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
                                controlAffinity:
                                    ListTileControlAffinity.leading,
                                contentPadding: EdgeInsets.zero,
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
                            final room = await _chatService.createGroupRoom(
                              name: groupName,
                              participantUserIds: selectedUserIds.toList(),
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
                      : const Text('Criar'),
                ),
              ],
            );
          },
        );
      },
    );
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
    return room.type;
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
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.green,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          item.unreadCount.toString(),
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 12,
          ),
        ),
      );
    }

    if (room.isLocked) {
      return const Icon(Icons.lock, color: Colors.red);
    }

    if (room.adminOnly) {
      return const Icon(Icons.campaign, color: Colors.orange);
    }

    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Chats'),
      ),
      floatingActionButton: _isAdmin
          ? FloatingActionButton(
              onPressed: _showCreateGroupDialog,
              child: const Icon(Icons.add),
            )
          : null,
      body: FutureBuilder<List<ChatRoomListItem>>(
        future: _futureRooms,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Text('Erro: ${snapshot.error}'),
            );
          }

          final rooms = snapshot.data ?? [];

          if (rooms.isEmpty) {
            return RefreshIndicator(
              onRefresh: _reload,
              child: ListView(
                children: const [
                  SizedBox(height: 200),
                  Center(child: Text('Você não participa de nenhum chat')),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: _reload,
            child: ListView.separated(
              itemCount: rooms.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final item = rooms[index];
                final room = item.room;

                return ListTile(
                  title: Text(room.name ?? 'Chat'),
                  subtitle: Text(
                    _buildRoomSubtitle(item),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  leading: CircleAvatar(
                    child: Text(
                      (room.name?.isNotEmpty == true ? room.name![0] : 'C')
                          .toUpperCase(),
                    ),
                  ),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      if (item.lastMessageAt != null)
                        Text(
                          _formatLastMessageTime(item.lastMessageAt),
                          style: const TextStyle(fontSize: 12),
                        ),
                      const SizedBox(height: 4),
                      if (_buildTrailing(item) != null) _buildTrailing(item)!,
                    ],
                  ),
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
                );
              },
            ),
          );
        },
      ),
    );
  }
}
