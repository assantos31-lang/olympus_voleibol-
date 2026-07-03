import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/badge_service.dart';

class CoachMessageThreadPage extends StatefulWidget {
  final String threadId;
  final String subject;
  final bool allowReply;

  const CoachMessageThreadPage({
    super.key,
    required this.threadId,
    required this.subject,
    required this.allowReply,
  });

  @override
  State<CoachMessageThreadPage> createState() => _CoachMessageThreadPageState();
}

class _CoachMessageThreadPageState extends State<CoachMessageThreadPage> {
  final SupabaseClient supabase = Supabase.instance.client;
  static const Color olympusBlue = Color(0xFF1E3A5F);
  static const Color olympusGold = Color(0xFFD4AF37);
  static const Color olympusLightBlue = Color(0xFF2C5F8D);
  final TextEditingController _replyController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  bool _loading = true;
  bool _sending = false;
  bool _hasShownReadConfirmation = false;
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

  Future<void> _handleBack() async {
    await _markThreadAsRead();
    if (!mounted) return;
    Navigator.of(context).pop(true);
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

    final now = DateTime.now().toUtc().toIso8601String();

    final current = await supabase
        .from('app_message_participants')
        .select('unread_count')
        .eq('thread_id', widget.threadId)
        .eq('user_id', user.id)
        .maybeSingle();

    final hadUnread = ((current?['unread_count'] ?? 0) as num) > 0;

    await supabase
        .from('app_message_participants')
        .update({
          'unread_count': 0,
          'last_read_at': now,
          'is_read': true,
          'viewed_at': now,
        })
        .eq('thread_id', widget.threadId)
        .eq('user_id', user.id);

    await BadgeService.updateBadge();

    if (hadUnread && !_hasShownReadConfirmation && mounted) {
      _hasShownReadConfirmation = true;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            '✓ Mensagem visualizada. O administrador foi notificado.',
          ),
          duration: Duration(seconds: 3),
        ),
      );
    }
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
      final senderType = (profile?['user_type'] ?? 'coach').toString();
      final now = DateTime.now().toUtc().toIso8601String();

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
        if (participantId.isEmpty) continue;

        if (participantId == user.id) {
          await supabase
              .from('app_message_participants')
              .update({
                'unread_count': 0,
                'last_read_at': now,
                'is_read': true,
                'viewed_at': now,
              })
              .eq('thread_id', widget.threadId)
              .eq('user_id', participantId);
          continue;
        }

        final currentUnread = (row['unread_count'] ?? 0) as int;

        await supabase
            .from('app_message_participants')
            .update({
              'unread_count': currentUnread + 1,
              'is_read': false,
              'viewed_at': null,
            })
            .eq('thread_id', widget.threadId)
            .eq('user_id', participantId);
      }

      _replyController.clear();
      await _markThreadAsRead();
      await _loadMessages();
      await BadgeService.updateBadge();
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

  Widget _buildThreadBackground() {
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
            color: Colors.black.withOpacity(0.24),
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
                  olympusBlue.withOpacity(0.52),
                  olympusLightBlue.withOpacity(0.22),
                  Colors.black.withOpacity(0.62),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  String _senderLabel(Map<String, dynamic> message, bool isMine) {
    if (isMine) return 'Você';

    final senderName = (message['sender_name'] ?? '').toString().trim();
    if (senderName.isNotEmpty) return senderName;

    final senderType = (message['sender_type'] ?? '').toString().toLowerCase();
    if (senderType.contains('admin')) return 'Administrador';
    if (senderType.contains('athlete') || senderType.contains('atleta')) {
      return 'Atleta';
    }
    if (senderType.contains('coach') || senderType.contains('treinador')) {
      return 'Treinador';
    }

    return 'Participante';
  }

  Widget _buildMessageBubble(
    BuildContext context,
    Map<String, dynamic> message,
    bool isCompact,
  ) {
    final isMine = _isCurrentUser(message);
    final body = (message['body'] ?? '').toString();
    final createdAt = _formatDateTime(message['created_at']);

    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth:
              MediaQuery.of(context).size.width * (isCompact ? 0.88 : 0.80),
        ),
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          child: ClipRRect(
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(20),
              topRight: const Radius.circular(20),
              bottomLeft: Radius.circular(isMine ? 20 : 8),
              bottomRight: Radius.circular(isMine ? 8 : 20),
            ),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
              child: Container(
                padding: EdgeInsets.all(isCompact ? 12 : 14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(20),
                    topRight: const Radius.circular(20),
                    bottomLeft: Radius.circular(isMine ? 20 : 8),
                    bottomRight: Radius.circular(isMine ? 8 : 20),
                  ),
                  gradient: LinearGradient(
                    colors: isMine
                        ? [
                            olympusGold.withOpacity(0.94),
                            const Color(0xFFE2C65A),
                          ]
                        : [
                            Colors.white.withOpacity(0.18),
                            Colors.white.withOpacity(0.10),
                          ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  border: Border.all(
                    color: isMine
                        ? Colors.white.withOpacity(0.20)
                        : Colors.white.withOpacity(0.14),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.14),
                      blurRadius: 12,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _senderLabel(message, isMine),
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: isCompact ? 12.5 : 13.2,
                        color: isMine ? olympusBlue : Colors.white,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      body,
                      style: TextStyle(
                        fontSize: isCompact ? 13.5 : 14.2,
                        height: 1.35,
                        color: isMine ? olympusBlue : Colors.white,
                      ),
                    ),
                    if (createdAt.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          createdAt,
                          style: TextStyle(
                            fontSize: 11,
                            color: isMine
                                ? olympusBlue.withOpacity(0.78)
                                : Colors.white.withOpacity(0.72),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildReplyBar(bool isCompact) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          isCompact ? 12 : 16,
          8,
          isCompact ? 12 : 16,
          isCompact ? 12 : 14,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
            child: Container(
              padding: EdgeInsets.all(isCompact ? 8 : 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                color: Colors.white.withOpacity(0.12),
                border: Border.all(
                  color: Colors.white.withOpacity(0.18),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.14),
                    blurRadius: 14,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _replyController,
                      minLines: 1,
                      maxLines: 4,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: 'Digite sua resposta',
                        hintStyle: TextStyle(
                          color: Colors.white.withOpacity(0.62),
                        ),
                        filled: true,
                        fillColor: Colors.white.withOpacity(0.08),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(18),
                          borderSide: BorderSide(
                            color: Colors.white.withOpacity(0.10),
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(18),
                          borderSide: BorderSide(
                            color: Colors.white.withOpacity(0.10),
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(18),
                          borderSide: const BorderSide(
                            color: Colors.white,
                            width: 1.1,
                          ),
                        ),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: isCompact ? 12 : 13,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    height: 50,
                    width: 50,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        gradient: const LinearGradient(
                          colors: [
                            Color(0xFFF0D771),
                            Color(0xFFB48A23),
                          ],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: olympusGold.withOpacity(0.35),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: FilledButton(
                        onPressed: _sending ? null : _sendReply,
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          foregroundColor: olympusBlue,
                          padding: EdgeInsets.zero,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: _sending
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                      olympusBlue),
                                ),
                              )
                            : const Icon(Icons.send_rounded),
                      ),
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

    return WillPopScope(
      onWillPop: () async {
        await _handleBack();
        return false;
      },
      child: Scaffold(
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: _handleBack,
          ),
          title: Text(widget.subject),
          backgroundColor: Colors.transparent,
          elevation: 0,
          foregroundColor: Colors.white,
        ),
        body: Stack(
          children: [
            Positioned.fill(child: _buildThreadBackground()),
            SafeArea(
              child: Column(
                children: [
                  Expanded(
                    child: _loading
                        ? const Center(
                            child:
                                CircularProgressIndicator(color: Colors.white),
                          )
                        : _messages.isEmpty
                            ? Center(
                                child: Padding(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: isCompact ? 20 : 28,
                                  ),
                                  child: Text(
                                    'Nenhuma mensagem nesta conversa.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: isCompact ? 16 : 18,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              )
                            : ListView.builder(
                                controller: _scrollController,
                                padding: EdgeInsets.fromLTRB(
                                  isCompact ? 12 : 16,
                                  12,
                                  isCompact ? 12 : 16,
                                  16,
                                ),
                                itemCount: _messages.length,
                                itemBuilder: (context, index) {
                                  final message = _messages[index];
                                  return _buildMessageBubble(
                                    context,
                                    message,
                                    isCompact,
                                  );
                                },
                              ),
                  ),
                  if (widget.allowReply) _buildReplyBar(isCompact),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
