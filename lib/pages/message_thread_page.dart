import 'package:flutter/material.dart';
import '../services/messaging_service.dart';
import '../services/active_message_thread_registry.dart';

class MessageThreadPage extends StatefulWidget {
  final String roomId;

  const MessageThreadPage({Key? key, required this.roomId}) : super(key: key);

  @override
  State<MessageThreadPage> createState() => _MessageThreadPageState();
}

class _MessageThreadPageState extends State<MessageThreadPage> {
  final MessagingService _service = MessagingService();
  final TextEditingController _controller = TextEditingController();

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

  void _send() async {
    if (_controller.text.trim().isEmpty) return;

    await _service.sendMessage(
      roomId: widget.roomId,
      senderId: "USER_ID_AQUI",
      content: _controller.text.trim(),
    );

    _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Chat")),
      body: Column(
        children: [
          Theme(
            data: Theme.of(context).copyWith(
              dividerColor: Colors.transparent,
            ),
            child: Card(
              margin: const EdgeInsets.fromLTRB(12, 12, 12, 8),
              child: ExpansionTile(
                tilePadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                leading: const Icon(Icons.visibility_outlined),
                title: const Text(
                  'Status de visualização',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: const Text('Toque para visualizar'),
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: const [
                      Chip(
                        label: Text('Visualizaram (0)'),
                      ),
                      Chip(
                        label: Text('Pendentes (1)'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Nenhum detalhe de visualização disponível ainda.',
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: StreamBuilder(
              stream: _service.streamMessages(widget.roomId),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final messages = snapshot.data as List<Map<String, dynamic>>;

                return ListView.builder(
                  reverse: true,
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final msg = messages[index];

                    return ListTile(
                      title: Text(msg['content'] ?? ''),
                      subtitle: Text(msg['sender_id'] ?? ''),
                    );
                  },
                );
              },
            ),
          ),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  decoration: const InputDecoration(
                    hintText: "Digite uma mensagem",
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.send),
                onPressed: _send,
              )
            ],
          )
        ],
      ),
    );
  }
}
