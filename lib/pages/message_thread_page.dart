import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/active_message_thread_registry.dart';
import '../services/messaging_service.dart';

class MessageThreadPage extends StatefulWidget {
  final String roomId;

  const MessageThreadPage({
    super.key,
    required this.roomId,
  });

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

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Chat'),
      ),
      body: Column(
        children: [
          Theme(
            data: Theme.of(context).copyWith(
              dividerColor: Colors.transparent,
            ),
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
                      Chip(
                        label: Text('Visualizaram (0)'),
                      ),
                      Chip(
                        label: Text('Pendentes (1)'),
                      ),
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
                    child:
                        Text('Erro ao carregar mensagens: ${snapshot.error}'),
                  );
                }

                if (!snapshot.hasData) {
                  return const Center(
                    child: CircularProgressIndicator(),
                  );
                }

                final messages = snapshot.data ?? [];

                if (messages.isEmpty) {
                  return const Center(
                    child: Text('Nenhuma mensagem ainda.'),
                  );
                }

                return ListView.builder(
                  reverse: true,
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final msg = messages[index];

                    return ListTile(
                      title: Text((msg['content'] ?? '').toString()),
                      subtitle: Text((msg['sender_id'] ?? '').toString()),
                    );
                  },
                );
              },
            ),
          ),
          SafeArea(
            top: false,
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
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 14,
                      ),
                    ),
                  ),
                ),
                IconButton(
                  icon: _sending
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send),
                  onPressed: _sending ? null : _send,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
