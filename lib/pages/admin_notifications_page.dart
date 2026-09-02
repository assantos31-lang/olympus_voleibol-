import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../theme/olympus_theme.dart';
import 'agenda_page.dart';
import 'admin_financial_page.dart';

class AdminNotificationsPage extends StatefulWidget {
  const AdminNotificationsPage({super.key});

  @override
  State<AdminNotificationsPage> createState() => _AdminNotificationsPageState();
}

class _AdminNotificationsPageState extends State<AdminNotificationsPage> {
  final SupabaseClient _supabase = Supabase.instance.client;

  bool _isLoading = true;
  List<Map<String, dynamic>> _notifications = [];
  RealtimeChannel? _notificationsChannel;

  static const Color _primaryColor = Color(0xFF0C2340);
  static const Color _goldColor = Color(0xFFE4C050);
  static const Color _cyanColor = Color(0xFF8FE8FF);

  @override
  void initState() {
    super.initState();
    _loadNotifications();
    _listenForNotifications();
  }

  @override
  void dispose() {
    if (_notificationsChannel != null) {
      _supabase.removeChannel(_notificationsChannel!);
    }
    super.dispose();
  }

  Future<void> _loadNotifications() async {
    final user = _supabase.auth.currentUser;

    if (user == null) {
      if (mounted) {
        setState(() {
          _notifications = [];
          _isLoading = false;
        });
      }
      return;
    }

    try {
      final response = await _supabase
          .from('admin_notifications')
          .select()
          .eq('admin_id', user.id)
          .order('created_at', ascending: false);

      if (mounted) {
        setState(() {
          _notifications = List<Map<String, dynamic>>.from(response as List);
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Erro ao carregar notificações admin: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao carregar notificações: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _listenForNotifications() {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    _notificationsChannel = _supabase
        .channel('admin_notifications_page_${user.id}')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'admin_notifications',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'admin_id',
            value: user.id,
          ),
          callback: (_) => _loadNotifications(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'admin_notifications',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'admin_id',
            value: user.id,
          ),
          callback: (_) => _loadNotifications(),
        )
        .subscribe();
  }

  Future<void> _markAsRead(String notificationId) async {
    try {
      await _supabase.from('admin_notifications').update({
        'is_read': true,
        'read_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', notificationId);

      if (mounted) {
        setState(() {
          final index = _notifications.indexWhere(
            (item) => item['id']?.toString() == notificationId,
          );
          if (index >= 0) {
            _notifications[index] = {
              ..._notifications[index],
              'is_read': true,
              'read_at': DateTime.now().toUtc().toIso8601String(),
            };
          }
        });
      }
    } catch (e) {
      debugPrint('Erro ao marcar notificação como lida: $e');
    }
  }

  Future<void> _markAllAsRead() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    try {
      await _supabase
          .from('admin_notifications')
          .update({
            'is_read': true,
            'read_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('admin_id', user.id)
          .eq('is_read', false);

      await _loadNotifications();
    } catch (e) {
      debugPrint('Erro ao marcar todas como lidas: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao marcar como lidas: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _openNotification(Map<String, dynamic> notification) async {
    final id = notification['id']?.toString();
    if (id != null && id.isNotEmpty) {
      await _markAsRead(id);
    }

    if (!mounted) return;

    final isEventResponse =
        notification['notification_type'] == 'event_response';
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            isEventResponse ? const AgendaPage() : const AdminFinancialPage(),
      ),
    );
  }

  String _notificationTitle(Map<String, dynamic> notification) {
    final title = notification['title']?.toString().trim();
    if (title != null && title.isNotEmpty) return title;
    return 'Novo comprovante anexado';
  }

  String _notificationBody(Map<String, dynamic> notification) {
    final body = notification['body']?.toString().trim();
    if (body != null && body.isNotEmpty) return body;

    final athleteName = notification['athlete_name']?.toString().trim();
    if (athleteName != null && athleteName.isNotEmpty) {
      return '$athleteName anexou um comprovante.';
    }

    return 'Um atleta anexou um comprovante financeiro.';
  }

  DateTime? _createdAt(Map<String, dynamic> notification) {
    final raw = notification['created_at'];
    if (raw == null) return null;
    return DateTime.tryParse(raw.toString())?.toLocal();
  }

  String _formatDate(DateTime? date) {
    if (date == null) return '';

    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    final year = date.year.toString();
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');

    return '$day/$month/$year às $hour:$minute';
  }

  int get _unreadCount {
    return _notifications.where((item) => item['is_read'] != true).length;
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 86,
              height: 86,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.10),
                border: Border.all(color: Colors.white.withOpacity(0.16)),
              ),
              child: const Icon(
                Icons.notifications_none_rounded,
                color: _goldColor,
                size: 42,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'Nenhuma notificação ainda',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withOpacity(0.92),
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'As respostas dos atletas e outros avisos aparecerão aqui.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withOpacity(0.68),
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNotificationCard(Map<String, dynamic> notification) {
    final isRead = notification['is_read'] == true;
    final isEventResponse =
        notification['notification_type'] == 'event_response';
    final date = _createdAt(notification);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => _openNotification(notification),
              borderRadius: BorderRadius.circular(18),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: isRead
                        ? Colors.white.withOpacity(0.12)
                        : _goldColor.withOpacity(0.45),
                    width: 1.2,
                  ),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: isRead
                        ? [
                            Colors.white.withOpacity(0.10),
                            Colors.white.withOpacity(0.05),
                          ]
                        : [
                            _goldColor.withOpacity(0.20),
                            Colors.white.withOpacity(0.08),
                          ],
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Container(
                          width: 46,
                          height: 46,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _goldColor.withOpacity(0.14),
                            border: Border.all(
                              color: _goldColor.withOpacity(0.35),
                            ),
                          ),
                          child: Icon(
                            isEventResponse
                                ? Icons.how_to_reg_rounded
                                : Icons.attach_file_rounded,
                            color: isRead ? Colors.white70 : _goldColor,
                            size: 24,
                          ),
                        ),
                        if (!isRead)
                          Positioned(
                            top: -1,
                            right: -1,
                            child: Container(
                              width: 12,
                              height: 12,
                              decoration: BoxDecoration(
                                color: Colors.redAccent,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.white,
                                  width: 1.5,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _notificationTitle(notification),
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.94),
                              fontSize: 15,
                              fontWeight:
                                  isRead ? FontWeight.w600 : FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _notificationBody(notification),
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.74),
                              fontSize: 13,
                              height: 1.25,
                            ),
                          ),
                          if (_formatDate(date).isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text(
                              _formatDate(date),
                              style: TextStyle(
                                color: _cyanColor.withOpacity(0.82),
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      Icons.chevron_right_rounded,
                      color: Colors.white.withOpacity(0.55),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _primaryColor,
      appBar: AppBar(
        backgroundColor: _primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Notificações'),
        actions: [
          if (_unreadCount > 0)
            TextButton(
              onPressed: _markAllAsRead,
              child: const Text(
                'Marcar lidas',
                style: TextStyle(color: _goldColor),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loadNotifications,
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color.lerp(olympusBlue, Colors.black, 0.30)!,
              olympusBlue,
              Color.lerp(olympusBlue, Colors.black, 0.42)!,
            ],
          ),
        ),
        child: _isLoading
            ? const Center(
                child: CircularProgressIndicator(color: _goldColor),
              )
            : RefreshIndicator(
                onRefresh: () async {
                  await _loadNotifications();
                },
                child: _notifications.isEmpty
                    ? ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: [
                          SizedBox(
                            height: MediaQuery.of(context).size.height * 0.55,
                            child: _buildEmptyState(),
                          ),
                        ],
                      )
                    : ListView.builder(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                        itemCount: _notifications.length,
                        itemBuilder: (context, index) {
                          return _buildNotificationCard(
                            _notifications[index],
                          );
                        },
                      ),
              ),
      ),
    );
  }
}
