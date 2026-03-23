import 'dart:developer' as developer;

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/app_message.dart';

class MessagingService {
  final SupabaseClient _supabase = Supabase.instance.client;

  static const String threadsTable = 'app_message_threads';
  static const String participantsTable = 'app_message_participants';
  static const String messagesTable = 'app_messages';

  void _log(String message, [Object? data]) {
    final text = data == null ? message : '$message => $data';
    developer.log(text, name: 'MessagingService');
    // ignore: avoid_print
    print(text);
  }

  Future<Map<String, dynamic>?> getMyProfile() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return null;

    return await _supabase
        .from('profiles')
        .select('id, full_name, email, user_type, avatar_url')
        .eq('id', user.id)
        .maybeSingle();
  }

  Future<List<MessageRecipientOption>> searchRecipients({
    String query = '',
    String userType = 'all',
  }) async {
    dynamic request = _supabase
        .from('profiles')
        .select('id, full_name, email, user_type, avatar_url')
        .neq('user_type', 'admin');

    if (userType != 'all') {
      request = request.eq('user_type', userType);
    }

    final response = await request.order('full_name');
    final q = query.toLowerCase().trim();

    return (response as List)
        .map((e) => MessageRecipientOption.fromMap(e as Map<String, dynamic>))
        .where((e) {
      if (q.isEmpty) return true;
      return e.fullName.toLowerCase().contains(q) ||
          e.email.toLowerCase().contains(q);
    }).toList();
  }

  Future<List<AppMessageThread>> getInboxThreads() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return [];

    final participants = await _supabase
        .from(participantsTable)
        .select('thread_id, unread_count')
        .eq('user_id', user.id);

    if ((participants as List).isEmpty) return [];

    final unreadByThread = <String, int>{};
    final threadIds = <String>[];

    for (final row in participants) {
      final id = (row['thread_id'] ?? '').toString();
      if (id.isEmpty) continue;
      threadIds.add(id);
      unreadByThread[id] =
          int.tryParse((row['unread_count'] ?? 0).toString()) ?? 0;
    }

    final threads = await _supabase
        .from(threadsTable)
        .select('*')
        .inFilter('id', threadIds)
        .order('last_message_at', ascending: false);

    return (threads as List).map((e) {
      final map = Map<String, dynamic>.from(e as Map<String, dynamic>);
      map['unread_count'] = unreadByThread[(map['id'] ?? '').toString()] ?? 0;
      return AppMessageThread.fromMap(map);
    }).toList();
  }

  Future<List<AppMessageThread>> getAdminCreatedThreads() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return [];

    final threads = await _supabase
        .from(threadsTable)
        .select('*')
        .eq('created_by', user.id)
        .order('last_message_at', ascending: false);

    return (threads as List)
        .map((e) => AppMessageThread.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<AppMessageItem>> getThreadMessages(String threadId) async {
    final response = await _supabase
        .from(messagesTable)
        .select('*')
        .eq('thread_id', threadId)
        .order('created_at');

    return (response as List)
        .map((e) => AppMessageItem.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> markThreadAsRead(String threadId) async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    await _supabase
        .from(participantsTable)
        .update({
          'unread_count': 0,
          'last_read_at': DateTime.now().toIso8601String(),
        })
        .eq('thread_id', threadId)
        .eq('user_id', user.id);
  }

  Future<void> sendReply({
    required String threadId,
    required String body,
  }) async {
    final me = await getMyProfile();
    if (me == null) throw Exception('Usuário não autenticado');

    final now = DateTime.now().toIso8601String();
    final myUserId = (me['id'] ?? '').toString();

    await _supabase.from(messagesTable).insert({
      'thread_id': threadId,
      'sender_id': me['id'],
      'sender_name': me['full_name'] ?? '',
      'sender_type': me['user_type'] ?? '',
      'body': body.trim(),
      'created_at': now,
    });

    await _supabase.from(threadsTable).update({
      'last_message_at': now,
      'preview': body.trim(),
    }).eq('id', threadId);

    final participants = await _supabase
        .from(participantsTable)
        .select('id, user_id, unread_count')
        .eq('thread_id', threadId);

    for (final row in (participants as List)) {
      final participantUserId = (row['user_id'] ?? '').toString();
      if (participantUserId == myUserId) {
        await _supabase.from(participantsTable).update({
          'last_read_at': now,
          'unread_count': 0,
        }).eq('id', row['id']);
      } else {
        final currentUnread =
            int.tryParse((row['unread_count'] ?? 0).toString()) ?? 0;
        await _supabase.from(participantsTable).update({
          'unread_count': currentUnread + 1,
        }).eq('id', row['id']);
      }
    }

    final rawRecipientIds = (participants as List)
        .map((e) => (e['user_id'] ?? '').toString())
        .toList();

    final recipientIds = _sanitizeRecipientIds(
      rawRecipientIds,
      excludeUserId: myUserId,
    );

    _log('sendReply raw recipients', rawRecipientIds);
    _log('sendReply sanitized recipients', recipientIds);

    try {
      await _sendPushForThread(
        recipientUserIds: recipientIds,
        title: 'Nova resposta',
        body: body.trim(),
        threadId: threadId,
      );
    } on FunctionException catch (e, stackTrace) {
      developer.log(
        'Falha no push após sendReply. A mensagem foi salva normalmente.',
        name: 'MessagingService',
        error: e,
        stackTrace: stackTrace,
      );
      _log('PUSH FUNCTION EXCEPTION EM sendReply', {
        'status': e.status,
        'details': e.details,
      });
    } catch (e, stackTrace) {
      developer.log(
        'Falha no push após sendReply. A mensagem foi salva normalmente.',
        name: 'MessagingService',
        error: e,
        stackTrace: stackTrace,
      );
      _log('PUSH FALHOU EM sendReply, mas a mensagem foi salva', e);
    }
  }

  Future<void> createThreadAndSend({
    required String subject,
    required String body,
    required bool allowReply,
    required String targetMode,
    required String targetUserType,
    required List<String> selectedUserIds,
  }) async {
    final me = await getMyProfile();
    if (me == null) throw Exception('Usuário não autenticado');

    final now = DateTime.now().toIso8601String();
    final myUserId = (me['id'] ?? '').toString();

    final rawRecipientIds = await _resolveRecipients(
      targetMode: targetMode,
      targetUserType: targetUserType,
      selectedUserIds: selectedUserIds,
    );

    final recipientIds = _sanitizeRecipientIds(
      rawRecipientIds,
      excludeUserId: myUserId,
    );

    _log('createThreadAndSend raw recipients', rawRecipientIds);
    _log('createThreadAndSend sanitized recipients', recipientIds);

    final insertedThread = await _supabase
        .from(threadsTable)
        .insert({
          'subject': subject.trim(),
          'created_by': me['id'],
          'created_by_name': me['full_name'] ?? '',
          'created_by_type': me['user_type'] ?? '',
          'allow_reply': allowReply,
          'created_at': now,
          'last_message_at': now,
          'target_mode': targetMode,
          'target_user_type': targetUserType,
          'preview': body.trim(),
        })
        .select('id')
        .single();

    final threadId = insertedThread['id'].toString();

    await _supabase.from(messagesTable).insert({
      'thread_id': threadId,
      'sender_id': me['id'],
      'sender_name': me['full_name'] ?? '',
      'sender_type': me['user_type'] ?? '',
      'body': body.trim(),
      'created_at': now,
    });

    final rows = <Map<String, dynamic>>[
      {
        'thread_id': threadId,
        'user_id': me['id'],
        'is_admin_sender': true,
        'unread_count': 0,
        'last_read_at': now,
      },
      ...recipientIds.map(
        (id) => {
          'thread_id': threadId,
          'user_id': id,
          'is_admin_sender': false,
          'unread_count': 1,
        },
      ),
    ];

    await _supabase.from(participantsTable).insert(rows);

    try {
      await _sendPushForThread(
        recipientUserIds: recipientIds,
        title: subject.trim(),
        body: body.trim(),
        threadId: threadId,
      );
    } on FunctionException catch (e, stackTrace) {
      developer.log(
        'Falha no push após createThreadAndSend. A thread foi salva normalmente.',
        name: 'MessagingService',
        error: e,
        stackTrace: stackTrace,
      );
      _log('PUSH FUNCTION EXCEPTION EM createThreadAndSend', {
        'status': e.status,
        'details': e.details,
      });
    } catch (e, stackTrace) {
      developer.log(
        'Falha no push após createThreadAndSend. A thread foi salva normalmente.',
        name: 'MessagingService',
        error: e,
        stackTrace: stackTrace,
      );
      _log('PUSH FALHOU EM createThreadAndSend, mas a thread foi salva', e);
    }
  }

  Future<void> _sendPushForThread({
    required List<String> recipientUserIds,
    required String title,
    required String body,
    required String threadId,
  }) async {
    final currentUser = _supabase.auth.currentUser;

    final uniqueRecipients = _sanitizeRecipientIds(
      recipientUserIds,
      excludeUserId: currentUser?.id,
    );

    _log('PUSH DEBUG START');
    _log('Function name', 'send-push-notification');
    _log('Current user id', currentUser?.id);
    _log('Recipients received by _sendPushForThread', recipientUserIds);
    _log('Recipients sanitized for invoke', uniqueRecipients);
    _log('Thread id', threadId);

    if (uniqueRecipients.isEmpty) {
      _log('PUSH CANCELADO: lista de destinatários vazia após sanitização');
      return;
    }

    final payload = {
      'recipientUserIds': uniqueRecipients,
      'recipient_user_ids': uniqueRecipients,
      'title': title.trim(),
      'body': body.trim(),
      'threadId': threadId.trim(),
      'thread_id': threadId.trim(),
      'click_action': 'OPEN_THREAD',
    };

    _log('Function payload', payload);

    try {
      final response = await _supabase.functions.invoke(
        'send-push-notification',
        body: payload,
      );

      _log('Function status', response.status);
      _log('Function data', response.data);

      if (response.status == null) {
        throw Exception('Edge Function sem status HTTP na resposta');
      }

      if (response.status! < 200 || response.status! >= 300) {
        throw Exception(
          'Edge Function retornou status ${response.status}: ${response.data}',
        );
      }
    } on FunctionException catch (e) {
      _log('FunctionException status', e.status);
      _log('FunctionException details', e.details);
      rethrow;
    }
  }

  List<String> _sanitizeRecipientIds(
    List<String> ids, {
    String? excludeUserId,
  }) {
    final exclude = (excludeUserId ?? '').trim();

    return ids
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .where((e) => e != 'null')
        .where((e) => e != exclude)
        .toSet()
        .toList();
  }

  Future<List<String>> _resolveRecipients({
    required String targetMode,
    required String targetUserType,
    required List<String> selectedUserIds,
  }) async {
    switch (targetMode) {
      case 'single':
      case 'multiple':
        return selectedUserIds
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .where((e) => e != 'null')
            .toSet()
            .toList();

      case 'all':
        final response = await _supabase
            .from('profiles')
            .select('id')
            .neq('user_type', 'admin');

        return (response as List)
            .map((e) => (e['id'] ?? '').toString())
            .toList();

      case 'by_role':
        final response = await _supabase
            .from('profiles')
            .select('id')
            .eq('user_type', targetUserType);

        return (response as List)
            .map((e) => (e['id'] ?? '').toString())
            .toList();

      default:
        return [];
    }
  }
}
