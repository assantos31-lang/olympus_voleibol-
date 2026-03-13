import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/chat_message.dart';
import '../models/chat_room.dart';

class ChatRoomListItem {
  final ChatRoom room;
  final String? lastMessageText;
  final String? lastMessageSenderName;
  final DateTime? lastMessageAt;
  final int unreadCount;

  ChatRoomListItem({
    required this.room,
    this.lastMessageText,
    this.lastMessageSenderName,
    this.lastMessageAt,
    required this.unreadCount,
  });
}

class ChatService {
  final SupabaseClient supabase = Supabase.instance.client;

  String? get currentUserId => supabase.auth.currentUser?.id;

  Future<List<ChatRoom>> getMyRooms() async {
    final userId = currentUserId;
    if (userId == null) return [];

    final memberships = await supabase
        .from('chat_room_members')
        .select('room_id')
        .eq('user_id', userId)
        .eq('is_banned', false);

    if (memberships.isEmpty) return [];

    final roomIds =
        memberships.map<String>((item) => item['room_id'] as String).toList();

    final roomsResponse = await supabase
        .from('chat_rooms')
        .select()
        .inFilter('id', roomIds)
        .order('created_at');

    return roomsResponse.map<ChatRoom>((e) => ChatRoom.fromMap(e)).toList();
  }

