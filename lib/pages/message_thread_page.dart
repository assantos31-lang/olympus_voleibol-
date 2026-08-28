import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/active_message_thread_registry.dart';
import '../services/messaging_service.dart';
import '../theme/olympus_theme.dart';

class MessageThreadPage extends StatefulWidget {
  final String roomId;

  const MessageThreadPage({super.key, required this.roomId});

  @override
  State<MessageThreadPage> createState() => _MessageThreadPageState();
}

class _MessageThreadPageState extends State<MessageThreadPage> {
  final MessagingService _service = MessagingService();
  final TextEditingController _controller = TextEditingController();
  final SupabaseClient _supabase = Supabase.instance.client;

  bool _sending = false;

  @override
  void initState() {
    super.initState();
    ActiveMessageThreadRegistry.instance.openThread(roomId: widget.roomId);
  }

  @override
  void dispose() {
    ActiveMessageThreadRegistry.instance.closeThread();
    _controller.dispose();
    super.dispose();
  }

  User? _currentUser() {
    return _supabase.auth.currentSession?.user ?? _supabase.auth.currentUser;
  }

  Future<void> _send() async {
    final user = _currentUser();

    if (user == null) {
      _showSnack('Usuario nao autenticado.');
      return;
    }

    final content = _controller.text.trim();

    if (content.isEmpty) return;

    setState(() => _sending = true);

    try {
      await _service.sendMessage(
        roomId: widget.roomId,
        senderId: user.id,
        content: content,
      );

      _controller.clear();
    } catch (e) {
      _showSnack('Erro ao enviar mensagem: $e');
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
    }
  }

  void _showSnack(String text) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final currentUserId = _currentUser()?.id;
    return Scaffold(
      appBar: AppBar(title: const Text('Mensagens')),
      body: OlympusBrandedBackground(
        child: Column(
          children: [
            Theme(
              data: Theme.of(
                context,
              ).copyWith(dividerColor: Colors.transparent),
              child: Card(
                margin: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                child: ExpansionTile(
                  tilePadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  leading: const Icon(Icons.visibility_outlined),
                  title: const Text(
                    'Status de visualizacao',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: const Text('Toque para visualizar'),
                  children: const [
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        Chip(label: Text('Visualizaram (0)')),
                        Chip(label: Text('Pendentes (1)')),
                      ],
                    ),
                    SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Nenhum detalhe de visualizacao disponivel ainda.',
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: StreamBuilder<List<Map<String, dynamic>>>(
                stream: _service.streamMessages(widget.roomId),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Center(
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.cloud_off_rounded,
                                size: 40,
                                color: colors.primary,
                              ),
                              const SizedBox(height: 10),
                              const Text(
                                'Não foi possível carregar as mensagens.',
                                textAlign: TextAlign.center,
                                style: TextStyle(fontWeight: FontWeight.w800),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }

                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final messages = snapshot.data ?? [];

                  if (messages.isEmpty) {
                    return Center(
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(22),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.mark_chat_unread_outlined,
                                size: 42,
                                color: colors.secondary,
                              ),
                              const SizedBox(height: 10),
                              const Text(
                                'Nenhuma mensagem ainda',
                                style: TextStyle(fontWeight: FontWeight.w900),
                              ),
                              const SizedBox(height: 4),
                              const Text(
                                'Envie a primeira mensagem desta conversa.',
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }

                  return ListView.builder(
                    reverse: true,
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      final msg = messages[index];
                      final isMine =
                          (msg['sender_id'] ?? '').toString() == currentUserId;
                      final content = (msg['content'] ?? '').toString();

                      return Align(
                        alignment: isMine
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: Container(
                          constraints: const BoxConstraints(maxWidth: 420),
                          margin: EdgeInsets.fromLTRB(
                            isMine ? 58 : 12,
                            4,
                            isMine ? 12 : 58,
                            4,
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 11,
                          ),
                          decoration: BoxDecoration(
                            color: isMine
                                ? const Color(0xFFDDF7D8)
                                : colors.surface,
                            borderRadius: BorderRadius.only(
                              topLeft: const Radius.circular(18),
                              topRight: const Radius.circular(18),
                              bottomLeft: Radius.circular(isMine ? 18 : 5),
                              bottomRight: Radius.circular(isMine ? 5 : 18),
                            ),
                            border: Border.all(
                              color: isMine
                                  ? colors.secondary.withValues(alpha: 0.52)
                                  : Colors.white.withValues(alpha: 0.75),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.14),
                                blurRadius: 8,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          child: Text(
                            content,
                            style: const TextStyle(
                              color: Color(0xFF172338),
                              fontSize: 15,
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
            SafeArea(
              top: false,
              child: Container(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                decoration: BoxDecoration(
                  color: colors.primary,
                  border: Border(
                    top: BorderSide(
                      color: colors.secondary.withValues(alpha: 0.5),
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        enabled: !_sending,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _sending ? null : _send(),
                        decoration: const InputDecoration(
                          hintText: 'Digite uma mensagem',
                          filled: true,
                          fillColor: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: colors.secondary,
                        foregroundColor: colors.primary,
                        shape: const CircleBorder(),
                        padding: const EdgeInsets.all(14),
                      ),
                      onPressed: _sending ? null : _send,
                      child: _sending
                          ? const SizedBox.square(
                              dimension: 20,
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
      ),
    );
  }
}
