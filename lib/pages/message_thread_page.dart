import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/app_message.dart';
import '../services/messaging_service.dart';

class MessageThreadPage extends StatefulWidget {
  final AppMessageThread initialThread;
  final bool canReply;

  const MessageThreadPage({
    super.key,
    required this.initialThread,
    required this.canReply,
  });

  @override
  State<MessageThreadPage> createState() => _MessageThreadPageState();
}

class _MessageThreadPageState extends State<MessageThreadPage> {
  final MessagingService _service = MessagingService();
  final TextEditingController _replyController = TextEditingController();

  static const Color olympusBlue = Color(0xFF1E3A5F);
  static const Color olympusGold = Color(0xFFD4AF37);
  static const Color olympusDark = Color(0xFF0B1420);

  bool _isLoading = true;
  bool _isSending = false;
  List<AppMessageItem> _messages = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final items = await _service.getThreadMessages(widget.initialThread.id);
    await _service.markThreadAsRead(widget.initialThread.id);
    if (!mounted) return;
    setState(() {
      _messages = items;
      _isLoading = false;
    });
  }

  Future<void> _send() async {
    final text = _replyController.text.trim();
    if (text.isEmpty) return;

    setState(() => _isSending = true);
    try {
      await _service.sendReply(
        threadId: widget.initialThread.id,
        body: text,
      );
      _replyController.clear();
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao enviar: $e')),
      );
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  Widget _bubble(AppMessageItem item) {
    final isAdmin = item.senderType == 'admin';
    return Align(
      alignment: isAdmin ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        constraints: const BoxConstraints(maxWidth: 320),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isAdmin ? olympusBlue : Colors.white.withOpacity(0.10),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isAdmin
                ? olympusGold.withOpacity(0.28)
                : Colors.white.withOpacity(0.10),
          ),
        ),
        child: Column(
          crossAxisAlignment:
              isAdmin ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Text(
              item.senderName,
              style: TextStyle(
                color: isAdmin ? olympusGold : Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              item.body,
              style: const TextStyle(color: Colors.white, height: 1.35),
            ),
            const SizedBox(height: 6),
            Text(
              DateFormat('dd/MM HH:mm').format(item.createdAt),
              style: TextStyle(
                color: Colors.white.withOpacity(0.62),
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _replyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: olympusDark,
      appBar: AppBar(
        title: Text(widget.initialThread.subject),
        backgroundColor: olympusBlue,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    padding: const EdgeInsets.all(16),
                    children: _messages.map(_bubble).toList(),
                  ),
          ),
          if (widget.canReply && widget.initialThread.allowReply)
            SafeArea(
              top: false,
              child: Container(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF122235),
                  border: Border(
                    top: BorderSide(color: Colors.white.withOpacity(0.08)),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _replyController,
                        style: const TextStyle(color: Colors.white),
                        minLines: 1,
                        maxLines: 4,
                        decoration: InputDecoration(
                          hintText: 'Digite sua resposta',
                          hintStyle:
                              TextStyle(color: Colors.white.withOpacity(0.55)),
                          filled: true,
                          fillColor: Colors.white.withOpacity(0.08),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      onPressed: _isSending ? null : _send,
                      style: IconButton.styleFrom(
                        backgroundColor: olympusGold,
                        foregroundColor: olympusBlue,
                      ),
                      icon: _isSending
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.send_rounded),
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