  Future<List<ChatRoomListItem>> getMyRoomListItems() async {
    final userId = currentUserId;
    if (userId == null) return [];

    final rooms = await getMyRooms();
    if (rooms.isEmpty) return [];

    final roomIds = rooms.map((r) => r.id).toList();

    final messagesResponse = await supabase
        .from('chat_messages')
        .select('id, room_id, sender_id, content, created_at')
        .inFilter('room_id', roomIds)
        .order('created_at', ascending: false);

    final List<Map<String, dynamic>> messages = messagesResponse
        .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e))
        .toList();

    final senderIds = messages
        .map((m) => (m['sender_id'] ?? '').toString())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();

    final profileMap = <String, String>{};
    if (senderIds.isNotEmpty) {
      final profiles = await supabase
          .from('profiles')
          .select('id, full_name, avatar_url')
          .inFilter('id', senderIds);

      for (final profile in profiles) {
        final map = Map<String, dynamic>.from(profile);
        final id = (map['id'] ?? '').toString();
        final fullName = (map['full_name'] ?? '').toString();
        if (id.isNotEmpty) {
          profileMap[id] = fullName;
        }
      }
    }

    final messageIds = messages
        .map((m) => (m['id'] ?? '').toString())
        .where((id) => id.isNotEmpty)
        .toList();

    final readIds = <String>{};
    if (messageIds.isNotEmpty) {
      final reads = await supabase
          .from('chat_message_reads')
          .select('message_id')
          .eq('user_id', userId)
          .inFilter('message_id', messageIds);

      for (final read in reads) {
        final map = Map<String, dynamic>.from(read);
        final messageId = (map['message_id'] ?? '').toString();
        if (messageId.isNotEmpty) {
          readIds.add(messageId);
        }
      }
    }

    final latestMessageByRoom = <String, Map<String, dynamic>>{};
    final unreadCountByRoom = <String, int>{};

    for (final message in messages) {
      final roomId = (message['room_id'] ?? '').toString();
      final messageId = (message['id'] ?? '').toString();
      final senderId = (message['sender_id'] ?? '').toString();

      if (roomId.isEmpty || messageId.isEmpty) continue;

      latestMessageByRoom.putIfAbsent(roomId, () => message);

      final isOwnMessage = senderId == userId;
      final isRead = readIds.contains(messageId);

      if (!isOwnMessage && !isRead) {
        unreadCountByRoom[roomId] = (unreadCountByRoom[roomId] ?? 0) + 1;
      }
    }

    return rooms.map((room) {
      final lastMessage = latestMessageByRoom[room.id];
      final senderId = (lastMessage?['sender_id'] ?? '').toString();

      return ChatRoomListItem(
        room: room,
        lastMessageText: lastMessage?['content']?.toString(),
        lastMessageSenderName:
            senderId.isNotEmpty ? profileMap[senderId] : null,
        lastMessageAt: lastMessage?['created_at'] != null
            ? DateTime.parse(lastMessage!['created_at'] as String)
            : null,
        unreadCount: unreadCountByRoom[room.id] ?? 0,
      );
    }).toList();
  }

  Future<bool> isCurrentUserAdmin() async {
    final userId = currentUserId;
    if (userId == null) return false;

    final response = await supabase
        .from('profiles')
        .select('user_type')
        .eq('id', userId)
        .maybeSingle();

    final userType = (response?['user_type'] ?? '').toString().trim();
    return userType == 'admin';
  }

  Future<List<Map<String, dynamic>>> getSelectableUsers() async {
    final response = await supabase
        .from('profiles')
        .select('id, full_name, user_type, phone, avatar_url')
        .order('full_name');

    return response.map<Map<String, dynamic>>((e) {
      return Map<String, dynamic>.from(e);
    }).toList();
  }

  Future<ChatRoom> createGroupRoom({
    required String name,
    required List<String> participantUserIds,
  }) async {
    final userId = currentUserId;
    if (userId == null) {
      throw Exception('Usuário não autenticado');
    }

    final roomResponse = await supabase
        .from('chat_rooms')
        .insert({
          'name': name.trim(),
          'type': 'group',
          'created_by': userId,
        })
        .select()
        .single();

    final roomId = roomResponse['id'] as String;

    final memberIds = <String>{userId, ...participantUserIds};

    final members = memberIds
        .map((memberId) => {
              'room_id': roomId,
              'user_id': memberId,
              'role': memberId == userId ? 'admin' : 'member',
            })
        .toList();

    await supabase.from('chat_room_members').insert(members);

    return ChatRoom.fromMap(roomResponse);
  }

  Stream<List<ChatMessage>> streamMessages(String roomId) {
    return supabase
        .from('chat_messages')
        .stream(primaryKey: ['id'])
        .eq('room_id', roomId)
        .order('created_at')
        .asyncMap((data) async {
          final messages = data.map(ChatMessage.fromMap).toList();

          final senderIds = messages.map((m) => m.senderId).toSet().toList();
          if (senderIds.isEmpty) return messages;

          final profiles = await supabase
              .from('profiles')
              .select('id, full_name, avatar_url')
              .inFilter('id', senderIds);

          final profileMap = <String, String>{};
          for (final profile in profiles) {
            final id = (profile['id'] ?? '').toString();
            final fullName = (profile['full_name'] ?? '').toString();
            if (id.isNotEmpty) {
              profileMap[id] = fullName;
            }
          }

          return messages.map((message) {
            return message.copyWith(
              senderName: profileMap[message.senderId],
            );
          }).toList();
        });
  }

  Future<void> sendMessage({
    required String roomId,
    required String text,
  }) async {
    final userId = currentUserId;
    if (userId == null) throw Exception('Usuário não autenticado');

    final trimmed = text.trim();
    if (trimmed.isEmpty) return;

    await supabase.from('chat_messages').insert({
      'room_id': roomId,
      'sender_id': userId,
      'content': trimmed,
    });
  }

  Future<ChatRoom?> getRoomById(String roomId) async {
    final response = await supabase
        .from('chat_rooms')
        .select()
        .eq('id', roomId)
        .maybeSingle();

    if (response == null) return null;
    return ChatRoom.fromMap(response);
  }

  Future<void> setRoomLocked({
    required String roomId,
    required bool locked,
  }) async {
    await supabase.from('chat_rooms').update({
      'is_locked': locked,
      'allow_messages': !locked,
      if (locked) 'admin_only': false,
    }).eq('id', roomId);
  }

  Future<void> setRoomAdminOnly({
    required String roomId,
    required bool adminOnly,
  }) async {
    await supabase.from('chat_rooms').update({
      'admin_only': adminOnly,
      'is_locked': false,
      'allow_messages': true,
    }).eq('id', roomId);
  }

  Future<String?> getMyRoleInRoom(String roomId) async {
    final userId = currentUserId;
    if (userId == null) return null;

    final response = await supabase
        .from('chat_room_members')
        .select('role')
        .eq('room_id', roomId)
        .eq('user_id', userId)
        .maybeSingle();

    return response?['role']?.toString();
  }

  Future<void> markRoomMessagesAsRead(String roomId) async {
    final userId = currentUserId;
    if (userId == null) return;

    final messagesResponse = await supabase
        .from('chat_messages')
        .select('id, sender_id')
        .eq('room_id', roomId);

    final messages = messagesResponse
        .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e))
        .where((m) => (m['sender_id'] ?? '').toString() != userId)
        .toList();

    if (messages.isEmpty) return;

    final messageIds = messages
        .map((m) => (m['id'] ?? '').toString())
        .where((id) => id.isNotEmpty)
        .toList();

    if (messageIds.isEmpty) return;

    final readsResponse = await supabase
        .from('chat_message_reads')
        .select('message_id')
        .eq('user_id', userId)
        .inFilter('message_id', messageIds);

    final existingReadIds = readsResponse
        .map<String>((e) => (e['message_id'] ?? '').toString())
        .toSet();

    final inserts = messageIds
        .where((id) => !existingReadIds.contains(id))
        .map((id) => {
              'message_id': id,
              'user_id': userId,
            })
        .toList();

    if (inserts.isNotEmpty) {
      await supabase.from('chat_message_reads').insert(inserts);
    }
  }

  Future<List<Map<String, dynamic>>> getRoomParticipants(String roomId) async {
    final membersResponse = await supabase
        .from('chat_room_members')
        .select('user_id, role, is_muted, is_banned')
        .eq('room_id', roomId)
        .order('joined_at');

    final members = membersResponse
        .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e))
        .toList();

    if (members.isEmpty) return [];

    final userIds = members
        .map((m) => (m['user_id'] ?? '').toString())
        .where((id) => id.isNotEmpty)
        .toList();

    final profilesResponse = await supabase
        .from('profiles')
        .select('id, full_name, phone, user_type, avatar_url')
        .inFilter('id', userIds);

    final profileMap = <String, Map<String, dynamic>>{};
    for (final profile in profilesResponse) {
      final map = Map<String, dynamic>.from(profile);
      final id = (map['id'] ?? '').toString();
      if (id.isNotEmpty) {
        profileMap[id] = map;
      }
    }

    return members.map((member) {
      final userId = (member['user_id'] ?? '').toString();
      final profile = profileMap[userId] ?? <String, dynamic>{};

      return {
        'user_id': userId,
        'role': (member['role'] ?? '').toString(),
        'is_muted': member['is_muted'] as bool? ?? false,
        'is_banned': member['is_banned'] as bool? ?? false,
        'full_name': (profile['full_name'] ?? 'Sem nome').toString(),
        'phone': (profile['phone'] ?? '').toString(),
        'user_type': (profile['user_type'] ?? '').toString(),
        'avatar_url': (profile['avatar_url'] ?? '').toString(),
      };
    }).toList();
  }

  Future<List<Map<String, dynamic>>> getAvailableUsersForRoom(
    String roomId,
  ) async {
    final allUsers = await getSelectableUsers();
    final participants = await getRoomParticipants(roomId);

    final existingIds = participants
        .map((p) => (p['user_id'] ?? '').toString())
        .where((id) => id.isNotEmpty)
        .toSet();

    return allUsers.where((user) {
      final id = (user['id'] ?? '').toString();
      return id.isNotEmpty && !existingIds.contains(id);
    }).toList();
  }

  Future<void> addParticipantsToRoom({
    required String roomId,
    required List<String> userIds,
  }) async {
    if (userIds.isEmpty) return;

    final existingMembersResponse = await supabase
        .from('chat_room_members')
        .select('user_id')
        .eq('room_id', roomId)
        .inFilter('user_id', userIds);

    final existingIds = existingMembersResponse
        .map<String>((e) => (e['user_id'] ?? '').toString())
        .where((id) => id.isNotEmpty)
        .toSet();

    final newUserIds =
        userIds.where((userId) => !existingIds.contains(userId)).toList();

    if (newUserIds.isEmpty) return;

    final inserts = newUserIds
        .map((userId) => {
              'room_id': roomId,
              'user_id': userId,
              'role': 'member',
            })
        .toList();

    await supabase.from('chat_room_members').insert(inserts);
  }

  Future<void> removeParticipantFromRoom({
    required String roomId,
    required String userId,
  }) async {
    await supabase
        .from('chat_room_members')
        .delete()
        .eq('room_id', roomId)
        .eq('user_id', userId);
  }

  Future<void> setParticipantRole({
    required String roomId,
    required String userId,
    required String role,
  }) async {
    await supabase
        .from('chat_room_members')
        .update({'role': role})
        .eq('room_id', roomId)
        .eq('user_id', userId);
  }

  Future<void> setParticipantMuted({
    required String roomId,
    required String userId,
    required bool muted,
  }) async {
    await supabase
        .from('chat_room_members')
        .update({'is_muted': muted})
        .eq('room_id', roomId)
        .eq('user_id', userId);
  }

  Future<void> setParticipantBanned({
    required String roomId,
    required String userId,
    required bool banned,
  }) async {
    await supabase
        .from('chat_room_members')
        .update({'is_banned': banned})
        .eq('room_id', roomId)
        .eq('user_id', userId);
  }
}
