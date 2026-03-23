import 'dart:ui';
import 'package:flutter/material.dart';
import '../models/app_message.dart';
import '../services/messaging_service.dart';
import 'message_thread_page.dart';

class UserMessagesPage extends StatefulWidget {
  const UserMessagesPage({super.key});

  @override
  State<UserMessagesPage> createState() => _UserMessagesPageState();
}

class _UserMessagesPageState extends State<UserMessagesPage> {
  final MessagingService _service = MessagingService();

  static const Color olympusBlue = Color(0xFF1E3A5F);
  static const Color olympusDark = Color(0xFF0B1420);

  bool _isLoading = true;
  List<AppMessageThread> _threads = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final threads = await _service.getInboxThreads();
      if (!mounted) return;
      setState(() {
        _threads = threads;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao carregar inbox: $e')),
      );
    }
  }

  Widget _buildBackground() {
    return IgnorePointer(
      child: Stack(
        children: [
          Positioned.fill(
            child: Opacity(
              opacity: 0.78,
              child: Image.asset(
                'assets/images/monte_olimpo.png',
                fit: BoxFit.cover,
                alignment: Alignment.topCenter,
              ),
            ),
          ),
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 0.8, sigmaY: 0.8),
              child: Container(color: Colors.transparent),
            ),
          ),
          Positioned.fill(
            child: Container(
              color: olympusDark.withOpacity(0.46),
            ),
          ),
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color.fromRGBO(9, 17, 27, 0.26),
                    Color.fromRGBO(17, 37, 58, 0.14),
                    Color.fromRGBO(30, 58, 95, 0.28),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _threadTile(AppMessageThread thread) {
    return Material(
      color: Colors.white.withOpacity(0.07),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => MessageThreadPage(
                initialThread: thread,
                canReply: true,
              ),
            ),
          );
          _load();
        },
        child: ListTile(
          title: Text(
            thread.subject,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
          subtitle: Text(
            thread.preview.isEmpty ? 'Sem preview' : thread.preview,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: Colors.white.withOpacity(0.68)),
          ),
          trailing: thread.unreadCount > 0
              ? Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.red,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    thread.unreadCount > 99 ? '99+' : '${thread.unreadCount}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                )
              : const Icon(Icons.chevron_right, color: Colors.white70),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: olympusDark,
      appBar: AppBar(
        title: const Text('Minhas mensagens'),
        backgroundColor: olympusBlue,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            onPressed: _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Stack(
        children: [
          _buildBackground(),
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _load,
                  child: _threads.isEmpty
                      ? ListView(
                          children: [
                            const SizedBox(height: 180),
                            Center(
                              child: Text(
                                'Nenhuma mensagem recebida ainda.',
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.76),
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemCount: _threads.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 10),
                          itemBuilder: (_, i) => _threadTile(_threads[i]),
                        ),
                ),
        ],
      ),
    );
  }
}
