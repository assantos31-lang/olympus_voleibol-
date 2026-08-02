import 'package:supabase_flutter/supabase_flutter.dart';

class AppMessageService {
  AppMessageService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Future<Map<String, Map<String, dynamic>>> loadLatestMessagesByThread(
    Iterable<String> threadIds,
  ) async {
    final uniqueThreadIds = threadIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList(growable: false);

    if (uniqueThreadIds.isEmpty) {
      return <String, Map<String, dynamic>>{};
    }

    // Busca um conjunto limitado de mensagens recentes em uma única chamada.
    // A tela usa o preview da thread quando uma conversa antiga não estiver
    // neste conjunto, evitando o padrão de uma consulta por conversa.
    final fetchLimit = (uniqueThreadIds.length * 8).clamp(80, 800).toInt();
    final response = await _client
        .from('app_messages')
        .select('thread_id, body, sender_name, sender_type, created_at')
        .inFilter('thread_id', uniqueThreadIds)
        .order('created_at', ascending: false)
        .limit(fetchLimit);

    final latestByThread = <String, Map<String, dynamic>>{};
    for (final row in List<Map<String, dynamic>>.from(response)) {
      final threadId = (row['thread_id'] ?? '').toString();
      if (threadId.isEmpty || latestByThread.containsKey(threadId)) continue;
      latestByThread[threadId] = row;
    }

    return latestByThread;
  }

  Future<void> deleteMessageForEveryone({
    required String threadId,
    required String messageId,
    bool allowAnySender = false,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) throw Exception('Usuário não autenticado.');
    if (threadId.trim().isEmpty || messageId.trim().isEmpty) {
      throw Exception('Mensagem inválida.');
    }

    dynamic deleteQuery =
        _client.from('app_messages').delete().eq('id', messageId);
    if (!allowAnySender) {
      deleteQuery = deleteQuery.eq('sender_id', user.id);
    }

    final deletedRows = await deleteQuery.select('id');
    if (deletedRows is! List || deletedRows.isEmpty) {
      throw Exception('Você não tem permissão para excluir esta mensagem.');
    }

    final lastMessages = await _client
        .from('app_messages')
        .select('body, created_at')
        .eq('thread_id', threadId)
        .order('created_at', ascending: false)
        .limit(1);
    final rows = List<Map<String, dynamic>>.from(lastMessages);

    if (rows.isEmpty) {
      final thread = await _client
          .from('app_message_threads')
          .select('created_at')
          .eq('id', threadId)
          .maybeSingle();
      await _client.from('app_message_threads').update({
        'preview': '',
        'last_message_at': thread?['created_at'],
      }).eq('id', threadId);
      return;
    }

    final lastMessage = rows.first;
    await _client.from('app_message_threads').update({
      'preview': _buildPreview((lastMessage['body'] ?? '').toString()),
      'last_message_at': lastMessage['created_at'],
    }).eq('id', threadId);
  }

  String _buildPreview(String body) {
    final normalized = body.replaceAll('\n', ' ').trim();
    if (normalized.length <= 120) return normalized;
    return '${normalized.substring(0, 120)}...';
  }
}
