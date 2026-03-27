import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AthleteMessagesPage extends StatefulWidget {
  const AthleteMessagesPage({super.key});

  @override
  State<AthleteMessagesPage> createState() => _AthleteMessagesPageState();
}

class _AthleteMessagesPageState extends State<AthleteMessagesPage> {
  final SupabaseClient supabase = Supabase.instance.client;

  bool _loading = true;
  bool _refreshing = false;
  List<Map<String, dynamic>> _threads = [];
  RealtimeChannel? _threadsChannel;
  RealtimeChannel? _messagesChannel;

  String? _debugUserId;
  String? _debugUserEmail;
  String? _debugMessage;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await _loadThreads(showLoader: true);
    _setupRealtime();
  }

  @override
  void dispose() {
    if (_threadsChannel != null) {
      supabase.removeChannel(_threadsChannel!);
    }
    if (_messagesChannel != null) {
      supabase.removeChannel(_messagesChannel!);
    }
    super.dispose();
  }

  User? _currentUser() {
    return supabase.auth.currentSession?.user ?? supabase.auth.currentUser;
  }

  void _setupRealtime() {
    final user = _currentUser();
    if (user == null) return;

    _threadsChannel =
        supabase.channel('athlete-message-participants-${user.id}')
          ..onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'app_message_participants',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'user_id',
              value: user.id,
            ),
            callback: (_) {
              _loadThreads(showLoader: false);
            },
          )
          ..subscribe();

    _messagesChannel = supabase.channel('athlete-messages-${user.id}')
      ..onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'app_messages',
        callback: (_) {
          _loadThreads(showLoader: false);
        },
      )
      ..subscribe();
  }

  Future<void> _loadThreads({required bool showLoader}) async {
    final user = _currentUser();

    if (mounted) {
      setState(() {
        _debugUserId = user?.id;
        _debugUserEmail = user?.email;
        _debugMessage = null;
      });
    }

    if (user == null) {
      if (mounted) {
        setState(() {
          _loading = false;
          _refreshing = false;
          _threads = [];
          _debugMessage = 'Nenhum usuário autenticado encontrado.';
        });
      }
      return;
    }

    debugPrint('AthleteMessagesPage user.id=${user.id} email=${user.email}');

    if (mounted) {
      setState(() {
        if (showLoader) {
          _loading = true;
        } else {
          _refreshing = true;
        }
      });
    }

    try {
      final participantResponse = await supabase
          .from('app_message_participants')
          .select('thread_id, unread_count, last_read_at, is_admin_sender')
          .eq('user_id', user.id);

      final participantRows =
          List<Map<String, dynamic>>.from(participantResponse);

      debugPrint(
        'AthleteMessagesPage participants for ${user.id}: ${participantRows.length}',
      );

      if (participantRows.isEmpty) {
        if (!mounted) return;
        setState(() {
          _threads = [];
          _debugMessage =
              'Nenhum vínculo encontrado em app_message_participants para o usuário logado.';
        });
        return;
      }

      final threadIds = participantRows
          .map((row) => (row['thread_id'] ?? '').toString())
          .where((id) => id.isNotEmpty)
          .toList();

      if (threadIds.isEmpty) {
        if (!mounted) return;
        setState(() {
          _threads = [];
          _debugMessage =
              'Os participantes encontrados não possuem thread_id válido.';
        });
        return;
      }

      final threadsResponse = await supabase
          .from('app_message_threads')
          .select(
            'id, subject, preview, created_at, last_message_at, allow_reply, '
            'created_by, created_by_name, created_by_type, target_mode, target_user_type',
          )
          .inFilter('id', threadIds);

      final threadRows = List<Map<String, dynamic>>.from(threadsResponse);
      debugPrint(
        'AthleteMessagesPage threads for ${user.id}: ${threadRows.length}',
      );

      final threadsById = <String, Map<String, dynamic>>{};
      for (final thread in threadRows) {
        final id = (thread['id'] ?? '').toString();
        if (id.isNotEmpty) {
          threadsById[id] = thread;
        }
      }

      final loadedThreads = <Map<String, dynamic>>[];

      for (final participant in participantRows) {
        final threadId = (participant['thread_id'] ?? '').toString();
        if (threadId.isEmpty) continue;

        final thread = Map<String, dynamic>.from(
          threadsById[threadId] ?? const {},
        );
        if (thread.isEmpty) continue;

        final lastMessageResponse = await supabase
            .from('app_messages')
            .select('body, sender_name, sender_type, created_at')
            .eq('thread_id', threadId)
            .order('created_at', ascending: false)
            .limit(1)
            .maybeSingle();

        loadedThreads.add({
          ...thread,
          'thread_id': threadId,
          'unread_count': participant['unread_count'] ?? 0,
          'last_read_at': participant['last_read_at'],
          'is_admin_sender': participant['is_admin_sender'],
          'last_message': lastMessageResponse,
        });
      }

      loadedThreads.sort((a, b) {
        final aDate = DateTime.tryParse(
              (a['last_message_at'] ?? a['created_at'] ?? '').toString(),
            ) ??
            DateTime.fromMillisecondsSinceEpoch(0);
        final bDate = DateTime.tryParse(
              (b['last_message_at'] ?? b['created_at'] ?? '').toString(),
            ) ??
            DateTime.fromMillisecondsSinceEpoch(0);
        return bDate.compareTo(aDate);
      });

      if (!mounted) return;
      setState(() {
        _threads = loadedThreads;
        if (loadedThreads.isEmpty) {
          _debugMessage =
              'Participantes encontrados, mas nenhuma thread retornou da app_message_threads.';
        }
      });
    } catch (e) {
      _showSnack('Erro ao carregar mensagens: $e');
      if (mounted) {
        setState(() {
          _debugMessage = 'Erro ao carregar mensagens: $e';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _refreshing = false;
        });
      }
    }
  }

  Future<void> _openThread(Map<String, dynamic> thread) async {
    final threadId = (thread['thread_id'] ?? thread['id'] ?? '').toString();
    if (threadId.isEmpty) return;

    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => AthleteMessageThreadPage(
          threadId: threadId,
          subject: (thread['subject'] ?? 'Mensagem').toString(),
          allowReply: thread['allow_reply'] == true,
        ),
      ),
    );

    if (result == true) {
      await _loadThreads(showLoader: false);
    }
  }

  String _formatDateTime(dynamic value) {
    final date = DateTime.tryParse((value ?? '').toString())?.toLocal();
    if (date == null) return '';
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    final year = date.year.toString();
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');
    return '$day/$month/$year $hour:$minute';
  }

  String _threadSubtitle(Map<String, dynamic> thread) {
    final lastMessage = Map<String, dynamic>.from(
      (thread['last_message'] as Map?) ?? const {},
    );

    final senderName = (lastMessage['sender_name'] ?? '').toString().trim();
    final body =
        (lastMessage['body'] ?? thread['preview'] ?? '').toString().trim();
    final createdAt = _formatDateTime(
      lastMessage['created_at'] ??
          thread['last_message_at'] ??
          thread['created_at'],
    );

    final parts = <String>[];
    if (senderName.isNotEmpty) {
      parts.add(senderName);
    }
    if (body.isNotEmpty) {
      parts.add(body);
    }
    if (createdAt.isNotEmpty) {
      parts.add(createdAt);
    }

    return parts.join(' • ');
  }

  Widget _buildDebugCard() {
    if (_debugUserId == null &&
        _debugUserEmail == null &&
        (_debugMessage == null || _debugMessage!.isEmpty)) {
      return const SizedBox.shrink();
    }

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: DefaultTextStyle(
          style: const TextStyle(fontSize: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Diagnóstico',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              if (_debugUserId != null) Text('user.id: $_debugUserId'),
              if (_debugUserEmail != null) Text('email: $_debugUserEmail'),
              if (_debugMessage != null && _debugMessage!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(_debugMessage!),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _showSnack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final content = _loading
        ? const Center(child: CircularProgressIndicator())
        : _threads.isEmpty
            ? RefreshIndicator(
                onRefresh: () => _loadThreads(showLoader: false),
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: [
                    _buildDebugCard(),
                    const SizedBox(height: 96),
                    const Icon(Icons.mark_chat_unread_outlined, size: 56),
                    const SizedBox(height: 12),
                    const Center(
                      child: Text('Nenhuma mensagem encontrada.'),
                    ),
                  ],
                ),
              )
            : RefreshIndicator(
                onRefresh: () => _loadThreads(showLoader: false),
                child: ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: _threads.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final thread = _threads[index];
                    final unreadCount = (thread['unread_count'] ?? 0) as int;
                    final subject =
                        (thread['subject'] ?? 'Mensagem').toString();
                    final subtitle = _threadSubtitle(thread);

                    return Card(
                      child: ListTile(
                        onTap: () => _openThread(thread),
                        title: Text(
                          subject,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight: unreadCount > 0
                                ? FontWeight.w700
                                : FontWeight.w500,
                          ),
                        ),
                        subtitle: subtitle.isEmpty
                            ? null
                            : Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  subtitle,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                        trailing: unreadCount > 0
                            ? CircleAvatar(
                                radius: 14,
                                child: Text(
                                  unreadCount > 99 ? '99+' : '$unreadCount',
                                  style: const TextStyle(fontSize: 11),
                                ),
                              )
                            : const Icon(Icons.chevron_right),
                      ),
                    );
                  },
                ),
              );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mensagens'),
        actions: [
          IconButton(
            tooltip: 'Atualizar',
            onPressed:
                _refreshing ? null : () => _loadThreads(showLoader: false),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: content,
    );
  }
}

