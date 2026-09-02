import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'organization_context_service.dart';

class MessagingService {
  final SupabaseClient _supabase = Supabase.instance.client;

  Future<void> sendMessage({
    required String roomId,
    required String senderId,
    required String content,
  }) async {
    await _supabase.from('messages').insert({
      'room_id': roomId,
      'sender_id': senderId,
      'content': content,
      'created_at': DateTime.now().toIso8601String(),
    });

    await _sendPushToRoomParticipants(
      roomId: roomId,
      senderId: senderId,
      content: content,
    );
  }

  Future<void> _sendPushToRoomParticipants({
    required String roomId,
    required String senderId,
    required String content,
  }) async {
    try {
      final room = await _supabase
          .from('chat_rooms')
          .select('participants')
          .eq('id', roomId)
          .maybeSingle();

      final participantsRaw = room?['participants'];

      if (participantsRaw is! List) {
        debugPrint('[MessagingService] Sala sem participants');
        return;
      }

      final recipientIds = participantsRaw
          .map((item) => item.toString())
          .where((id) => id.isNotEmpty && id != senderId)
          .toList();

      if (recipientIds.isEmpty) {
        debugPrint('[MessagingService] Sem destinatarios para push');
        return;
      }

      final senderProfile = await _supabase
          .from('profiles')
          .select('full_name')
          .eq('id', senderId)
          .maybeSingle();

      final senderName =
          senderProfile?['full_name']?.toString().trim().isNotEmpty == true
              ? senderProfile!['full_name'].toString().trim()
              : OrganizationContextService.instance.currentName;

      final tokenRows = await _supabase
          .from('user_push_tokens')
          .select('user_id, device_token')
          .inFilter('user_id', recipientIds);

      final tokens = <String>{};

      for (final row in tokenRows) {
        final token = row['device_token']?.toString().trim();

        if (token != null && token.isNotEmpty) {
          tokens.add(token);
        }
      }

      if (tokens.isEmpty) {
        debugPrint('[MessagingService] Nenhum device_token encontrado');
        return;
      }

      // Não expõe o conteúdo da conversa na tela bloqueada.
      const preview = 'Nova mensagem';

      for (final token in tokens) {
        await _supabase.functions.invoke(
          'send-push-notification',
          body: {
            'token': token,
            'title': senderName,
            'body': preview,
            'type': 'message',
            'threadId': roomId,
            'senderId': senderId,
            'senderName': senderName,
          },
        );
      }

      debugPrint(
          '[MessagingService] Push enviado para ${tokens.length} tokens');
    } catch (e, st) {
      debugPrint('[MessagingService] Erro ao enviar push de chat: $e');
      debugPrintStack(stackTrace: st);
    }
  }

  Stream<List<Map<String, dynamic>>> streamMessages(String roomId) {
    return _supabase
        .from('messages')
        .stream(primaryKey: ['id'])
        .eq('room_id', roomId)
        .order('created_at');
  }

  Future<List<Map<String, dynamic>>> fetchMessages(String roomId) async {
    final response = await _supabase
        .from('messages')
        .select()
        .eq('room_id', roomId)
        .order('created_at');

    return List<Map<String, dynamic>>.from(response);
  }

  Future<String> createRoom({
    required List<String> participants,
  }) async {
    final response = await _supabase
        .from('chat_rooms')
        .insert({
          'participants': participants,
          'created_at': DateTime.now().toIso8601String(),
        })
        .select()
        .single();

    return response['id'].toString();
  }

  Future<List<Map<String, dynamic>>> getUserRooms(String userId) async {
    final response = await _supabase
        .from('chat_rooms')
        .select()
        .contains('participants', [userId]);

    return List<Map<String, dynamic>>.from(response);
  }
}
