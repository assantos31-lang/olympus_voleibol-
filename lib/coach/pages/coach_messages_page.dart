import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/badge_service.dart';
import '../../services/olympus_memory_cache.dart';
import 'coach_message_thread_page.dart';

export 'coach_message_thread_page.dart';

class CoachMessagesPage extends StatefulWidget {
  const CoachMessagesPage({super.key});

  @override
  State<CoachMessagesPage> createState() => _CoachMessagesPageState();
}

class _CoachMessagesPageState extends State<CoachMessagesPage> {
  final SupabaseClient supabase = Supabase.instance.client;
  static const Color olympusBlue = Color(0xFF1E3A5F);
  static const Color olympusGold = Color(0xFFD4AF37);
  static const Color olympusLightBlue = Color(0xFF2C5F8D);

  bool _loading = true;
  bool _refreshing = false;
  bool _loadInProgress = false;
  bool _openingThread = false;
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
    _restoreThreadsCache();
    await _loadThreads(showLoader: true);
    _setupRealtime();
  }

  String get _threadsCacheKey =>
      'coach_messages:${_currentUser()?.id ?? 'guest'}';

  void _restoreThreadsCache() {
    final cached = OlympusMemoryCache.read<List<Map<String, dynamic>>>(
      _threadsCacheKey,
    );
    if (cached == null || cached.isEmpty) return;
    setState(() {
      _threads = List<Map<String, dynamic>>.from(cached);
      _loading = false;
    });
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

    _threadsChannel = supabase.channel('coach-message-participants-${user.id}')
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

    _messagesChannel = supabase.channel('coach-messages-${user.id}')
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
    if (_loadInProgress) return;
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
    _loadInProgress = true;

    debugPrint('CoachMessagesPage user.id=${user.id} email=${user.email}');

    if (mounted) {
      setState(() {
        if (showLoader && _threads.isEmpty) {
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
        'CoachMessagesPage participants for ${user.id}: ${participantRows.length}',
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
        'CoachMessagesPage threads for ${user.id}: ${threadRows.length}',
      );

      final threadsById = <String, Map<String, dynamic>>{};
      for (final thread in threadRows) {
        final id = (thread['id'] ?? '').toString();
        if (id.isNotEmpty) {
          threadsById[id] = thread;
        }
      }

      final loadedThreads = <Map<String, dynamic>>[];
      final lastMessagesResponse = await supabase
          .from('app_messages')
          .select('thread_id, body, sender_name, sender_type, created_at')
          .inFilter('thread_id', threadIds)
          .order('created_at', ascending: false)
          .limit(500);
      final lastMessageByThread = <String, Map<String, dynamic>>{};
      for (final rawMessage in lastMessagesResponse) {
        final message = Map<String, dynamic>.from(rawMessage);
        final messageThreadId = (message['thread_id'] ?? '').toString();
        if (messageThreadId.isNotEmpty) {
          lastMessageByThread.putIfAbsent(messageThreadId, () => message);
        }
      }

      for (final participant in participantRows) {
        final threadId = (participant['thread_id'] ?? '').toString();
        if (threadId.isEmpty) continue;

        final thread = Map<String, dynamic>.from(
          threadsById[threadId] ?? const {},
        );
        if (thread.isEmpty) continue;

        loadedThreads.add({
          ...thread,
          'thread_id': threadId,
          'unread_count': participant['unread_count'] ?? 0,
          'last_read_at': participant['last_read_at'],
          'is_admin_sender': participant['is_admin_sender'],
          'last_message': lastMessageByThread[threadId],
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
      OlympusMemoryCache.write<List<Map<String, dynamic>>>(
        _threadsCacheKey,
        List<Map<String, dynamic>>.from(loadedThreads),
      );
      await BadgeService.updateBadge();
    } catch (e) {
      _showSnack('Erro ao carregar mensagens: $e');
      if (mounted) {
        setState(() {
          _debugMessage = 'Erro ao carregar mensagens: $e';
        });
      }
    } finally {
      _loadInProgress = false;
      if (mounted) {
        setState(() {
          _loading = false;
          _refreshing = false;
        });
      }
    }
  }

  Future<void> _openThread(Map<String, dynamic> thread) async {
    if (_openingThread) return;
    final threadId = (thread['thread_id'] ?? thread['id'] ?? '').toString();
    if (threadId.isEmpty) return;
    _openingThread = true;

    try {
      final updated = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => CoachMessageThreadPage(
            threadId: threadId,
            subject: (thread['subject'] ?? 'Mensagem').toString(),
            allowReply: thread['allow_reply'] == true,
          ),
        ),
      );

      if (updated == true && mounted) {
        setState(() {
          final index = _threads.indexWhere(
            (t) => (t['thread_id'] ?? t['id']).toString() == threadId,
          );

          if (index != -1) {
            _threads[index] = {
              ..._threads[index],
              'unread_count': 0,
            };
          }
        });
      }

      await _loadThreads(showLoader: false);
    } finally {
      _openingThread = false;
    }
  }

  Future<void> _deleteThreadForMe(Map<String, dynamic> thread) async {
    final user = _currentUser();
    final threadId = (thread['thread_id'] ?? thread['id'] ?? '').toString();
    if (user == null || threadId.isEmpty) return;

    final subject = (thread['subject'] ?? 'esta conversa').toString();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Excluir conversa'),
        content: Text(
          'Deseja excluir "$subject" da sua lista? '
          'Ela continuará disponível para os outros participantes.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).pop(true),
            icon: const Icon(Icons.delete_outline),
            label: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await supabase
          .from('app_message_participants')
          .delete()
          .eq('thread_id', threadId)
          .eq('user_id', user.id);
      if (!mounted) return;
      setState(() {
        _threads.removeWhere(
          (item) => (item['thread_id'] ?? item['id']).toString() == threadId,
        );
      });
      await BadgeService.updateBadge();
      _showSnack('Conversa excluída da sua lista.');
    } catch (e) {
      _showSnack('Erro ao excluir conversa: $e');
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

  Widget _buildPremiumBackground() {
    return Stack(
      children: [
        Positioned.fill(
          child: Image.asset(
            'assets/images/monte_olimpo_v2.png',
            fit: BoxFit.cover,
            alignment: Alignment.center,
            errorBuilder: (_, __, ___) {
              return Container(color: const Color(0xFF102845));
            },
          ),
        ),
        Positioned.fill(
          child: Container(
            color: Colors.black.withOpacity(0.22),
          ),
        ),
        Positioned.fill(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 1.5, sigmaY: 1.5),
            child: Container(color: Colors.transparent),
          ),
        ),
        Positioned.fill(
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  olympusBlue.withOpacity(0.54),
                  olympusLightBlue.withOpacity(0.22),
                  Colors.black.withOpacity(0.62),
                ],
              ),
            ),
          ),
        ),
        Positioned.fill(
          child: Container(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(0, -0.78),
                radius: 1.05,
                colors: [
                  olympusGold.withOpacity(0.14),
                  Colors.transparent,
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState(bool isCompact) {
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: isCompact ? 20 : 28,
          vertical: 24,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
            child: Container(
              width: double.infinity,
              constraints: const BoxConstraints(maxWidth: 540),
              padding: EdgeInsets.all(isCompact ? 20 : 24),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                gradient: LinearGradient(
                  colors: [
                    Colors.white.withOpacity(0.18),
                    Colors.white.withOpacity(0.10),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                border: Border.all(
                  color: Colors.white.withOpacity(0.24),
                  width: 1.1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.16),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: isCompact ? 64 : 76,
                    height: isCompact ? 64 : 76,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      color: Colors.white.withOpacity(0.10),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.18),
                      ),
                    ),
                    child: const Icon(
                      Icons.mark_chat_unread_outlined,
                      size: 34,
                      color: Colors.white,
                    ),
                  ),
                  SizedBox(height: isCompact ? 14 : 18),
                  Text(
                    'Nenhuma mensagem encontrada.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: isCompact ? 17 : 19,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Quando novas conversas chegarem, elas aparecerão aqui.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: isCompact ? 13 : 14,
                      color: Colors.white.withOpacity(0.82),
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildThreadCard(Map<String, dynamic> thread, bool isCompact) {
    final unreadCount = (thread['unread_count'] ?? 0) as int;
    final subject = (thread['subject'] ?? 'Mensagem').toString();
    final subtitle = _threadSubtitle(thread);

    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => _openThread(thread),
            borderRadius: BorderRadius.circular(22),
            child: Ink(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                gradient: LinearGradient(
                  colors: [
                    Colors.white.withOpacity(0.18),
                    Colors.white.withOpacity(0.10),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                border: Border.all(
                  color: unreadCount > 0
                      ? Colors.white.withOpacity(0.30)
                      : Colors.white.withOpacity(0.18),
                  width: unreadCount > 0 ? 1.2 : 1.0,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.16),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                  BoxShadow(
                    color:
                        olympusGold.withOpacity(unreadCount > 0 ? 0.14 : 0.06),
                    blurRadius: 14,
                    spreadRadius: 0.5,
                  ),
                ],
              ),
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: isCompact ? 14 : 18,
                  vertical: isCompact ? 14 : 16,
                ),
                child: Row(
                  children: [
                    Container(
                      width: isCompact ? 50 : 58,
                      height: isCompact ? 50 : 58,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        color: Colors.white.withOpacity(0.10),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.14),
                        ),
                      ),
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          const Center(
                            child: Icon(
                              Icons.mark_chat_unread_rounded,
                              color: Colors.white,
                              size: 26,
                            ),
                          ),
                          if (unreadCount > 0)
                            Positioned(
                              right: -4,
                              top: -4,
                              child: Container(
                                constraints: const BoxConstraints(
                                  minWidth: 24,
                                  minHeight: 24,
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.red.shade700,
                                  borderRadius: BorderRadius.circular(999),
                                  border: Border.all(
                                    color: Colors.white,
                                    width: 1.4,
                                  ),
                                ),
                                child: Text(
                                  unreadCount > 99 ? '99+' : '$unreadCount',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    SizedBox(width: isCompact ? 12 : 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            subject,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: isCompact ? 16 : 17,
                              fontWeight: unreadCount > 0
                                  ? FontWeight.w800
                                  : FontWeight.w700,
                              color: Colors.white,
                              height: 1.1,
                            ),
                          ),
                          SizedBox(height: isCompact ? 6 : 8),
                          Text(
                            subtitle.isEmpty
                                ? 'Toque para abrir a conversa.'
                                : subtitle,
                            maxLines: isCompact ? 2 : 3,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: isCompact ? 12.5 : 13.5,
                              color: Colors.white.withOpacity(0.82),
                              height: 1.35,
                            ),
                          ),
                        ],
                      ),
                    ),
                    PopupMenuButton<String>(
                      tooltip: 'Opções da conversa',
                      icon: Icon(
                        Icons.more_vert_rounded,
                        size: isCompact ? 20 : 22,
                        color: Colors.white.withOpacity(0.88),
                      ),
                      onSelected: (value) {
                        if (value == 'delete') {
                          _deleteThreadForMe(thread);
                        }
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem<String>(
                          value: 'delete',
                          child: Row(
                            children: [
                              Icon(Icons.delete_outline),
                              SizedBox(width: 10),
                              Text('Excluir conversa'),
                            ],
                          ),
                        ),
                      ],
                    ),
                    SizedBox(width: isCompact ? 2 : 4),
                    Icon(
                      Icons.arrow_forward_ios_rounded,
                      size: isCompact ? 16 : 18,
                      color: Colors.white.withOpacity(0.72),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDebugCard() {
    return const SizedBox.shrink();
  }

  void _showSnack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isCompact = size.width < 380;

    final content = _loading
        ? const Center(
            child: CircularProgressIndicator(color: Colors.white),
          )
        : _threads.isEmpty
            ? RefreshIndicator(
                color: olympusBlue,
                onRefresh: () => _loadThreads(showLoader: false),
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsets.only(bottom: size.height * 0.08),
                  children: [
                    SizedBox(height: size.height * 0.12),
                    _buildEmptyState(isCompact),
                  ],
                ),
              )
            : RefreshIndicator(
                color: olympusBlue,
                onRefresh: () => _loadThreads(showLoader: false),
                child: ListView.separated(
                  padding: EdgeInsets.fromLTRB(
                    isCompact ? 12 : 16,
                    16,
                    isCompact ? 12 : 16,
                    24,
                  ),
                  itemCount: _threads.length,
                  separatorBuilder: (_, __) =>
                      SizedBox(height: isCompact ? 10 : 12),
                  itemBuilder: (context, index) {
                    final thread = _threads[index];
                    return _buildThreadCard(thread, isCompact);
                  },
                ),
              );

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Mensagens'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Atualizar',
            onPressed:
                _refreshing ? null : () => _loadThreads(showLoader: false),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Stack(
        children: [
          Positioned.fill(child: _buildPremiumBackground()),
          SafeArea(child: content),
        ],
      ),
    );
  }
}