class AthleteMessageThreadPage extends StatefulWidget {
  final String threadId;
  final String subject;
  final bool allowReply;

  const AthleteMessageThreadPage({
    super.key,
    required this.threadId,
    required this.subject,
    required this.allowReply,
  });

  @override
  State<AthleteMessageThreadPage> createState() =>
      _AthleteMessageThreadPageState();
}

class _AthleteMessageThreadPageState extends State<AthleteMessageThreadPage> {
  final SupabaseClient supabase = Supabase.instance.client;
  final TextEditingController _replyController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  bool _loading = true;
  bool _sending = false;
  List<Map<String, dynamic>> _messages = [];
  RealtimeChannel? _threadChannel;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await _markThreadAsRead();
    await _loadMessages();
    _setupRealtime();
  }

  @override
  void dispose() {
    _replyController.dispose();
    _scrollController.dispose();
    if (_threadChannel != null) {
      supabase.removeChannel(_threadChannel!);
    }
    super.dispose();
  }

  User? _currentUser() {
    return supabase.auth.currentSession?.user ?? supabase.auth.currentUser;
  }

  void _setupRealtime() {
    _threadChannel = supabase.channel('thread-${widget.threadId}')
      ..onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'app_messages',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'thread_id',
          value: widget.threadId,
        ),
        callback: (_) async {
          await _markThreadAsRead();
          await _loadMessages();
        },
      )
      ..subscribe();
  }

  Future<void> _markThreadAsRead() async {
    final user = _currentUser();
    if (user == null) return;

    await supabase
        .from('app_message_participants')
        .update({
          'unread_count': 0,
          'last_read_at': DateTime.now().toIso8601String(),
        })
        .eq('thread_id', widget.threadId)
        .eq('user_id', user.id);
  }

  Future<void> _loadMessages() async {
    try {
      final response = await supabase
          .from('app_messages')
          .select('id, sender_id, sender_name, sender_type, body, created_at')
          .eq('thread_id', widget.threadId)
          .order('created_at', ascending: true);

      if (!mounted) return;
      setState(() {
        _messages = List<Map<String, dynamic>>.from(response);
        _loading = false;
      });

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
        }
      });
    } catch (e) {
      _showSnack('Erro ao carregar conversa: $e');
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<Map<String, dynamic>?> _loadSenderProfile(String userId) async {
    try {
      final userProfiles = await supabase
          .from('user_profiles')
          .select('full_name, role')
          .eq('id', userId)
          .maybeSingle();

      if (userProfiles != null) {
        return {
          'full_name': userProfiles['full_name'],
          'user_type': userProfiles['role'],
        };
      }
    } catch (_) {}

    try {
      final profiles = await supabase
          .from('profiles')
          .select('full_name, user_type')
          .eq('id', userId)
          .maybeSingle();

      if (profiles != null) {
        return {
          'full_name': profiles['full_name'],
          'user_type': profiles['user_type'],
        };
      }
    } catch (_) {}

    return null;
  }

  Future<void> _sendReply() async {
    final user = _currentUser();
    if (user == null) {
      _showSnack('Usuário não autenticado.');
      return;
    }

    final body = _replyController.text.trim();
    if (body.isEmpty) {
      _showSnack('Digite uma mensagem.');
      return;
    }

    setState(() => _sending = true);

    try {
      final profile = await _loadSenderProfile(user.id);

      final senderName = (profile?['full_name'] ?? 'Usuário').toString();
      final senderType = (profile?['user_type'] ?? 'athlete').toString();
      final now = DateTime.now().toIso8601String();

      await supabase.from('app_messages').insert({
        'thread_id': widget.threadId,
        'sender_id': user.id,
        'sender_name': senderName,
        'sender_type': senderType,
        'body': body,
        'created_at': now,
      });

      await supabase.from('app_message_threads').update({
        'last_message_at': now,
        'preview': _buildPreview(body),
      }).eq('id', widget.threadId);

      final participants = await supabase
          .from('app_message_participants')
          .select('user_id, unread_count')
          .eq('thread_id', widget.threadId);

      for (final row in List<Map<String, dynamic>>.from(participants)) {
        final participantId = (row['user_id'] ?? '').toString();
        if (participantId.isEmpty || participantId == user.id) continue;

        final currentUnread = (row['unread_count'] ?? 0) as int;

        await supabase
            .from('app_message_participants')
            .update({'unread_count': currentUnread + 1})
            .eq('thread_id', widget.threadId)
            .eq('user_id', participantId);
      }

      _replyController.clear();
      await _markThreadAsRead();
      await _loadMessages();

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      _showSnack('Erro ao enviar resposta: $e');
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
    }
  }

  String _buildPreview(String body) {
    final normalized = body.replaceAll('\n', ' ').trim();
    if (normalized.length <= 120) return normalized;
    return '${normalized.substring(0, 120)}...';
  }

  bool _isCurrentUser(Map<String, dynamic> message) {
    final user = _currentUser();
    if (user == null) return false;
    return (message['sender_id'] ?? '').toString() == user.id;
  }

  String _formatDateTime(dynamic value) {
    final date = DateTime.tryParse((value ?? '').toString())?.toLocal();
    if (date == null) return '';
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');
    return '$day/$month $hour:$minute';
  }

  void _showSnack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.subject),
      ),
      body: Column(
        children: [
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _messages.isEmpty
                    ? const Center(
                        child: Text('Nenhuma mensagem nesta conversa.'),
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.all(12),
                        itemCount: _messages.length,
                        itemBuilder: (context, index) {
                          final message = _messages[index];
                          final isMine = _isCurrentUser(message);
                          final senderName =
                              (message['sender_name'] ?? '').toString().trim();
                          final body = (message['body'] ?? '').toString();
                          final createdAt =
                              _formatDateTime(message['created_at']);

                          return Align(
                            alignment: isMine
                                ? Alignment.centerRight
                                : Alignment.centerLeft,
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                maxWidth:
                                    MediaQuery.of(context).size.width * 0.82,
                              ),
                              child: Card(
                                color: isMine
                                    ? Theme.of(context)
                                        .colorScheme
                                        .primaryContainer
                                    : null,
                                margin: const EdgeInsets.only(bottom: 10),
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        senderName.isEmpty
                                            ? (isMine
                                                ? 'Você'
                                                : 'Administrador')
                                            : (isMine ? 'Você' : senderName),
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(body),
                                      if (createdAt.isNotEmpty) ...[
                                        const SizedBox(height: 8),
                                        Text(
                                          createdAt,
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall,
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
          ),
          if (widget.allowReply)
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _replyController,
                        minLines: 1,
                        maxLines: 4,
                        decoration: const InputDecoration(
                          hintText: 'Digite sua resposta',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      height: 50,
                      child: FilledButton(
                        onPressed: _sending ? null : _sendReply,
                        child: _sending
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.send),
                      ),
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
