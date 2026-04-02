import 'package:supabase_flutter/supabase_flutter.dart';

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

    try {
      await _supabase.functions.invoke(
        'send-push-notification',
        body: {
          'type': 'chat',
          'room_id': roomId,
          'sender_id': senderId,
          'content': content,
        },
      );
    } catch (e) {
      print('Erro ao enviar push de chat: $e');
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
