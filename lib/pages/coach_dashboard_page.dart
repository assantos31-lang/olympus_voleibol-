import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/messaging_service.dart';
import 'user_messages_page.dart';

class CoachDashboardPage extends StatefulWidget {
  const CoachDashboardPage({super.key});

  @override
  State<CoachDashboardPage> createState() => _CoachDashboardPageState();
}

class _CoachDashboardPageState extends State<CoachDashboardPage> {
  final supabase = Supabase.instance.client;
  final MessagingService _messagingService = MessagingService();
  int _unreadMessagesCount = 0;

  @override
  void initState() {
    super.initState();
    _loadUnreadMessagesCount();
  }

  Future<void> _redirectToLogin() async {
    await supabase.auth.signOut();
    if (mounted) {
      Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
    }
  }

  Future<void> _loadUnreadMessagesCount() async {
    try {
      final threads = await _messagingService.getInboxThreads();
      final unread =
          threads.fold<int>(0, (sum, item) => sum + item.unreadCount);

      if (!mounted) return;

      setState(() {
        _unreadMessagesCount = unread;
      });
    } catch (_) {}
  }

  Widget _bg() {
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
              color: const Color(0xFF0B1420).withOpacity(0.46),
            ),
          ),
        ],
      ),
    );
  }

  Widget _messagesButton(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        ElevatedButton.icon(
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const UserMessagesPage()),
            ).then((_) => _loadUnreadMessagesCount());
          },
          icon: const Icon(Icons.mark_email_unread_rounded),
          label: const Text('Abrir Mensagens'),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFD4AF37),
            foregroundColor: const Color(0xFF1E3A5F),
          ),
        ),
        if (_unreadMessagesCount > 0)
          Positioned(
            right: -8,
            top: -8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              constraints: const BoxConstraints(minWidth: 22),
              decoration: BoxDecoration(
                color: Colors.red,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: Colors.white, width: 1.2),
              ),
              child: Text(
                _unreadMessagesCount > 99 ? '99+' : '$_unreadMessagesCount',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Área do Técnico'),
        backgroundColor: const Color(0xFF1E3A5F),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Sair',
            onPressed: _redirectToLogin,
          ),
        ],
      ),
      body: Stack(
        children: [
          _bg(),
          Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.sports_volleyball,
                      size: 92, color: Colors.white),
                  const SizedBox(height: 20),
                  const Text(
                    'Painel do Técnico',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _messagesButton(context),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
