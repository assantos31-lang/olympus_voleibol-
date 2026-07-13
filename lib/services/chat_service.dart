import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/chat_message.dart';
import '../models/chat_poll.dart';
import '../models/chat_room.dart';

class ChatRoomListItem {
  final ChatRoom room;
  final String? lastMessageText;
  final String? lastMessageSenderName;
  final DateTime? lastMessageAt;
  final int unreadCount;
  final String? avatarUrl;

  ChatRoomListItem({
    required this.room,
    this.lastMessageText,
    this.lastMessageSenderName,
    this.lastMessageAt,
    required this.unreadCount,
    this.avatarUrl,
  });
}

class ChatService {
  final SupabaseClient supabase = Supabase.instance.client;

  String? get currentUserId => supabase.auth.currentUser?.id;

  int _stableNotificationId(String value) {
    var hash = 0;
    for (final unit in value.codeUnits) {
      hash = ((hash * 31) + unit) & 0x7fffffff;
    }
    return 100000 + (hash % 800000);
  }

  Future<List<ChatRoom>> getMyRooms() async {
    final userId = currentUserId;
    if (userId == null) return [];

    final memberships = await supabase
        .from('chat_room_members')
        .select('room_id')
        .eq('user_id', userId)
        .eq('is_banned', false);

    if (memberships.isEmpty) return [];

    final roomIds = memberships
        .map<String>((item) => (item['room_id'] ?? '').toString())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();

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

    final hiddenAtByRoom = <String, DateTime>{};
    try {
      final hiddenRows = await supabase
          .from('chat_room_hidden_users')
          .select('room_id, hidden_at')
          .eq('user_id', userId)
          .inFilter('room_id', roomIds);

      for (final rawHidden in hiddenRows) {
        final hidden = Map<String, dynamic>.from(rawHidden);
        final roomId = (hidden['room_id'] ?? '').toString();
        final hiddenAtText = (hidden['hidden_at'] ?? '').toString();
        if (roomId.isEmpty || hiddenAtText.isEmpty) continue;

        hiddenAtByRoom[roomId] = DateTime.parse(hiddenAtText);
      }
    } catch (_) {
      // Se o SQL de ocultar conversa ainda não foi aplicado, mantém o chat
      // funcionando normalmente.
    }

    dynamic messagesResponse;
    try {
      messagesResponse = await supabase
          .from('chat_messages')
          .select(
            'id, room_id, sender_id, content, message_type, image_url, media_deleted_at, created_at, deleted_at',
          )
          .inFilter('room_id', roomIds)
          .order('created_at', ascending: false);
    } catch (_) {
      messagesResponse = await supabase
          .from('chat_messages')
          .select('id, room_id, sender_id, content, created_at')
          .inFilter('room_id', roomIds)
          .order('created_at', ascending: false);
    }

    final messageMap = <String, Map<String, dynamic>>{};
    for (final rawMessage in messagesResponse) {
      final message = Map<String, dynamic>.from(rawMessage);
      final id = (message['id'] ?? '').toString();
      if (id.isNotEmpty) {
        messageMap[id] = message;
      }
    }

    final List<Map<String, dynamic>> messages = messageMap.values.toList();

    final senderIds = messages
        .map((m) => (m['sender_id'] ?? '').toString())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();

    final roomMembersResponse = await supabase
        .from('chat_room_members')
        .select('room_id, user_id')
        .inFilter('room_id', roomIds)
        .eq('is_banned', false);

    final roomMembers = roomMembersResponse
        .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e))
        .toList();

    final participantIds = roomMembers
        .map((m) => (m['user_id'] ?? '').toString())
        .where((id) => id.isNotEmpty)
        .toSet();

    participantIds.addAll(senderIds);

    final profileNameMap = <String, String>{};
    final profileAvatarMap = <String, String>{};
    if (participantIds.isNotEmpty) {
      final profiles = await supabase
          .from('profiles')
          .select('id, full_name, avatar_url')
          .inFilter('id', participantIds.toList());

      for (final profile in profiles) {
        final map = Map<String, dynamic>.from(profile);
        final id = (map['id'] ?? '').toString();
        final fullName = (map['full_name'] ?? '').toString();
        final avatarUrl = (map['avatar_url'] ?? '').toString();

        if (id.isNotEmpty) {
          profileNameMap[id] = fullName;
          profileAvatarMap[id] = avatarUrl;
        }
      }
    }

    final roomAvatarMap = <String, String?>{};
    for (final room in rooms) {
      if (room.type == 'group' &&
          room.avatarUrl != null &&
          room.avatarUrl!.trim().isNotEmpty) {
        roomAvatarMap[room.id] = room.avatarUrl;
      }
    }

    for (final member in roomMembers) {
      final roomId = (member['room_id'] ?? '').toString();
      final memberUserId = (member['user_id'] ?? '').toString();

      if (roomId.isEmpty || memberUserId.isEmpty || memberUserId == userId) {
        continue;
      }

      roomAvatarMap.putIfAbsent(roomId, () {
        final avatar = profileAvatarMap[memberUserId];
        return avatar != null && avatar.trim().isNotEmpty ? avatar : null;
      });
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
      final isDeleted = message['deleted_at'] != null;

      if (roomId.isEmpty || messageId.isEmpty || isDeleted) continue;

      latestMessageByRoom.putIfAbsent(roomId, () => message);

      final isOwnMessage = senderId == userId;
      final isRead = readIds.contains(messageId);

      if (!isOwnMessage && !isRead) {
        unreadCountByRoom[roomId] = (unreadCountByRoom[roomId] ?? 0) + 1;
      }
    }

    final items = <ChatRoomListItem>[];

    for (final room in rooms) {
      final lastMessage = latestMessageByRoom[room.id];
      final lastMessageAt = lastMessage?['created_at'] != null
          ? DateTime.parse(lastMessage!['created_at'] as String)
          : null;
      final hiddenAt = hiddenAtByRoom[room.id];

      if (hiddenAt != null) {
        final compareDate = lastMessageAt ?? room.createdAt;
        if (!compareDate.isAfter(hiddenAt)) {
          continue;
        }
      }

      final senderId = (lastMessage?['sender_id'] ?? '').toString();
      final otherMemberId = roomMembers.map((member) {
        final roomId = (member['room_id'] ?? '').toString();
        final memberUserId = (member['user_id'] ?? '').toString();
        return roomId == room.id && memberUserId != userId ? memberUserId : '';
      }).firstWhere((id) => id.isNotEmpty, orElse: () => '');
      final displayRoom = room.type == 'direct' && otherMemberId.isNotEmpty
          ? room.copyWith(
              name: profileNameMap[otherMemberId]?.trim().isNotEmpty == true
                  ? profileNameMap[otherMemberId]
                  : room.name,
            )
          : room;

      items.add(ChatRoomListItem(
        room: displayRoom,
        lastMessageText: _previewMessage(lastMessage),
        lastMessageSenderName:
            senderId.isNotEmpty ? profileNameMap[senderId] : null,
        lastMessageAt: lastMessageAt,
        unreadCount: unreadCountByRoom[room.id] ?? 0,
        avatarUrl: roomAvatarMap[room.id],
      ));
    }

    return items;
  }

  String? _previewMessage(Map<String, dynamic>? message) {
    if (message == null) return null;
    if (message['deleted_at'] != null) return 'Mensagem apagada';

    final type = (message['message_type'] ?? 'text').toString();
    if (type == 'image') {
      final caption = (message['content'] ?? '').toString().trim();
      return caption.isEmpty ? '?? Imagem' : '?? $caption';
    }

    if (type == 'video') {
      if (message['media_deleted_at'] != null || message['image_url'] == null) {
        return 'Vídeo expirado';
      }
      final caption = (message['content'] ?? '').toString().trim();
      return caption.isEmpty ? '🎥 Vídeo' : '🎥 $caption';
    }

    if (type == 'poll') {
      final question = (message['content'] ?? '').toString().trim();
      return question.isEmpty ? '?? Enquete' : '?? Enquete: $question';
    }

    return message['content']?.toString();
  }

  Stream<List<ChatRoomListItem>> streamMyRoomListItems() {
    final controller = StreamController<List<ChatRoomListItem>>();
    RealtimeChannel? channel;
    Timer? fallbackTimer;
    var closed = false;

    Future<void> emit() async {
      if (closed) return;
      try {
        final items = await getMyRoomListItems();
        if (!closed && !controller.isClosed) controller.add(items);
      } catch (e, st) {
        if (!closed && !controller.isClosed) controller.addError(e, st);
      }
    }

    controller.onListen = () {
      emit();
      channel = supabase
          .channel('chat_rooms_live_${currentUserId ?? 'anon'}')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'chat_messages',
            callback: (_) => emit(),
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'chat_room_members',
            callback: (_) => emit(),
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'chat_rooms',
            callback: (_) => emit(),
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'chat_message_reads',
            callback: (_) => emit(),
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'chat_room_hidden_users',
            callback: (_) => emit(),
          )
          .subscribe();

      fallbackTimer =
          Timer.periodic(const Duration(seconds: 20), (_) => emit());
    };

    controller.onCancel = () async {
      closed = true;
      fallbackTimer?.cancel();
      if (channel != null) {
        await supabase.removeChannel(channel!);
      }
    };

    return controller.stream;
  }

  Future<bool> isCurrentUserAdmin() async {
    final userId = currentUserId;
    if (userId == null) return false;

    try {
      final roleResponse = await supabase
          .from('user_roles')
          .select('id')
          .eq('user_id', userId)
          .eq('role', 'admin')
          .eq('is_active', true)
          .maybeSingle();

      if (roleResponse != null) return true;
    } catch (_) {}

    final response = await supabase
        .from('profiles')
        .select('user_type')
        .eq('id', userId)
        .maybeSingle();

    final userType = (response?['user_type'] ?? '').toString().trim();
    return userType == 'admin';
  }

  Future<List<Map<String, dynamic>>> getSelectableUsers() async {
    final userId = currentUserId;
    final response = await supabase
        .from('profiles')
        .select('id, full_name, user_type, phone, avatar_url')
        .eq('is_active', true)
        .order('full_name');

    final users = response
        .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e))
        .where((profile) => (profile['id'] ?? '').toString() != userId)
        .toList();

    for (final user in users) {
      final fullName = (user['full_name'] ?? '').toString();
      user['display_name'] = compactPersonName(fullName);
    }

    users.sort((a, b) {
      final nameA = (a['display_name'] ?? a['full_name'] ?? '').toString();
      final nameB = (b['display_name'] ?? b['full_name'] ?? '').toString();
      return nameA.toLowerCase().compareTo(nameB.toLowerCase());
    });

    return users;
  }

  String compactPersonName(String fullName) {
    final parts = fullName
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.trim().isNotEmpty)
        .toList();

    if (parts.isEmpty) return 'Sem nome';
    if (parts.length == 1) return parts.first;

    return '${parts.first} ${parts.last}';
  }

  Future<int> getTotalUnreadCount() async {
    final userId = currentUserId;
    if (userId == null) return 0;

    try {
      final memberships = await supabase
          .from('chat_room_members')
          .select('room_id')
          .eq('user_id', userId)
          .eq('is_banned', false);

      final roomIds = memberships
          .map<String>((row) => (row['room_id'] ?? '').toString())
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList();

      if (roomIds.isEmpty) return 0;

      final messagesResponse = await supabase
          .from('chat_messages')
          .select('id, sender_id')
          .inFilter('room_id', roomIds)
          .neq('sender_id', userId);

      final messageIds = messagesResponse
          .map<String>((row) => (row['id'] ?? '').toString())
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList();

      if (messageIds.isEmpty) return 0;

      final readsResponse = await supabase
          .from('chat_message_reads')
          .select('message_id')
          .eq('user_id', userId)
          .inFilter('message_id', messageIds);

      final readIds = readsResponse
          .map<String>((row) => (row['message_id'] ?? '').toString())
          .where((id) => id.isNotEmpty)
          .toSet();

      return messageIds.where((id) => !readIds.contains(id)).length;
    } catch (e) {
      debugPrint('[ChatService] Erro ao buscar badge do chat: $e');
      return 0;
    }
  }

  Future<ChatRoom> createDirectRoom({
    required String otherUserId,
    String? otherUserName,
  }) async {
    final userId = currentUserId;
    if (userId == null) {
      throw Exception('Usuário não autenticado');
    }

    if (otherUserId == userId) {
      throw Exception('Você não pode abrir conversa com você mesmo.');
    }

    final memberships = await supabase
        .from('chat_room_members')
        .select('room_id')
        .inFilter('user_id', [userId, otherUserId]).eq('is_banned', false);

    final counter = <String, int>{};
    for (final item in memberships) {
      final roomId = (item['room_id'] ?? '').toString();
      if (roomId.isEmpty) continue;
      counter[roomId] = (counter[roomId] ?? 0) + 1;
    }

    final commonRoomIds = counter.entries
        .where((entry) => entry.value >= 2)
        .map((entry) => entry.key)
        .toList();

    if (commonRoomIds.isNotEmpty) {
      final existing = await supabase
          .from('chat_rooms')
          .select()
          .inFilter('id', commonRoomIds)
          .eq('type', 'direct')
          .limit(1)
          .maybeSingle();

      if (existing != null) {
        await unhideRoomForCurrentUser(existing['id'].toString());
        return ChatRoom.fromMap(existing);
      }
    }

    final roomResponse = await supabase
        .from('chat_rooms')
        .insert({
          'name': otherUserName?.trim().isNotEmpty == true
              ? otherUserName!.trim()
              : 'Conversa',
          'type': 'direct',
          'created_by': userId,
          'allow_messages': true,
          'admin_only': false,
          'is_locked': false,
        })
        .select()
        .single();

    final roomId = roomResponse['id'] as String;

    await supabase.from('chat_room_members').insert([
      {
        'room_id': roomId,
        'user_id': userId,
        'role': 'member',
      },
      {
        'room_id': roomId,
        'user_id': otherUserId,
        'role': 'member',
      },
    ]);

    return ChatRoom.fromMap(roomResponse);
  }

  Future<ChatRoom> createGroupRoom({
    required String name,
    required List<String> participantUserIds,
    String? avatarUrl,
  }) async {
    final userId = currentUserId;
    if (userId == null) {
      throw Exception('Usuário não autenticado');
    }

    final isAdmin = await isCurrentUserAdmin();
    if (!isAdmin) {
      throw Exception('Apenas administradores podem criar grupos.');
    }

    final roomPayload = {
      'name': name.trim(),
      'type': 'group',
      'created_by': userId,
      'allow_messages': true,
      'admin_only': false,
      'is_locked': false,
      if (avatarUrl != null && avatarUrl.trim().isNotEmpty)
        'avatar_url': avatarUrl.trim(),
    };

    dynamic roomResponse;
    try {
      roomResponse = await supabase
          .from('chat_rooms')
          .insert(roomPayload)
          .select()
          .single();
    } catch (e) {
      final message = e.toString();
      final avatarColumnMissing =
          message.contains('avatar_url') || message.contains('PGRST204');

      if (!avatarColumnMissing) rethrow;

      final fallbackPayload = Map<String, dynamic>.from(roomPayload)
        ..remove('avatar_url');
      roomResponse = await supabase
          .from('chat_rooms')
          .insert(fallbackPayload)
          .select()
          .single();
    }

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

  Future<String> uploadRoomAvatar({
    required String roomId,
    required File file,
  }) async {
    final bytes = await file.readAsBytes();
    final extension = file.path.split('.').last.toLowerCase();
    final safeExtension = extension.isEmpty ? 'jpg' : extension;
    final path =
        'chat_rooms/$roomId/avatar_${DateTime.now().millisecondsSinceEpoch}.$safeExtension';

    await supabase.storage.from('avatars').uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(
            upsert: true,
            contentType: safeExtension == 'png'
                ? 'image/png'
                : safeExtension == 'webp'
                    ? 'image/webp'
                    : 'image/jpeg',
          ),
        );

    return path;
  }

  Future<String> uploadChatImage({
    required String roomId,
    required File file,
  }) async {
    final bytes = await file.readAsBytes();
    final extension = file.path.split('.').last.toLowerCase();
    final safeExtension = extension.isEmpty ? 'jpg' : extension;
    final path =
        'chat_messages/$roomId/image_${DateTime.now().millisecondsSinceEpoch}.$safeExtension';

    await supabase.storage.from('avatars').uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(
            upsert: true,
            contentType: 'image/jpeg',
          ),
        );

    return path;
  }

  Future<String> uploadChatVideo({
    required String roomId,
    required File file,
  }) async {
    final extension = file.path.split('.').last.toLowerCase();
    final safeExtension = extension.isEmpty ? 'mp4' : extension;
    final path =
        'chat_messages/$roomId/video_${DateTime.now().millisecondsSinceEpoch}.$safeExtension';

    await supabase.storage.from('avatars').upload(
          path,
          file,
          fileOptions: FileOptions(
            upsert: true,
            contentType: _videoContentType(safeExtension),
          ),
        );

    return path;
  }

  String _videoContentType(String extension) {
    switch (extension) {
      case 'mov':
        return 'video/quicktime';
      case 'webm':
        return 'video/webm';
      case 'm4v':
        return 'video/x-m4v';
      default:
        return 'video/mp4';
    }
  }

  Future<void> updateRoomName({
    required String roomId,
    required String name,
  }) async {
    await supabase.from('chat_rooms').update({
      'name': name.trim(),
    }).eq('id', roomId);
  }

  Future<void> updateRoomAvatar({
    required String roomId,
    required String avatarUrl,
  }) async {
    await supabase.from('chat_rooms').update({
      'avatar_url': avatarUrl,
    }).eq('id', roomId);
  }

  Future<void> updateCurrentUserChatName(String name) async {
    final userId = currentUserId;
    if (userId == null) throw Exception('Usuário não autenticado');

    final cleanName = name.trim();
    if (cleanName.isEmpty) throw Exception('Informe um nome válido');

    await supabase.from('profiles').update({
      'full_name': cleanName,
    }).eq('id', userId);
  }

  Future<void> deletePoll({
    required String pollId,
  }) async {
    final userId = currentUserId;
    if (userId == null) throw Exception('Usuário não autenticado');

    final isAdmin = await isCurrentUserAdmin();
    if (!isAdmin) {
      throw Exception('Apenas administradores podem excluir enquetes.');
    }

    await supabase.from('chat_poll_votes').delete().eq('poll_id', pollId);
    await supabase.from('chat_poll_options').delete().eq('poll_id', pollId);
    await supabase.from('chat_polls').delete().eq('id', pollId);
  }

  Future<void> setPollPinned({
    required String pollId,
    required bool pinned,
  }) async {
    final userId = currentUserId;
    if (userId == null) throw Exception('Usuário não autenticado');

    final isAdmin = await isCurrentUserAdmin();
    if (!isAdmin) {
      throw Exception('Apenas administradores podem fixar enquetes.');
    }

    await supabase.from('chat_polls').update({
      'is_pinned': pinned,
    }).eq('id', pollId);
  }

  Future<List<Map<String, dynamic>>> getPollVotesDetail(String pollId) async {
    final userId = currentUserId;
    if (userId == null) return [];

    final isAdmin = await isCurrentUserAdmin();
    if (!isAdmin) {
      throw Exception('Apenas administradores podem visualizar os votos.');
    }

    final votesResponse = await supabase
        .from('chat_poll_votes')
        .select('option_id, user_id, created_at')
        .eq('poll_id', pollId)
        .order('created_at', ascending: true);

    final votes = (votesResponse as List)
        .map((row) => Map<String, dynamic>.from(row))
        .toList();

    if (votes.isEmpty) return [];

    final optionIds = votes
        .map((vote) => (vote['option_id'] ?? '').toString())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();
    final userIds = votes
        .map((vote) => (vote['user_id'] ?? '').toString())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();

    final optionTextById = <String, String>{};
    if (optionIds.isNotEmpty) {
      final optionsResponse = await supabase
          .from('chat_poll_options')
          .select('id, option_text')
          .inFilter('id', optionIds);

      for (final rawOption in optionsResponse as List) {
        final option = Map<String, dynamic>.from(rawOption);
        final id = (option['id'] ?? '').toString();
        if (id.isNotEmpty) {
          optionTextById[id] = (option['option_text'] ?? '').toString();
        }
      }
    }

    final profileById = <String, Map<String, dynamic>>{};
    if (userIds.isNotEmpty) {
      final profilesResponse = await supabase
          .from('profiles')
          .select('id, full_name, avatar_url')
          .inFilter('id', userIds);

      for (final rawProfile in profilesResponse as List) {
        final profile = Map<String, dynamic>.from(rawProfile);
        final id = (profile['id'] ?? '').toString();
        if (id.isNotEmpty) profileById[id] = profile;
      }
    }

    return votes.map((vote) {
      final optionId = (vote['option_id'] ?? '').toString();
      final voterId = (vote['user_id'] ?? '').toString();
      final profile = profileById[voterId] ?? const <String, dynamic>{};
      return {
        'user_id': voterId,
        'full_name': (profile['full_name'] ?? 'Sem nome').toString(),
        'avatar_url': (profile['avatar_url'] ?? '').toString(),
        'option_id': optionId,
        'option_text': optionTextById[optionId] ?? 'Opção removida',
        'created_at': vote['created_at'],
      };
    }).toList();
  }

  Future<void> deleteRoomForEveryone(String roomId) async {
    final userId = currentUserId;
    if (userId == null) throw Exception('Usuário não autenticado');

    final isAdmin = await isCurrentUserAdmin();
    if (!isAdmin) {
      throw Exception('Apenas administradores podem excluir grupos.');
    }

    final messagesResponse =
        await supabase.from('chat_messages').select('id').eq('room_id', roomId);
    final messageIds = (messagesResponse as List)
        .map((row) => (row['id'] ?? '').toString())
        .where((id) => id.isNotEmpty)
        .toList();

    if (messageIds.isNotEmpty) {
      await supabase
          .from('chat_message_reads')
          .delete()
          .inFilter('message_id', messageIds);
    }

    final pollsResponse =
        await supabase.from('chat_polls').select('id').eq('room_id', roomId);
    final pollIds = (pollsResponse as List)
        .map((row) => (row['id'] ?? '').toString())
        .where((id) => id.isNotEmpty)
        .toList();

    if (pollIds.isNotEmpty) {
      await supabase
          .from('chat_poll_votes')
          .delete()
          .inFilter('poll_id', pollIds);
      await supabase
          .from('chat_poll_options')
          .delete()
          .inFilter('poll_id', pollIds);
      await supabase.from('chat_polls').delete().inFilter('id', pollIds);
    }

    await supabase.from('chat_typing_status').delete().eq('room_id', roomId);
    await supabase.from('chat_messages').delete().eq('room_id', roomId);
    await supabase.from('chat_room_members').delete().eq('room_id', roomId);
    await supabase.from('chat_rooms').delete().eq('id', roomId);
  }

  Stream<List<ChatMessage>> streamMessages(String roomId) {
    final controller = StreamController<List<ChatMessage>>();
    RealtimeChannel? channel;

    Future<void> emit() async {
      if (controller.isClosed) return;
      try {
        controller.add(await _loadMessagesForRoom(roomId));
      } catch (error, stackTrace) {
        if (!controller.isClosed) {
          controller.addError(error, stackTrace);
        }
      }
    }

    controller.onListen = () {
      emit();
      channel = supabase
          .channel('chat_messages_live_$roomId')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'chat_messages',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'room_id',
              value: roomId,
            ),
            callback: (_) => emit(),
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'chat_message_reactions',
            callback: (_) => emit(),
          )
          .subscribe();
    };

    controller.onCancel = () async {
      final liveChannel = channel;
      if (liveChannel != null) {
        await supabase.removeChannel(liveChannel);
      }
    };

    return controller.stream;
  }

  Future<List<ChatMessage>> _loadMessagesForRoom(String roomId) async {
    final data = await supabase
        .from('chat_messages')
        .select()
        .eq('room_id', roomId)
        .order('created_at');

    final rows = data.map<Map<String, dynamic>>((row) {
      return Map<String, dynamic>.from(row);
    }).toList();

    final messageIds = rows
        .map((row) => (row['id'] ?? '').toString())
        .where((id) => id.isNotEmpty)
        .toList();

    final reactionByMessageId = <String, String>{};
    if (messageIds.isNotEmpty) {
      try {
        final reactions = await supabase
            .from('chat_message_reactions')
            .select('message_id, emoji, created_at')
            .inFilter('message_id', messageIds)
            .order('created_at', ascending: false);

        for (final rawReaction in reactions) {
          final reaction = Map<String, dynamic>.from(rawReaction);
          final messageId = (reaction['message_id'] ?? '').toString();
          final emoji = (reaction['emoji'] ?? '').toString().trim();
          if (messageId.isNotEmpty &&
              emoji.isNotEmpty &&
              !reactionByMessageId.containsKey(messageId)) {
            reactionByMessageId[messageId] = emoji;
          }
        }
      } catch (_) {
        // Se o SQL ainda não foi aplicado, o chat continua funcionando sem reação.
      }
    }

    final messages = <ChatMessage>[];
    final senderIds = <String>{};
    for (final row in rows) {
      final messageId = (row['id'] ?? '').toString();
      row['reaction_emoji'] = reactionByMessageId[messageId];
      final message = ChatMessage.fromMap(row);
      messages.add(message);
      senderIds.add(message.senderId);
    }

    if (senderIds.isEmpty) return messages;

    final profiles = await supabase
        .from('profiles')
        .select('id, full_name, avatar_url')
        .inFilter('id', senderIds.toList());

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
  }

  Future<void> sendMessage({
    required String roomId,
    required String text,
    String? replyToMessageId,
    String? replyToText,
    String? replyToSenderName,
  }) async {
    final userId = currentUserId;
    if (userId == null) throw Exception('Usuário não autenticado');

    final trimmed = text.trim();
    if (trimmed.isEmpty) return;

    final payload = <String, dynamic>{
      'room_id': roomId,
      'sender_id': userId,
      'content': trimmed,
    };

    if ((replyToMessageId ?? '').trim().isNotEmpty) {
      payload['reply_to_message_id'] = replyToMessageId;
      payload['reply_to_text'] = (replyToText ?? '').trim();
      payload['reply_to_sender_name'] = (replyToSenderName ?? '').trim();
    }

    await supabase.from('chat_messages').insert(payload);
    await unhideRoomForCurrentUser(roomId);

    unawaited(_sendPushToRoomParticipants(
      roomId: roomId,
      senderId: userId,
      content: trimmed,
    ));
  }

  Future<void> sendImageMessage({
    required String roomId,
    required File imageFile,
    String caption = '',
  }) async {
    final userId = currentUserId;
    if (userId == null) throw Exception('Usuário não autenticado');

    final imagePath = await uploadChatImage(roomId: roomId, file: imageFile);
    final trimmedCaption = caption.trim();

    await supabase.from('chat_messages').insert({
      'room_id': roomId,
      'sender_id': userId,
      'content': trimmedCaption,
      'message_type': 'image',
      'image_url': imagePath,
    });
    await unhideRoomForCurrentUser(roomId);

    unawaited(_sendPushToRoomParticipants(
      roomId: roomId,
      senderId: userId,
      content: trimmedCaption.isEmpty ? '📷 Imagem' : '📷 $trimmedCaption',
    ));
  }

  Future<void> sendVideoMessage({
    required String roomId,
    required File videoFile,
    required bool isOriginal,
    String caption = '',
  }) async {
    final userId = currentUserId;
    if (userId == null) throw Exception('Usuário não autenticado');

    final videoPath = await uploadChatVideo(roomId: roomId, file: videoFile);
    final trimmedCaption = caption.trim();
    final retentionDays = isOriginal ? 30 : 90;
    final expiresAt = DateTime.now()
        .toUtc()
        .add(Duration(days: retentionDays))
        .toIso8601String();

    await supabase.from('chat_messages').insert({
      'room_id': roomId,
      'sender_id': userId,
      'content': trimmedCaption,
      'message_type': 'video',
      // Mantém compatibilidade com a estrutura atual de mídia do chat.
      'image_url': videoPath,
      'media_quality': isOriginal ? 'original' : 'compressed',
      'media_expires_at': expiresAt,
    });
    await unhideRoomForCurrentUser(roomId);

    unawaited(_sendPushToRoomParticipants(
      roomId: roomId,
      senderId: userId,
      content: trimmedCaption.isEmpty ? '🎥 Vídeo' : '🎥 $trimmedCaption',
    ));
  }

  Future<void> editMessage({
    required String messageId,
    required String text,
  }) async {
    final userId = currentUserId;
    if (userId == null) throw Exception('Usuário não autenticado');

    final trimmed = text.trim();
    if (trimmed.isEmpty) throw Exception('A mensagem não pode ficar vazia.');

    await supabase
        .from('chat_messages')
        .update({
          'content': trimmed,
          'edited_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', messageId)
        .eq('sender_id', userId);
  }

  Future<void> deleteMessage({
    required String messageId,
  }) async {
    final userId = currentUserId;
    if (userId == null) throw Exception('Usuário não autenticado');

    await supabase
        .from('chat_messages')
        .update({
          'content': '',
          'deleted_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', messageId)
        .eq('sender_id', userId);
  }

  Future<void> reactToMessage({
    required String messageId,
    String? emoji,
  }) async {
    final userId = currentUserId;
    if (userId == null) throw Exception('Usuário não autenticado');

    final cleanEmoji = (emoji ?? '').trim();

    if (cleanEmoji.isEmpty) {
      await supabase
          .from('chat_message_reactions')
          .delete()
          .eq('message_id', messageId)
          .eq('user_id', userId);
      return;
    }

    await supabase.from('chat_message_reactions').upsert({
      'message_id': messageId,
      'user_id': userId,
      'emoji': cleanEmoji,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'message_id,user_id');
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
      try {
        await supabase
            .from('chat_message_reads')
            .upsert(inserts, onConflict: 'message_id,user_id');
      } catch (_) {
        await supabase.from('chat_message_reads').insert(inserts);
      }
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
        'display_name': compactPersonName(
          (profile['full_name'] ?? 'Sem nome').toString(),
        ),
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

  Future<void> deleteRoomForCurrentUser(String roomId) async {
    final userId = currentUserId;
    if (userId == null) throw Exception('Usuário não autenticado');

    // Igual WhatsApp: "apagar conversa" apaga apenas para o usuário atual.
    // Nunca remova o usuário de chat_room_members em conversa direta, porque
    // isso quebra o recebimento de novas mensagens. A sala fica viva, some da
    // lista de quem apagou e volta quando chegar uma nova mensagem.
    await supabase.from('chat_room_hidden_users').upsert(
      {
        'room_id': roomId,
        'user_id': userId,
        'hidden_at': DateTime.now().toUtc().toIso8601String(),
      },
      onConflict: 'room_id,user_id',
    );

    await markRoomMessagesAsRead(roomId);
  }

  Future<void> unhideRoomForCurrentUser(String roomId) async {
    final userId = currentUserId;
    if (userId == null) return;

    try {
      await supabase
          .from('chat_room_hidden_users')
          .delete()
          .eq('room_id', roomId)
          .eq('user_id', userId);
    } catch (_) {
      // Se o SQL ainda não foi aplicado, não deve impedir enviar/abrir conversa.
    }
  }

  Future<void> setCurrentUserOnline(bool isOnline) async {
    final userId = currentUserId;
    if (userId == null) return;

    await supabase.from('user_presence').upsert({
      'user_id': userId,
      'is_online': isOnline,
      'last_seen': DateTime.now().toUtc().toIso8601String(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  Future<ChatPoll> createPoll({
    required String roomId,
    required String question,
    required List<String> options,
  }) async {
    final userId = currentUserId;
    if (userId == null) throw Exception('Usuário não autenticado');

    final canCreate = await isCurrentUserAdmin();
    if (!canCreate) {
      throw Exception('Apenas administradores podem criar enquetes.');
    }

    final cleanOptions = options
        .map((option) => option.trim())
        .where((option) => option.isNotEmpty)
        .toList();

    if (question.trim().isEmpty) {
      throw Exception('Informe a pergunta da enquete.');
    }

    if (cleanOptions.length < 2) {
      throw Exception('Informe pelo menos duas opções.');
    }

    final room = await getRoomById(roomId);
    if (room == null || room.type != 'group') {
      throw Exception('Enquetes estão disponíveis apenas em grupos.');
    }

    final pollResponse = await supabase
        .from('chat_polls')
        .insert({
          'room_id': roomId,
          'created_by': userId,
          'question': question.trim(),
        })
        .select()
        .single();

    final poll = ChatPoll.fromMap(Map<String, dynamic>.from(pollResponse));

    final optionRows = <Map<String, dynamic>>[];
    for (var i = 0; i < cleanOptions.length; i++) {
      optionRows.add({
        'poll_id': poll.id,
        'option_text': cleanOptions[i],
        'position': i,
      });
    }

    await supabase.from('chat_poll_options').insert(optionRows);

    await sendMessage(
      roomId: roomId,
      text:
          '📊 Enquete criada: ${question.trim()}\nAbra esta conversa para votar.',
    );

    final insertedOptions = optionRows
        .map((row) => ChatPollOption.fromMap(Map<String, dynamic>.from(row)))
        .toList();

    return ChatPoll.fromMap(
      Map<String, dynamic>.from(pollResponse),
      options: insertedOptions,
    );
  }

  Future<List<ChatPoll>> getPendingPollsForRoom(String roomId) async {
    final userId = currentUserId;
    if (userId == null) return [];

    final membership = await supabase
        .from('chat_room_members')
        .select('room_id')
        .eq('room_id', roomId)
        .eq('user_id', userId)
        .eq('is_banned', false)
        .maybeSingle();

    if (membership == null) return [];

    final pollsResponse = await supabase
        .from('chat_polls')
        .select(
            'id, room_id, created_by, question, is_closed, is_pinned, created_at')
        .eq('room_id', roomId)
        .eq('is_closed', false)
        .order('created_at', ascending: true);

    final polls = (pollsResponse as List)
        .map((row) => Map<String, dynamic>.from(row))
        .where((row) => (row['id'] ?? '').toString().isNotEmpty)
        .toList();

    if (polls.isEmpty) return [];

    final pollIds = polls.map((poll) => poll['id'].toString()).toList();

    final votesResponse = await supabase
        .from('chat_poll_votes')
        .select('poll_id, option_id, user_id')
        .inFilter('poll_id', pollIds);

    final votedPollIds = <String>{};
    final voteCounts = <String, int>{};

    for (final rawVote in votesResponse as List) {
      final vote = Map<String, dynamic>.from(rawVote);
      final pollId = (vote['poll_id'] ?? '').toString();
      final optionId = (vote['option_id'] ?? '').toString();
      final voteUserId = (vote['user_id'] ?? '').toString();

      if (voteUserId == userId && pollId.isNotEmpty) {
        votedPollIds.add(pollId);
      }
      if (optionId.isNotEmpty) {
        voteCounts[optionId] = (voteCounts[optionId] ?? 0) + 1;
      }
    }

    final pendingPolls = polls
        .where((poll) => !votedPollIds.contains(poll['id'].toString()))
        .toList();

    if (pendingPolls.isEmpty) return [];

    final pendingPollIds =
        pendingPolls.map((poll) => poll['id'].toString()).toList();

    final optionsResponse = await supabase
        .from('chat_poll_options')
        .select('id, poll_id, option_text, position')
        .inFilter('poll_id', pendingPollIds)
        .order('position', ascending: true);

    final optionsByPollId = <String, List<ChatPollOption>>{};
    for (final rawOption in optionsResponse as List) {
      final optionMap = Map<String, dynamic>.from(rawOption);
      final option = ChatPollOption.fromMap(
        optionMap,
        voteCount: voteCounts[(optionMap['id'] ?? '').toString()] ?? 0,
      );
      optionsByPollId.putIfAbsent(option.pollId, () => []).add(option);
    }

    return pendingPolls.map((poll) {
      final pollId = poll['id'].toString();
      return ChatPoll.fromMap(
        poll,
        options: optionsByPollId[pollId] ?? const [],
        myOptionId: null,
      );
    }).toList();
  }

  Future<List<ChatPoll>> getPollsForRoom(String roomId) async {
    final userId = currentUserId;
    if (userId == null) return [];

    final membership = await supabase
        .from('chat_room_members')
        .select('room_id')
        .eq('room_id', roomId)
        .eq('user_id', userId)
        .eq('is_banned', false)
        .maybeSingle();

    if (membership == null) return [];

    final pollsResponse = await supabase
        .from('chat_polls')
        .select(
            'id, room_id, created_by, question, is_closed, is_pinned, created_at')
        .eq('room_id', roomId)
        .order('is_pinned', ascending: false)
        .order('created_at', ascending: true);

    final polls = (pollsResponse as List)
        .map((row) => Map<String, dynamic>.from(row))
        .where((row) => (row['id'] ?? '').toString().isNotEmpty)
        .toList();

    if (polls.isEmpty) return [];

    final pollIds = polls.map((poll) => poll['id'].toString()).toList();

    final votesResponse = await supabase
        .from('chat_poll_votes')
        .select('poll_id, option_id, user_id')
        .inFilter('poll_id', pollIds);

    final voteCounts = <String, int>{};
    final myVotesByPollId = <String, String>{};

    for (final rawVote in votesResponse as List) {
      final vote = Map<String, dynamic>.from(rawVote);
      final pollId = (vote['poll_id'] ?? '').toString();
      final optionId = (vote['option_id'] ?? '').toString();
      final voteUserId = (vote['user_id'] ?? '').toString();

      if (optionId.isNotEmpty) {
        voteCounts[optionId] = (voteCounts[optionId] ?? 0) + 1;
      }

      if (voteUserId == userId && pollId.isNotEmpty && optionId.isNotEmpty) {
        myVotesByPollId[pollId] = optionId;
      }
    }

    final optionsResponse = await supabase
        .from('chat_poll_options')
        .select('id, poll_id, option_text, position')
        .inFilter('poll_id', pollIds)
        .order('position', ascending: true);

    final optionsByPollId = <String, List<ChatPollOption>>{};
    for (final rawOption in optionsResponse as List) {
      final optionMap = Map<String, dynamic>.from(rawOption);
      final optionId = (optionMap['id'] ?? '').toString();
      final option = ChatPollOption.fromMap(
        optionMap,
        voteCount: voteCounts[optionId] ?? 0,
      );
      optionsByPollId.putIfAbsent(option.pollId, () => []).add(option);
    }

    return polls.map((poll) {
      final pollId = poll['id'].toString();
      return ChatPoll.fromMap(
        poll,
        options: optionsByPollId[pollId] ?? const [],
        myOptionId: myVotesByPollId[pollId],
      );
    }).toList();
  }

  Stream<List<ChatPoll>> streamPollsForRoom(String roomId) {
    final controller = StreamController<List<ChatPoll>>();
    RealtimeChannel? channel;
    Timer? fallbackTimer;
    var disposed = false;

    Future<void> emit() async {
      if (disposed || controller.isClosed) return;
      try {
        controller.add(await getPollsForRoom(roomId));
      } catch (e, st) {
        if (!controller.isClosed) controller.addError(e, st);
      }
    }

    emit();

    channel = supabase
        .channel('chat_room_polls_cards_$roomId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'chat_polls',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'room_id',
            value: roomId,
          ),
          callback: (_) => emit(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'chat_poll_options',
          callback: (_) => emit(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'chat_poll_votes',
          callback: (_) => emit(),
        )
        .subscribe();

    fallbackTimer = Timer.periodic(const Duration(seconds: 20), (_) => emit());

    controller.onCancel = () async {
      disposed = true;
      fallbackTimer?.cancel();
      if (channel != null) {
        await supabase.removeChannel(channel!);
      }
    };

    return controller.stream;
  }

  Stream<List<ChatPoll>> streamPendingPollsForRoom(String roomId) {
    final controller = StreamController<List<ChatPoll>>();
    RealtimeChannel? channel;
    Timer? fallbackTimer;
    var disposed = false;

    Future<void> emit() async {
      if (disposed || controller.isClosed) return;
      try {
        controller.add(await getPendingPollsForRoom(roomId));
      } catch (e) {
        if (!controller.isClosed) controller.addError(e);
      }
    }

    emit();

    channel = supabase
        .channel('chat_polls_live_$roomId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'chat_polls',
          callback: (_) => emit(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'chat_poll_options',
          callback: (_) => emit(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'chat_poll_votes',
          callback: (_) => emit(),
        )
        .subscribe();

    fallbackTimer = Timer.periodic(const Duration(seconds: 20), (_) => emit());

    controller.onCancel = () async {
      disposed = true;
      fallbackTimer?.cancel();
      if (channel != null) {
        await supabase.removeChannel(channel!);
      }
    };

    return controller.stream;
  }

  Future<void> votePoll({
    required String pollId,
    required String optionId,
  }) async {
    final userId = currentUserId;
    if (userId == null) throw Exception('Usuário não autenticado');

    await supabase.from('chat_poll_votes').upsert(
      {
        'poll_id': pollId,
        'option_id': optionId,
        'user_id': userId,
      },
      onConflict: 'poll_id,user_id',
    );
  }

  Stream<List<Map<String, dynamic>>> streamUsersPresence(
    List<String> userIds,
  ) {
    if (userIds.isEmpty) {
      return Stream.value(const <Map<String, dynamic>>[]);
    }

    return supabase
        .from('user_presence')
        .stream(primaryKey: ['user_id'])
        .inFilter('user_id', userIds)
        .map((rows) => rows
            .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e))
            .toList());
  }

  Future<void> setTypingStatus({
    required String roomId,
    required bool isTyping,
  }) async {
    final userId = currentUserId;
    if (userId == null) return;

    await supabase.from('chat_typing_status').upsert(
      {
        'room_id': roomId,
        'user_id': userId,
        'is_typing': isTyping,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      onConflict: 'room_id,user_id',
    );
  }

  Stream<List<Map<String, dynamic>>> streamTypingStatus(String roomId) {
    return supabase
        .from('chat_typing_status')
        .stream(primaryKey: ['room_id', 'user_id'])
        .eq('room_id', roomId)
        .map((rows) => rows
            .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e))
            .toList());
  }

  Future<void> _sendPushToRoomParticipants({
    required String roomId,
    required String senderId,
    required String content,
  }) async {
    try {
      final memberRows = await supabase
          .from('chat_room_members')
          .select('user_id')
          .eq('room_id', roomId)
          .eq('is_banned', false);

      final recipientIds = memberRows
          .map<String>((row) => (row['user_id'] ?? '').toString())
          .where((id) => id.isNotEmpty && id != senderId)
          .toSet()
          .toList();

      if (recipientIds.isEmpty) return;

      final senderProfile = await supabase
          .from('profiles')
          .select('full_name')
          .eq('id', senderId)
          .maybeSingle();

      final senderName =
          senderProfile?['full_name']?.toString().trim().isNotEmpty == true
              ? senderProfile!['full_name'].toString().trim()
              : 'Olympus Chat';

      final tokenRows = await supabase
          .from('user_push_tokens')
          .select('user_id, device_token')
          .inFilter('user_id', recipientIds);

      final tokens = <String>{};
      for (final row in tokenRows) {
        final token = row['device_token']?.toString().trim();
        if (token != null && token.isNotEmpty) tokens.add(token);
      }

      if (tokens.isEmpty) return;

      final preview =
          content.length > 90 ? '${content.substring(0, 90)}...' : content;
      final collapseId = 'chat_$roomId';
      final notificationId = _stableNotificationId(collapseId);

      for (final token in tokens) {
        await supabase.functions.invoke(
          'send-push-notification',
          body: {
            'token': token,
            'title': senderName,
            'body': preview,
            'type': 'message',
            'notification_type': 'chat_message',
            'screen': 'chat',
            'route': '/chat-rooms',
            'tag': collapseId,
            'androidTag': collapseId,
            'android_tag': collapseId,
            'collapseKey': collapseId,
            'collapse_key': collapseId,
            'collapseId': collapseId,
            'collapse_id': collapseId,
            'groupKey': collapseId,
            'group_key': collapseId,
            'notificationId': notificationId,
            'notification_id': notificationId,
            'localNotificationId': notificationId,
            'local_notification_id': notificationId,
            'androidNotificationId': notificationId,
            'android_notification_id': notificationId,
            'replaceId': notificationId,
            'replace_id': notificationId,
            'roomId': roomId,
            'room_id': roomId,
            'threadId': roomId,
            'thread_id': roomId,
            'senderId': senderId,
            'senderName': senderName,
            'data': {
              'type': 'message',
              'screen': 'chat',
              'route': '/chat-rooms',
              'roomId': roomId,
              'room_id': roomId,
              'tag': collapseId,
              'collapse_key': collapseId,
              'notificationId': notificationId.toString(),
              'notification_id': notificationId.toString(),
              'local_notification_id': notificationId.toString(),
            },
          },
        );
      }
    } catch (e, st) {
      debugPrint('[ChatService] Push de chat não enviado: $e');
      debugPrintStack(stackTrace: st);
    }
  }
}
