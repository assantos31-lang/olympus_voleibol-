import 'package:flutter/material.dart';
import '../theme/olympus_theme.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/app_message_service.dart';
import '../services/olympus_memory_cache.dart';

class AdminMessagesPage extends StatefulWidget {
  const AdminMessagesPage({super.key});

  @override
  State<AdminMessagesPage> createState() => _AdminMessagesPageState();
}

class _AdminMessagesPageState extends State<AdminMessagesPage> {
  final SupabaseClient supabase = Supabase.instance.client;

  bool _loading = true;
  bool _loadingHistory = false;
  bool _loadingSchedules = false;
  bool _showScheduledSection = false;
  bool _showSentSection = false;
  String _scheduledMonthFilter = 'Todos';
  String _sentMonthFilter = 'Todos';
  static const int _sentPageSize = 50;
  int _sentLoadLimit = _sentPageSize;
  bool _hasMoreSentThreads = false;
  bool _openingMessagesPage = false;

  List<Map<String, dynamic>> _sentThreads = [];
  List<Map<String, dynamic>> _scheduledMessages = [];
  final Set<String> _selectedThreadIds = <String>{};

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    _restoreMessagesCache();
    await Future.wait([_loadSentThreads(), _loadScheduledMessages()]);
  }

  String get _messagesCacheKey =>
      'admin_messages:${supabase.auth.currentUser?.id ?? 'guest'}';

  void _restoreMessagesCache() {
    final cached = OlympusMemoryCache.read<Map<String, dynamic>>(
      _messagesCacheKey,
    );
    if (cached == null) return;

    final sent = List<Map<String, dynamic>>.from(
      (cached['sent'] as List?) ?? const [],
    );
    final scheduled = List<Map<String, dynamic>>.from(
      (cached['scheduled'] as List?) ?? const [],
    );
    if (sent.isEmpty && scheduled.isEmpty) return;

    setState(() {
      _sentThreads = sent;
      _scheduledMessages = scheduled;
      _sentLoadLimit = (cached['limit'] as num?)?.toInt() ?? _sentPageSize;
      _hasMoreSentThreads = cached['has_more'] == true;
      _loading = false;
    });
  }

  void _saveMessagesCache() {
    OlympusMemoryCache.write<Map<String, dynamic>>(_messagesCacheKey, {
      'sent': List<Map<String, dynamic>>.from(_sentThreads),
      'scheduled': List<Map<String, dynamic>>.from(_scheduledMessages),
      'limit': _sentLoadLimit,
      'has_more': _hasMoreSentThreads,
    });
  }

  Future<void> _loadSentThreads() async {
    final admin = supabase.auth.currentUser;
    if (admin == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }

    if (mounted) {
      setState(() {
        _loadingHistory = true;
        _loading = _sentThreads.isEmpty && _scheduledMessages.isEmpty;
      });
    }

    try {
      final response = await supabase
          .from('app_message_threads')
          .select(
            'id, subject, preview, created_at, last_message_at, target_mode, '
            'target_user_type, created_by, created_by_name, created_by_type, '
            'allow_reply, app_message_participants(user_id)',
          )
          .or('created_by.eq.${admin.id},created_by_type.eq.system')
          .order('created_at', ascending: false)
          .limit(_sentLoadLimit + 1);

      final loaded = List<Map<String, dynamic>>.from(response);
      final hasMore = loaded.length > _sentLoadLimit;
      final visible = hasMore ? loaded.take(_sentLoadLimit).toList() : loaded;

      if (!mounted) return;
      setState(() {
        _sentThreads = visible;
        _hasMoreSentThreads = hasMore;
        _selectedThreadIds.removeWhere(
          (id) =>
              !_sentThreads.any((item) => (item['id'] ?? '').toString() == id),
        );
        if (!_sentMonthOptions().contains(_sentMonthFilter)) {
          _sentMonthFilter = 'Todos';
        }
      });
      _saveMessagesCache();
    } catch (e) {
      _showSnack('Erro ao carregar histórico: $e');
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadingHistory = false;
        });
      }
    }
  }

  Future<void> _loadMoreSentThreads() async {
    if (_loadingHistory || !_hasMoreSentThreads) return;
    setState(() => _sentLoadLimit += _sentPageSize);
    await _loadSentThreads();
  }

  Future<void> _loadScheduledMessages() async {
    final admin = supabase.auth.currentUser;
    if (admin == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }

    if (mounted) {
      setState(() {
        _loadingSchedules = true;
        _loading = _sentThreads.isEmpty && _scheduledMessages.isEmpty;
      });
    }

    try {
      final response = await supabase
          .from('app_message_schedules')
          .select(
            'id, title, message_body, target_mode, target_user_type, '
            'target_user_id, target_user_ids, gender_filter, frequency, weekdays, day_of_month, '
            'time_of_day, timezone, is_active, last_run_at, next_run_at, '
            'created_by, created_at, updated_at, target_court_position, '
            'delivery_channel, is_urgent, scheduled_for, status, sent_at',
          )
          .eq('created_by', admin.id)
          .eq('is_active', true)
          .inFilter('status', ['pending'])
          .order('next_run_at', ascending: true)
          .order('created_at', ascending: false);

      if (!mounted) return;
      setState(() {
        _scheduledMessages = List<Map<String, dynamic>>.from(response);
        if (!_scheduleMonthOptions().contains(_scheduledMonthFilter)) {
          _scheduledMonthFilter = 'Todos';
        }
      });
      _saveMessagesCache();
    } catch (e) {
      _showSnack('Erro ao carregar agendamentos: $e');
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadingSchedules = false;
        });
      }
    }
  }

  Future<void> _refreshAll() async {
    await Future.wait([_loadSentThreads(), _loadScheduledMessages()]);
  }

  Future<void> _openThread(Map<String, dynamic> thread) async {
    if (_openingMessagesPage) return;
    final threadId = (thread['id'] ?? '').toString();
    if (threadId.isEmpty) return;
    _openingMessagesPage = true;

    try {
      final result = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => AdminMessageThreadPage(
            threadId: threadId,
            subject: (thread['subject'] ?? 'Mensagem').toString(),
            allowReply: thread['allow_reply'] == true,
          ),
        ),
      );

      if (result == true) {
        await _refreshAll();
      }
    } finally {
      _openingMessagesPage = false;
    }
  }

  Future<void> _openCreatePage() async {
    if (_openingMessagesPage) return;
    _openingMessagesPage = true;
    try {
      final created = await Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => const AdminCreateMessagePage()),
      );

      if (created == true) {
        await _refreshAll();
      }
    } finally {
      _openingMessagesPage = false;
    }
  }

  int _recipientCountForThread(Map<String, dynamic> thread) {
    final participants = List<Map<String, dynamic>>.from(
      (thread['app_message_participants'] as List?) ?? const [],
    );
    var count = 0;

    for (final item in participants) {
      final userId = (item['user_id'] ?? '').toString();
      final createdBy = (thread['created_by'] ?? '').toString();
      if (userId.isNotEmpty && userId != createdBy) {
        count++;
      }
    }

    return count;
  }

  String _profileLabelFromValue(String value) {
    const fixedProfileLabels = {
      'coach': 'Técnico',
      'member': 'Membro',
      'athlete': 'Atleta',
    };
    return fixedProfileLabels[value.trim().toLowerCase()] ?? value.trim();
  }

  String _historySubtitle(Map<String, dynamic> thread) {
    final recipients = _recipientCountForThread(thread);
    final profile = (thread['target_user_type'] ?? '').toString().trim();
    final profileLabel = profile.isEmpty ? '' : _profileLabelFromValue(profile);
    final createdAt = DateTime.tryParse(
      ((thread['last_message_at'] ?? thread['created_at']) ?? '').toString(),
    )?.toLocal();

    final parts = <String>[
      if (recipients > 0) '$recipients destinatário(s)',
      if (profileLabel.isNotEmpty) profileLabel,
      if (createdAt != null) _formatDateTime(createdAt),
    ];

    return parts.join(' • ');
  }

  String _scheduleModeLabel(String value) {
    switch (value) {
      case 'profile':
        return 'Por perfil';
      case 'single_user':
        return '1 usuário';
      case 'multiple_users':
        return 'Vários usuários';
      default:
        return value;
    }
  }

  String _scheduleStatusLabel(Map<String, dynamic> schedule) {
    final isActive = schedule['is_active'] == true;
    final status = (schedule['status'] ?? '').toString().trim().toLowerCase();
    final sentAt = DateTime.tryParse(
      (schedule['sent_at'] ?? '').toString(),
    )?.toLocal();
    final nextRun = DateTime.tryParse(
      (schedule['next_run_at'] ?? '').toString(),
    )?.toLocal();

    if (!isActive) return 'Inativo';
    if (status == 'error') return 'Erro';
    if (status == 'sent' && sentAt != null) {
      return 'Enviado em ${_formatDateTime(sentAt)}';
    }
    if (nextRun != null) {
      return 'Agendado para ${_formatDateTime(nextRun)}';
    }
    return status.isEmpty ? 'Pendente' : status;
  }

  String _scheduleSubtitle(Map<String, dynamic> schedule) {
    final parts = <String>[];

    final mode = (schedule['target_mode'] ?? '').toString().trim();
    if (mode.isNotEmpty) {
      parts.add(_scheduleModeLabel(mode));
    }

    final profile = (schedule['target_user_type'] ?? '').toString().trim();
    if (profile.isNotEmpty) {
      parts.add(_profileLabelFromValue(profile));
    }

    final gender = (schedule['gender_filter'] ?? '').toString().trim();
    if (gender.isNotEmpty && gender.toLowerCase() != 'all') {
      parts.add(gender);
    }

    final courtPosition =
        (schedule['target_court_position'] ?? '').toString().trim();
    if (courtPosition.isNotEmpty) {
      parts.add(courtPosition);
    }

    final channel = (schedule['delivery_channel'] ?? '').toString().trim();
    if (channel.isNotEmpty) {
      parts.add(_deliveryChannelLabel(channel));
    }

    parts.add(_scheduleStatusLabel(schedule));

    return parts.join(' • ');
  }

  String _deliveryChannelLabel(String value) {
    switch (value) {
      case 'in_app':
        return 'Apenas no mural';
      case 'push':
        return 'Apenas push';
      case 'both':
        return 'Push + mural';
      default:
        return value;
    }
  }

  bool get _isSelectingThreads => _selectedThreadIds.isNotEmpty;

  void _toggleThreadSelection(String threadId) {
    if (threadId.isEmpty) return;
    setState(() {
      if (_selectedThreadIds.contains(threadId)) {
        _selectedThreadIds.remove(threadId);
      } else {
        _selectedThreadIds.add(threadId);
      }
    });
  }

  void _cancelThreadSelection() {
    if (_selectedThreadIds.isEmpty) return;
    setState(() {
      _selectedThreadIds.clear();
    });
  }

  bool get _allThreadsSelected =>
      _visibleSentThreads.isNotEmpty &&
      _selectedThreadIds.length == _visibleSentThreads.length;

  void _toggleSelectAllThreads() {
    setState(() {
      if (_allThreadsSelected) {
        _selectedThreadIds.clear();
      } else {
        _selectedThreadIds
          ..clear()
          ..addAll(
            _visibleSentThreads
                .map((item) => (item['id'] ?? '').toString())
                .where((id) => id.isNotEmpty),
          );
      }
    });
  }

  Future<void> _deleteSelectedThreads() async {
    if (_selectedThreadIds.isEmpty) return;

    final threadIds = _selectedThreadIds.toList(growable: false);

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Excluir mensagens enviadas'),
        content: Text(
          'Deseja excluir ${threadIds.length} mensagem(ns) enviada(s)? Essa exclusão será refletida para todos os perfis.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await supabase
          .from('app_messages')
          .delete()
          .inFilter('thread_id', threadIds);
      await supabase
          .from('app_message_participants')
          .delete()
          .inFilter('thread_id', threadIds);
      await supabase
          .from('app_message_threads')
          .delete()
          .inFilter('id', threadIds);

      if (!mounted) return;
      setState(() {
        _sentThreads.removeWhere(
          (item) => threadIds.contains((item['id'] ?? '').toString()),
        );
        _selectedThreadIds.clear();
      });
      _showSnack('Conversas selecionadas excluídas com sucesso.');
    } catch (e) {
      _showSnack('Erro ao excluir conversas selecionadas: $e');
    }
  }

  Future<void> _deleteThread(Map<String, dynamic> thread) async {
    final threadId = (thread['id'] ?? '').toString();
    if (threadId.isEmpty) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Excluir mensagem'),
        content: const Text(
          'Essa exclusão será refletida para todos os perfis. Deseja continuar?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await supabase.from('app_messages').delete().eq('thread_id', threadId);
      await supabase
          .from('app_message_participants')
          .delete()
          .eq('thread_id', threadId);
      await supabase.from('app_message_threads').delete().eq('id', threadId);

      if (!mounted) return;
      setState(() {
        _sentThreads.removeWhere((item) => item['id'].toString() == threadId);
      });
      _showSnack('Mensagem excluída para todos os perfis.');
    } catch (e) {
      _showSnack('Erro ao excluir mensagem: $e');
    }
  }

  Future<void> _deleteSchedule(Map<String, dynamic> schedule) async {
    final scheduleId = (schedule['id'] ?? '').toString();
    if (scheduleId.isEmpty) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Excluir agendamento'),
        content: const Text(
          'Essa mensagem programada será removida e não será mais enviada. Deseja continuar?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await supabase
          .from('app_message_schedules')
          .delete()
          .eq('id', scheduleId);

      if (!mounted) return;
      setState(() {
        _scheduledMessages.removeWhere(
          (item) => item['id'].toString() == scheduleId,
        );
      });
      _showSnack('Agendamento excluído com sucesso.');
    } catch (e) {
      _showSnack('Erro ao excluir agendamento: $e');
    }
  }

  void _showSnack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  String _formatDateTime(DateTime date) {
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    final year = date.year.toString();
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');
    return '$day/$month/$year $hour:$minute';
  }

  Widget _buildHeaderCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(Icons.mark_chat_unread_outlined),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Mensagens do Admin',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Veja conversas enviadas, agendamentos ativos e crie novas mensagens.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Nova mensagem',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Envie avisos, lembretes e comunicados na hora ou programados.',
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            FilledButton.icon(
              onPressed: _openCreatePage,
              icon: const Icon(Icons.add_comment_outlined),
              label: const Text('Criar mensagem'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildThreadCard(Map<String, dynamic> thread) {
    final threadId = (thread['id'] ?? '').toString();
    final isSelected = _selectedThreadIds.contains(threadId);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: _isSelectingThreads
            ? () => _toggleThreadSelection(threadId)
            : () => _openThread(thread),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_isSelectingThreads)
                Padding(
                  padding: const EdgeInsets.only(right: 8, top: 6),
                  child: Checkbox(
                    value: isSelected,
                    onChanged: (_) => _toggleThreadSelection(threadId),
                  ),
                )
              else
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.forum_outlined),
                ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      (thread['subject'] ?? '').toString(),
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _historySubtitle(thread),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      (thread['preview'] ?? '').toString(),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (!_isSelectingThreads)
                Column(
                  children: [
                    IconButton(
                      tooltip: 'Abrir conversa',
                      onPressed: () => _openThread(thread),
                      icon: const Icon(Icons.chevron_right),
                    ),
                    IconButton(
                      tooltip: 'Excluir para todos',
                      onPressed: () => _deleteThread(thread),
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildScheduleCard(Map<String, dynamic> schedule) {
    final messageBody = (schedule['message_body'] ?? '').toString();

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.tertiaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.schedule_send_outlined),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    (schedule['title'] ?? '').toString(),
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _scheduleSubtitle(schedule),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    messageBody,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Excluir agendamento',
              onPressed: () => _deleteSchedule(schedule),
              icon: const Icon(Icons.delete_outline),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionToggle({
    required String title,
    required bool expanded,
    required VoidCallback onTap,
    Widget? trailing,
  }) {
    final isScheduled = title.toLowerCase().contains('programadas');
    final accentColor =
        isScheduled ? const Color(0xFF8FE8FF) : const Color(0xFFFF4F93);
    final accentGlow =
        isScheduled ? const Color(0x338FE8FF) : const Color(0x33FF4F93);
    final panelColor =
        isScheduled ? const Color(0x804F5F66) : const Color(0x80664B5E);
    final iconData =
        isScheduled ? Icons.calendar_month_outlined : Icons.cake_outlined;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(0.22)),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [panelColor, Colors.white.withOpacity(0.08)],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.22),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: accentGlow,
                    border: Border.all(color: accentColor.withOpacity(0.55)),
                    boxShadow: [
                      BoxShadow(
                        color: accentGlow,
                        blurRadius: 16,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                  child: Icon(iconData, color: accentColor, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    isScheduled
                        ? 'Mensagens programadas'
                        : 'Mensagens enviadas',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
                if (trailing != null)
                  IconTheme(
                    data: const IconThemeData(color: Colors.white70),
                    child: trailing,
                  ),
                Icon(
                  expanded ? Icons.expand_less : Icons.expand_more,
                  color: Colors.white70,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCollapsedInfo(String text) {
    return Container(
      margin: const EdgeInsets.only(top: 8, bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.24),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.14)),
      ),
      child: Text(
        text,
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: Colors.white),
      ),
    );
  }

  String _monthKeyFromDate(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    return '${date.year}-$month';
  }

  String _monthLabel(String key) {
    if (key == 'Todos') return 'Todos';
    final parts = key.split('-');
    if (parts.length != 2) return key;

    const names = {
      '01': 'Jan',
      '02': 'Fev',
      '03': 'Mar',
      '04': 'Abr',
      '05': 'Mai',
      '06': 'Jun',
      '07': 'Jul',
      '08': 'Ago',
      '09': 'Set',
      '10': 'Out',
      '11': 'Nov',
      '12': 'Dez',
    };

    return '${names[parts[1]] ?? parts[1]}/${parts[0]}';
  }

  List<String> _scheduleMonthOptions() {
    final values = <String>{'Todos'};
    for (final item in _scheduledMessages) {
      final raw = (item['scheduled_for'] ??
              item['next_run_at'] ??
              item['created_at'] ??
              '')
          .toString();
      final date = DateTime.tryParse(raw)?.toLocal();
      if (date != null) {
        values.add(_monthKeyFromDate(date));
      }
    }
    final months = values.where((e) => e != 'Todos').toList()
      ..sort((a, b) => b.compareTo(a));
    return ['Todos', ...months];
  }

  List<String> _sentMonthOptions() {
    final values = <String>{'Todos'};
    for (final item in _sentThreads) {
      final raw =
          ((item['last_message_at'] ?? item['created_at']) ?? '').toString();
      final date = DateTime.tryParse(raw)?.toLocal();
      if (date != null) {
        values.add(_monthKeyFromDate(date));
      }
    }
    final months = values.where((e) => e != 'Todos').toList()
      ..sort((a, b) => b.compareTo(a));
    return ['Todos', ...months];
  }

  List<Map<String, dynamic>> get _visibleScheduledMessages {
    if (_scheduledMonthFilter == 'Todos') return _scheduledMessages;
    return _scheduledMessages.where((item) {
      final raw = (item['scheduled_for'] ??
              item['next_run_at'] ??
              item['created_at'] ??
              '')
          .toString();
      final date = DateTime.tryParse(raw)?.toLocal();
      return date != null && _monthKeyFromDate(date) == _scheduledMonthFilter;
    }).toList();
  }

  List<Map<String, dynamic>> get _visibleSentThreads {
    if (_sentMonthFilter == 'Todos') return _sentThreads;
    return _sentThreads.where((item) {
      final raw =
          ((item['last_message_at'] ?? item['created_at']) ?? '').toString();
      final date = DateTime.tryParse(raw)?.toLocal();
      return date != null && _monthKeyFromDate(date) == _sentMonthFilter;
    }).toList();
  }

  Widget _buildMonthFilter({
    required List<String> options,
    required String value,
    required ValueChanged<String?> onChanged,
  }) {
    return DropdownButtonFormField<String>(
      dropdownColor: Colors.grey.shade900,
      value: options.contains(value) ? value : 'Todos',
      isDense: true,
      style: const TextStyle(color: Colors.white, fontSize: 16),
      decoration: const InputDecoration(
        labelText: 'Mês',
        labelStyle: TextStyle(color: Colors.white),
        border: OutlineInputBorder(),
        enabledBorder: OutlineInputBorder(
          borderSide: BorderSide(color: Colors.white70),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: BorderSide(color: Colors.white),
        ),
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      ),
      iconEnabledColor: Colors.white,
      items: options
          .map(
            (item) => DropdownMenuItem<String>(
              value: item,
              child: Text(
                _monthLabel(item),
                style: const TextStyle(color: Colors.white),
              ),
            ),
          )
          .toList(),
      onChanged: onChanged,
    );
  }

  Widget _buildExpandedSectionPanel({
    required bool isScheduled,
    required Widget child,
  }) {
    final panelColor =
        isScheduled ? const Color(0x664F5F66) : const Color(0x66664B5E);

    return Container(
      margin: const EdgeInsets.only(top: 8, bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.18)),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [panelColor, Colors.white.withOpacity(0.06)],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.20),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return RefreshIndicator(
      onRefresh: _refreshAll,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _buildHeaderCard(),
          const SizedBox(height: 12),
          _buildActionCard(),
          const SizedBox(height: 16),
          _buildSectionToggle(
            title: 'Mensagens programadas',
            expanded: _showScheduledSection,
            onTap: () {
              setState(() {
                _showScheduledSection = !_showScheduledSection;
              });
            },
            trailing: IconButton(
              tooltip: 'Atualizar agendamentos',
              onPressed: _loadingSchedules ? null : _loadScheduledMessages,
              icon: const Icon(Icons.refresh),
            ),
          ),
          if (!_showScheduledSection)
            _buildCollapsedInfo(
              _scheduledMessages.isEmpty
                  ? 'Nenhuma mensagem programada.'
                  : '${_visibleScheduledMessages.length} de ${_scheduledMessages.length} agendamento(s). Toque para visualizar.',
            )
          else
            _buildExpandedSectionPanel(
              isScheduled: true,
              child: Column(
                children: [
                  _buildMonthFilter(
                    options: _scheduleMonthOptions(),
                    value: _scheduledMonthFilter,
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() => _scheduledMonthFilter = value);
                    },
                  ),
                  const SizedBox(height: 10),
                  if (_loadingSchedules && _scheduledMessages.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (_visibleScheduledMessages.isEmpty)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          children: const [
                            Icon(Icons.schedule_send_outlined, size: 48),
                            SizedBox(height: 12),
                            Text(
                              'Nenhuma mensagem programada até o momento.',
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    ..._visibleScheduledMessages.map(_buildScheduleCard),
                ],
              ),
            ),
          const SizedBox(height: 12),
          _buildSectionToggle(
            title: 'Mensagens enviadas',
            expanded: _showSentSection,
            onTap: () {
              setState(() {
                _showSentSection = !_showSentSection;
              });
            },
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!_isSelectingThreads && _showSentSection)
                  TextButton.icon(
                    onPressed: _visibleSentThreads.isEmpty
                        ? null
                        : () {
                            final firstId =
                                (_sentThreads.first['id'] ?? '').toString();
                            if (firstId.isNotEmpty) {
                              _toggleThreadSelection(firstId);
                            }
                          },
                    icon: const Icon(Icons.checklist),
                    label: const Text('Selecionar'),
                    style: TextButton.styleFrom(foregroundColor: Colors.white),
                  ),
                IconButton(
                  tooltip: 'Atualizar histórico',
                  onPressed: _loadingHistory ? null : _loadSentThreads,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
          ),
          if (!_showSentSection)
            _buildCollapsedInfo(
              _sentThreads.isEmpty
                  ? 'Nenhuma mensagem enviada.'
                  : '${_visibleSentThreads.length} de ${_sentThreads.length} mensagem(ns) enviada(s). Toque para visualizar.',
            )
          else
            _buildExpandedSectionPanel(
              isScheduled: false,
              child: Column(
                children: [
                  _buildMonthFilter(
                    options: _sentMonthOptions(),
                    value: _sentMonthFilter,
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() => _sentMonthFilter = value);
                    },
                  ),
                  const SizedBox(height: 10),
                  if (_loadingHistory && _sentThreads.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (_visibleSentThreads.isEmpty)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          children: [
                            const Icon(Icons.mark_chat_read_outlined, size: 48),
                            const SizedBox(height: 12),
                            const Text(
                              'Nenhuma mensagem enviada até o momento.',
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 12),
                            FilledButton.icon(
                              onPressed: _openCreatePage,
                              icon: const Icon(Icons.add),
                              label: const Text('Criar primeira mensagem'),
                            ),
                          ],
                        ),
                      ),
                    )
                  else ...[
                    ..._visibleSentThreads.map(_buildThreadCard),
                    if (_hasMoreSentThreads && _sentMonthFilter == 'Todos')
                      Padding(
                        padding: const EdgeInsets.only(top: 4, bottom: 8),
                        child: OutlinedButton.icon(
                          onPressed:
                              _loadingHistory ? null : _loadMoreSentThreads,
                          icon: _loadingHistory
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.expand_more_rounded),
                          label: const Text('Carregar mensagens anteriores'),
                        ),
                      ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: _isSelectingThreads
            ? IconButton(
                onPressed: _cancelThreadSelection,
                icon: const Icon(Icons.close),
              )
            : null,
        title: Text(
          _isSelectingThreads
              ? '${_selectedThreadIds.length} selecionada(s)'
              : 'Mensagens',
        ),
        actions: [
          if (_isSelectingThreads)
            TextButton(
              onPressed: _toggleSelectAllThreads,
              child: Text(
                _allThreadsSelected ? 'Desmarcar todas' : 'Selecionar todas',
              ),
            ),
          if (_isSelectingThreads)
            IconButton(
              tooltip: 'Excluir selecionadas',
              onPressed: _deleteSelectedThreads,
              icon: const Icon(Icons.delete_outline),
            ),
        ],
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: const OlympusBrandBackgroundImage(
              fit: BoxFit.cover,
            ),
          ),
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withOpacity(0.45),
                    Colors.black.withOpacity(0.65),
                  ],
                ),
              ),
            ),
          ),
          _buildBody(),
        ],
      ),
    );
  }
}

class AdminCreateMessagePage extends StatefulWidget {
  const AdminCreateMessagePage({super.key});

  @override
  State<AdminCreateMessagePage> createState() => _AdminCreateMessagePageState();
}

class _AdminCreateMessagePageState extends State<AdminCreateMessagePage> {
  final SupabaseClient supabase = Supabase.instance.client;

  Color get _olympusBlue => olympusBlue;
  Color get _olympusBlueLight =>
      Color.lerp(olympusBlue, Colors.white, 0.18)!;
  Color get _olympusGold => olympusGold;
  static const Color _olympusCream = Color(0xFFFFFBF3);

  final TextEditingController _subjectController = TextEditingController();
  final TextEditingController _messageController = TextEditingController();
  final TextEditingController _templateTitleController =
      TextEditingController();
  final TextEditingController _templateBodyController = TextEditingController();
  final TextEditingController _userSearchController = TextEditingController();

  bool _loading = true;
  bool _sending = false;
  bool _allowReply = true;
  bool _isUrgent = false;
  bool _scheduleSend = false;

  DateTime? _scheduledDate;
  TimeOfDay? _scheduledTime;

  String _sendMode = 'Por perfil';
  String? _selectedProfile;
  String? _selectedGender;
  String? _selectedTemplateKey;
  String? _selectedCourtPosition;
  String _deliveryChannel = 'both';
  String _deviceTimezone = 'UTC';

  List<Map<String, dynamic>> _allUsers = [];
  List<Map<String, dynamic>> _filteredUsers = [];
  final List<Map<String, dynamic>> _selectedUsers = [];

  static const List<Map<String, String>> _defaultTemplates = [
    {
      'title': 'Aviso geral',
      'body': 'Olá! Temos um novo aviso importante. Confira no app.',
    },
    {
      'title': 'Lembrete',
      'body': 'Olá! Passando para lembrar você do compromisso agendado.',
    },
  ];

  List<Map<String, String>> _templates = _defaultTemplates
      .map((template) => Map<String, String>.from(template))
      .toList();

  static const List<String> _sendModes = [
    'Por perfil',
    '1 usuário',
    'Vários usuários',
  ];

  static const Map<String, String> _fixedProfileLabels = {
    'athlete': 'Atleta',
    'coach': 'Técnico',
    'member': 'Membro',
  };

  static const Map<String, String> _profileAliases = {
    'athlete': 'athlete',
    'atleta': 'athlete',
    'coach': 'coach',
    'tecnico': 'coach',
    'técnico': 'coach',
    'treinador': 'coach',
    'trainer': 'coach',
    'member': 'member',
    'membro': 'member',
  };

  static const Map<String, String> _deliveryChannelLabels = {
    'in_app': 'Apenas no mural',
    'push': 'Apenas push',
    'both': 'Push + mural',
  };

  @override
  void initState() {
    super.initState();
    _subjectController.addListener(_onDraftChanged);
    _messageController.addListener(_onDraftChanged);
    _bootstrap();
  }

  void _onDraftChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _subjectController.removeListener(_onDraftChanged);
    _messageController.removeListener(_onDraftChanged);
    _subjectController.dispose();
    _messageController.dispose();
    _templateTitleController.dispose();
    _templateBodyController.dispose();
    _userSearchController.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    await _loadDeviceTimezone();
    await Future.wait([_loadUsers(), _loadTemplates()]);
  }

  Future<void> _loadDeviceTimezone() async {
    final timezone = DateTime.now().timeZoneName.trim();
    if (!mounted) return;
    setState(() {
      _deviceTimezone = timezone.isEmpty ? 'UTC' : timezone;
    });
  }

  Future<void> _loadUsers() async {
    if (mounted) setState(() => _loading = true);

    try {
      final response = await supabase
          .from('profiles')
          .select('id, user_type, full_name, email, gender, court_position')
          .neq('user_type', 'admin')
          .eq('is_active', true)
          .order('full_name', ascending: true);

      _allUsers = List<Map<String, dynamic>>.from(response);
      _applyFilter();
    } catch (e) {
      _showSnack('Erro ao carregar usuários: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _normalizeProfileValue(String value) {
    final normalized = value.trim().toLowerCase();
    return _profileAliases[normalized] ?? normalized;
  }

  String _profileLabelFromValue(String value) {
    final normalized = _normalizeProfileValue(value);
    return _fixedProfileLabels[normalized] ?? value.trim();
  }

  bool _matchesProfile(dynamic userType, String? selectedProfile) {
    if (selectedProfile == null || selectedProfile.trim().isEmpty) return false;
    return _normalizeProfileValue((userType ?? '').toString()) ==
        _normalizeProfileValue(selectedProfile);
  }

  List<String> get _profiles {
    final values = <String>{..._fixedProfileLabels.keys};

    for (final user in _allUsers) {
      final profile = (user['user_type'] ?? '').toString().trim();
      if (profile.isNotEmpty) {
        values.add(_normalizeProfileValue(profile));
      }
    }

    final profiles = values.toList()
      ..sort(
        (a, b) => _profileLabelFromValue(
          a,
        ).toLowerCase().compareTo(_profileLabelFromValue(b).toLowerCase()),
      );
    return profiles;
  }

  List<String> get _genders {
    final values = _allUsers
        .map((e) => (e['gender'] ?? '').toString().trim())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    return values;
  }

  List<String> get _courtPositions {
    final values = _allUsers
        .where(
          (e) =>
              _normalizeProfileValue((e['user_type'] ?? '').toString()) ==
              'athlete',
        )
        .map((e) => (e['court_position'] ?? '').toString().trim())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    return values;
  }

  String? _singleOrNullValue(String? value, List<String> options) {
    if (value == null || value.isEmpty) return null;
    return options.where((item) => item == value).length == 1 ? value : null;
  }

  String _templateKey(Map<String, String> template) {
    return '${template['title'] ?? ''}__${template['body'] ?? ''}';
  }

  String? _singleOrNullTemplateKey(String? value) {
    if (value == null || value.isEmpty) return null;
    return _templates
                .where((template) => _templateKey(template) == value)
                .length ==
            1
        ? value
        : null;
  }

  Future<void> _loadTemplates() async {
    final admin = supabase.auth.currentUser;
    if (admin == null) return;

    try {
      final profile = await supabase
          .from('profiles')
          .select('permissions')
          .eq('id', admin.id)
          .maybeSingle();

      final permissions = Map<String, dynamic>.from(
        (profile?['permissions'] as Map?) ?? const {},
      );

      final savedTemplatesRaw = permissions['admin_message_templates'];
      final savedTemplates = <Map<String, String>>[];

      if (savedTemplatesRaw is List) {
        for (final item in savedTemplatesRaw) {
          if (item is Map) {
            final title = (item['title'] ?? '').toString().trim();
            final body = (item['body'] ?? '').toString().trim();
            if (title.isNotEmpty && body.isNotEmpty) {
              savedTemplates.add({'title': title, 'body': body});
            }
          }
        }
      }

      final merged = <String, Map<String, String>>{};
      for (final template in [..._defaultTemplates, ...savedTemplates]) {
        merged[_templateKey(template)] = Map<String, String>.from(template);
      }

      if (!mounted) return;
      setState(() {
        _templates = merged.values.toList();
      });
    } catch (_) {}
  }

  Future<void> _persistTemplates() async {
    final admin = supabase.auth.currentUser;
    if (admin == null) return;

    try {
      final profile = await supabase
          .from('profiles')
          .select('permissions')
          .eq('id', admin.id)
          .maybeSingle();

      final permissions = Map<String, dynamic>.from(
        (profile?['permissions'] as Map?) ?? const {},
      );

      permissions['admin_message_templates'] = _templates
          .map(
            (template) => {
              'title': template['title'] ?? '',
              'body': template['body'] ?? '',
            },
          )
          .toList();

      await supabase
          .from('profiles')
          .update({'permissions': permissions}).eq('id', admin.id);
    } catch (_) {}
  }

  void _applyFilter() {
    var users = List<Map<String, dynamic>>.from(_allUsers);

    if (_sendMode == 'Por perfil' && _selectedProfile != null) {
      users = users
          .where((u) => _matchesProfile(u['user_type'], _selectedProfile))
          .toList();

      final isAthleteProfile =
          _normalizeProfileValue(_selectedProfile ?? '') == 'athlete';

      if (isAthleteProfile &&
          _selectedCourtPosition != null &&
          _selectedCourtPosition!.isNotEmpty) {
        users = users
            .where(
              (u) =>
                  (u['court_position'] ?? '').toString().trim() ==
                  _selectedCourtPosition,
            )
            .toList();
      }
    }

    if ((_sendMode == '1 usuário' || _sendMode == 'Vários usuários') &&
        _selectedGender != null &&
        _selectedGender!.isNotEmpty) {
      users = users
          .where((u) => (u['gender'] ?? '').toString() == _selectedGender)
          .toList();
    }

    users.sort((a, b) {
      final nameA = (a['full_name'] ?? '').toString().toLowerCase().trim();
      final nameB = (b['full_name'] ?? '').toString().toLowerCase().trim();
      return nameA.compareTo(nameB);
    });

    _filteredUsers = users;

    _selectedUsers.removeWhere(
      (selected) => !_filteredUsers.any(
        (item) => item['id'].toString() == selected['id'].toString(),
      ),
    );

    if (mounted) setState(() {});
  }

  void _toggleUser(Map<String, dynamic> user) {
    final exists = _selectedUsers.any(
      (u) => u['id'].toString() == user['id'].toString(),
    );

    setState(() {
      if (exists) {
        _selectedUsers.removeWhere(
          (u) => u['id'].toString() == user['id'].toString(),
        );
      } else {
        if (_sendMode == '1 usuário') {
          _selectedUsers
            ..clear()
            ..add(user);
        } else {
          _selectedUsers.add(user);
        }
      }
    });
  }

  void _clearSelection() {
    setState(() {
      _selectedUsers.clear();
    });
  }

  void _selectAllFiltered() {
    if (_sendMode == '1 usuário') return;
    setState(() {
      _selectedUsers
        ..clear()
        ..addAll(_filteredUsers);
    });
  }

  int get _selectedFilteredCount {
    final filteredIds = _filteredUsers
        .map((user) => (user['id'] ?? '').toString())
        .where((id) => id.isNotEmpty)
        .toSet();

    return _selectedUsers
        .where((user) => filteredIds.contains((user['id'] ?? '').toString()))
        .length;
  }

  Future<void> _openUserSelectionSheet() async {
    final tempSelectedIds = _selectedUsers
        .map((user) => (user['id'] ?? '').toString())
        .where((id) => id.isNotEmpty)
        .toSet();

    _userSearchController.clear();
    var localSearch = '';

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, modalSetState) {
            final visibleUsers = _filteredUsers.where((user) {
              final query = localSearch.trim().toLowerCase();
              final name = (user['full_name'] ?? '').toString().toLowerCase();
              final subtitle = _userSubtitle(user).toLowerCase();

              if (query.isEmpty) return true;
              return name.contains(query) || subtitle.contains(query);
            }).toList();

            void toggleLocalUser(Map<String, dynamic> user) {
              final userId = (user['id'] ?? '').toString();
              if (userId.isEmpty) return;

              modalSetState(() {
                if (tempSelectedIds.contains(userId)) {
                  tempSelectedIds.remove(userId);
                } else {
                  if (_sendMode == '1 usuário') {
                    tempSelectedIds
                      ..clear()
                      ..add(userId);
                  } else {
                    tempSelectedIds.add(userId);
                  }
                }
              });
            }

            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 16,
                bottom: MediaQuery.of(context).viewInsets.bottom + 16,
              ),
              child: SizedBox(
                height: MediaQuery.of(context).size.height * 0.82,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _sendMode == '1 usuário'
                          ? 'Selecionar usuário'
                          : 'Selecionar usuários',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _userSearchController,
                      decoration: const InputDecoration(
                        hintText: 'Buscar por nome, perfil, posição ou gênero',
                        prefixIcon: Icon(Icons.search),
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (value) {
                        modalSetState(() {
                          localSearch = value;
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${tempSelectedIds.length} selecionado(s)',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),
                        if (_sendMode == 'Vários usuários')
                          TextButton(
                            onPressed: () {
                              modalSetState(() {
                                tempSelectedIds
                                  ..clear()
                                  ..addAll(
                                    visibleUsers
                                        .map(
                                          (user) =>
                                              (user['id'] ?? '').toString(),
                                        )
                                        .where((id) => id.isNotEmpty),
                                  );
                              });
                            },
                            child: const Text('Selecionar visíveis'),
                          ),
                        TextButton(
                          onPressed: () {
                            modalSetState(() {
                              tempSelectedIds.clear();
                            });
                          },
                          child: const Text('Limpar'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: visibleUsers.isEmpty
                          ? const Center(
                              child: Text('Nenhum usuário encontrado.'),
                            )
                          : ListView.builder(
                              itemCount: visibleUsers.length,
                              itemBuilder: (context, index) {
                                final user = visibleUsers[index];
                                final userId = (user['id'] ?? '').toString();
                                final selected = tempSelectedIds.contains(
                                  userId,
                                );
                                final subtitle = _userSubtitle(user);

                                return CheckboxListTile(
                                  value: selected,
                                  onChanged: (_) => toggleLocalUser(user),
                                  title: Text(
                                    (user['full_name'] ?? '').toString(),
                                  ),
                                  subtitle:
                                      subtitle.isEmpty ? null : Text(subtitle),
                                  controlAffinity:
                                      ListTileControlAffinity.trailing,
                                  contentPadding: EdgeInsets.zero,
                                );
                              },
                            ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () {
                          setState(() {
                            _selectedUsers
                              ..clear()
                              ..addAll(
                                _allUsers.where(
                                  (user) => tempSelectedIds.contains(
                                    (user['id'] ?? '').toString(),
                                  ),
                                ),
                              );
                          });
                          Navigator.of(context).pop();
                        },
                        child: const Text('Confirmar seleção'),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _applyTemplate(Map<String, String>? template) {
    if (template == null) return;
    setState(() {
      _selectedTemplateKey = _templateKey(template);
      _subjectController.text = template['title'] ?? '';
      _messageController.text = template['body'] ?? '';
    });
  }

  Future<void> _openCreateTemplateDialog() async {
    _templateTitleController.clear();
    _templateBodyController.clear();

    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Criar modelo de mensagem'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _templateTitleController,
                decoration: const InputDecoration(
                  labelText: 'Título do modelo',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _templateBodyController,
                minLines: 4,
                maxLines: 6,
                decoration: const InputDecoration(
                  labelText: 'Texto do modelo',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              final title = _templateTitleController.text.trim();
              final body = _templateBodyController.text.trim();

              if (title.isEmpty || body.isEmpty) {
                _showSnack('Preencha título e mensagem padrão.');
                return;
              }

              final template = {'title': title, 'body': body};

              setState(() {
                _templates.removeWhere(
                  (item) => _templateKey(item) == _templateKey(template),
                );
                _templates.add(template);
                _selectedTemplateKey = _templateKey(template);
              });

              _persistTemplates();
              Navigator.of(context).pop();
              _showSnack('Modelo criado.');
            },
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
  }

  Future<void> _sendPushNotification({
    required List<String> recipientUserIds,
    required String title,
    required String body,
    String? threadId,
    required bool isUrgent,
  }) async {
    if (recipientUserIds.isEmpty) return;

    try {
      await supabase.functions.invoke(
        'send-push-notification',
        body: {
          'recipientUserIds': recipientUserIds,
          'title': isUrgent ? 'URGENTE: $title' : title,
          'body': 'Nova mensagem',
          'type': 'platform_message',
          'threadId': threadId,
        },
      );
    } catch (e) {
      debugPrint('Erro ao enviar push de admin: $e');
    }
  }

  String _buildPreview(String body) {
    final normalized = body.replaceAll('\n', ' ').trim();
    if (normalized.length <= 120) return normalized;
    return '${normalized.substring(0, 120)}...';
  }

  String _buildTargetMode() {
    switch (_sendMode) {
      case 'Por perfil':
        return 'profile';
      case '1 usuário':
        return 'single_user';
      case 'Vários usuários':
        return 'multiple_users';
      default:
        return 'custom';
    }
  }

  DateTime? _buildScheduledDateTime() {
    if (_scheduledDate == null || _scheduledTime == null) return null;

    return DateTime(
      _scheduledDate!.year,
      _scheduledDate!.month,
      _scheduledDate!.day,
      _scheduledTime!.hour,
      _scheduledTime!.minute,
    );
  }

  String? _buildScheduledTimeOfDay() {
    if (_scheduledTime == null) return null;
    return '${_scheduledTime!.hour.toString().padLeft(2, '0')}:'
        '${_scheduledTime!.minute.toString().padLeft(2, '0')}:00';
  }

  String _toUtcIsoString(DateTime value) {
    return value.toUtc().toIso8601String();
  }

  Future<List<Map<String, dynamic>>> _resolveRecipients() async {
    List<Map<String, dynamic>> recipients = [];

    switch (_sendMode) {
      case 'Por perfil':
        if (_selectedProfile == null || _selectedProfile!.isEmpty) {
          throw Exception('Selecione um perfil.');
        }
        recipients = _allUsers
            .where((u) => _matchesProfile(u['user_type'], _selectedProfile))
            .where(
              (u) =>
                  _selectedCourtPosition == null ||
                  _selectedCourtPosition!.isEmpty ||
                  (u['court_position'] ?? '').toString().trim() ==
                      _selectedCourtPosition,
            )
            .toList();
        break;
      case '1 usuário':
        if (_selectedUsers.length != 1) {
          throw Exception('Selecione exatamente 1 usuário.');
        }
        recipients = List<Map<String, dynamic>>.from(_selectedUsers);
        break;
      case 'Vários usuários':
        if (_selectedUsers.isEmpty) {
          throw Exception('Selecione ao menos 1 usuário.');
        }
        recipients = List<Map<String, dynamic>>.from(_selectedUsers);
        break;
    }

    if (recipients.isEmpty) {
      throw Exception('Nenhum destinatário encontrado.');
    }

    final admin = supabase.auth.currentUser;
    final dedupRecipients = <String, Map<String, dynamic>>{};
    for (final user in recipients) {
      final id = (user['id'] ?? '').toString();
      if (id.isNotEmpty && id != admin?.id) {
        dedupRecipients[id] = user;
      }
    }

    final resolved = dedupRecipients.values.toList();

    if (resolved.isEmpty) {
      throw Exception('Nenhum destinatário válido encontrado.');
    }

    return resolved;
  }

  Future<void> _scheduleMessage() async {
    final admin = supabase.auth.currentUser;
    if (admin == null) {
      _showSnack('Usuário admin não autenticado.');
      return;
    }

    final subject = _subjectController.text.trim();
    final body = _messageController.text.trim();

    if (subject.isEmpty || body.isEmpty) {
      _showSnack('Preencha assunto e mensagem.');
      return;
    }

    final scheduledDateTime = _buildScheduledDateTime();
    if (scheduledDateTime == null) {
      _showSnack('Selecione data e horário do envio.');
      return;
    }

    if (!scheduledDateTime.isAfter(DateTime.now())) {
      _showSnack('Escolha um horário futuro para o agendamento.');
      return;
    }

    setState(() => _sending = true);

    try {
      final recipients = await _resolveRecipients();
      final nowUtc = DateTime.now().toUtc();

      final payload = <String, dynamic>{
        'title': subject,
        'message_body': body,
        'target_mode': _buildTargetMode(),
        'target_user_type': _selectedProfile,
        'target_user_id': _sendMode == '1 usuário' && recipients.isNotEmpty
            ? recipients.first['id']
            : null,
        'target_user_ids': _sendMode == 'Vários usuários'
            ? recipients
                .map((user) => (user['id'] ?? '').toString())
                .where((id) => id.isNotEmpty)
                .toList()
            : null,
        'gender_filter': _selectedGender,
        'frequency': 'once',
        'weekdays': null,
        'day_of_month': null,
        'time_of_day': _buildScheduledTimeOfDay(),
        'timezone': _deviceTimezone,
        'is_active': true,
        'last_run_at': null,
        'next_run_at': _toUtcIsoString(scheduledDateTime),
        'created_by': admin.id,
        'created_at': nowUtc.toIso8601String(),
        'updated_at': nowUtc.toIso8601String(),
        'target_court_position': _selectedCourtPosition,
        'delivery_channel': _deliveryChannel,
        'is_urgent': _isUrgent,
        'scheduled_for': _toUtcIsoString(scheduledDateTime),
        'status': 'pending',
        'sent_at': null,
      };

      await supabase.from('app_message_schedules').insert(payload);

      if (!mounted) return;
      _showSnack('Mensagem programada com sucesso.');
      Navigator.of(context).pop(true);
    } catch (e) {
      _showSnack('Erro ao programar mensagem: $e');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _sendMessage() async {
    final admin = supabase.auth.currentUser;
    if (admin == null) {
      _showSnack('Usuário admin não autenticado.');
      return;
    }

    final subject = _subjectController.text.trim();
    final body = _messageController.text.trim();

    if (subject.isEmpty || body.isEmpty) {
      _showSnack('Preencha assunto e mensagem.');
      return;
    }

    setState(() => _sending = true);

    try {
      final recipients = await _resolveRecipients();

      final adminProfile = await supabase
          .from('profiles')
          .select('full_name, user_type')
          .eq('id', admin.id)
          .maybeSingle();

      final adminName = (adminProfile?['full_name'] ?? 'Admin').toString();
      final adminType = (adminProfile?['user_type'] ?? 'admin').toString();
      final now = DateTime.now().toUtc().toIso8601String();

      final thread = await supabase
          .from('app_message_threads')
          .insert({
            'subject': subject,
            'created_by': admin.id,
            'created_by_name': adminName,
            'created_by_type': adminType,
            'allow_reply': _allowReply,
            'created_at': now,
            'last_message_at': now,
            'target_mode': _buildTargetMode(),
            'target_user_type': _selectedProfile,
            'preview': _buildPreview(body),
          })
          .select()
          .single();

      final threadId = thread['id'].toString();

      final participants = <Map<String, dynamic>>[
        {
          'thread_id': threadId,
          'user_id': admin.id,
          'is_admin_sender': true,
          'unread_count': 0,
          'is_read': true,
          'viewed_at': now,
          'created_at': now,
        },
        ...recipients.map(
          (user) => {
            'thread_id': threadId,
            'user_id': user['id'],
            'is_admin_sender': false,
            'unread_count': 1,
            'is_read': false,
            'viewed_at': null,
            'created_at': now,
          },
        ),
      ];

      await supabase.from('app_message_participants').insert(participants);

      await supabase.from('app_messages').insert({
        'thread_id': threadId,
        'sender_id': admin.id,
        'sender_name': adminName,
        'sender_type': adminType,
        'body': body,
        'created_at': now,
      });

      if (_deliveryChannel == 'push' || _deliveryChannel == 'both') {
        final recipientIds = recipients
            .map((e) => e['id'].toString())
            .where((e) => e.isNotEmpty)
            .toSet()
            .toList();

        if (recipientIds.isNotEmpty) {
          await _sendPushNotification(
            recipientUserIds: recipientIds,
            title: subject,
            body: body,
            threadId: threadId,
            isUrgent: _isUrgent,
          );
        }
      }

      if (!mounted) return;
      _showSnack('Mensagem enviada com sucesso.');
      Navigator.of(context).pop(true);
    } catch (e) {
      _showSnack('Erro ao enviar mensagem: $e');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _pickScheduledDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _scheduledDate ?? now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );

    if (picked == null) return;

    setState(() {
      _scheduledDate = picked;
    });
  }

  Future<void> _pickScheduledTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _scheduledTime ?? TimeOfDay.now(),
    );

    if (picked == null) return;

    setState(() {
      _scheduledTime = picked;
    });
  }

  String _formattedScheduledDate() {
    if (_scheduledDate == null) return 'Selecionar data';
    return '${_scheduledDate!.day.toString().padLeft(2, '0')}/'
        '${_scheduledDate!.month.toString().padLeft(2, '0')}/'
        '${_scheduledDate!.year}';
  }

  String _formattedScheduledTime() {
    if (_scheduledTime == null) return 'Selecionar hora';
    return '${_scheduledTime!.hour.toString().padLeft(2, '0')}:'
        '${_scheduledTime!.minute.toString().padLeft(2, '0')}';
  }

  void _showSnack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  int get _recipientCount {
    if (_sendMode == 'Por perfil') {
      return _selectedProfile == null ? 0 : _filteredUsers.length;
    }
    return _selectedUsers.length;
  }

  String get _recipientSummary {
    if (_sendMode == 'Por perfil') {
      if (_selectedProfile == null) return 'Escolha o perfil dos destinatários';
      return '${_profileLabelFromValue(_selectedProfile!)} • '
          '$_recipientCount destinatário(s)';
    }
    if (_selectedUsers.isEmpty) return 'Nenhum destinatário selecionado';
    if (_selectedUsers.length == 1) {
      return (_selectedUsers.first['full_name'] ?? '1 destinatário').toString();
    }
    return '${_selectedUsers.length} destinatários selecionados';
  }

  double get _composerProgress {
    var completed = 0;
    if (_recipientCount > 0) completed++;
    if (_subjectController.text.trim().isNotEmpty) completed++;
    if (_messageController.text.trim().isNotEmpty) completed++;
    if (!_scheduleSend || (_scheduledDate != null && _scheduledTime != null))
      completed++;
    return completed / 4;
  }

  bool get _composerReady => _composerProgress == 1;

  Widget _buildComposerHero() {
    final percent = (_composerProgress * 100).round();
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          colors: [_olympusBlue, _olympusBlueLight],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: _olympusGold.withOpacity(0.62)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.22),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _olympusGold.withOpacity(0.18),
                  border: Border.all(color: _olympusGold.withOpacity(0.7)),
                ),
                child: Icon(Icons.campaign_rounded, color: _olympusGold),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Central de comunicação',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Configure, revise e envie em poucos passos.',
                      style: TextStyle(color: Color(0xFFD9E8F7), fontSize: 12),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '$percent%',
                  style: TextStyle(
                    color: _olympusGold,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 15),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: _composerProgress,
              minHeight: 7,
              backgroundColor: Colors.white.withOpacity(0.16),
              valueColor: AlwaysStoppedAnimation<Color>(_olympusGold),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(
                Icons.people_alt_rounded,
                size: 17,
                color: _olympusGold,
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  _recipientSummary,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSectionCard({
    required String title,
    String? subtitle,
    required IconData icon,
    required int step,
    required Widget child,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: _olympusCream.withOpacity(0.97),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withOpacity(0.82)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF05182E).withOpacity(0.18),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: _olympusBlue.withOpacity(0.09),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(icon, color: _olympusBlue, size: 21),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'ETAPA $step',
                        style: TextStyle(
                          color: _olympusGold,
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.1,
                        ),
                      ),
                      Text(
                        title,
                        style: TextStyle(
                          color: _olympusBlue,
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (subtitle != null && subtitle.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                subtitle,
                style: TextStyle(color: _olympusBlue.withOpacity(0.68)),
              ),
            ],
            const SizedBox(height: 15),
            child,
          ],
        ),
      ),
    );
  }

  String _userSubtitle(Map<String, dynamic> user) {
    final pieces = <String>[];
    final userType = (user['user_type'] ?? '').toString().trim();
    final courtPosition = (user['court_position'] ?? '').toString().trim();
    final gender = (user['gender'] ?? '').toString().trim();

    if (userType.isNotEmpty) pieces.add(_profileLabelFromValue(userType));
    if (courtPosition.isNotEmpty) pieces.add(courtPosition);
    if (gender.isNotEmpty) pieces.add(gender);

    return pieces.join(' • ');
  }

  Widget _buildChoiceButtons({
    required List<String> options,
    required String? selectedValue,
    required ValueChanged<String> onSelected,
    String Function(String value)? labelBuilder,
  }) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: options.map((option) {
        final isSelected = option == selectedValue;
        final label = labelBuilder?.call(option) ?? option;

        return ChoiceChip(
          label: Text(label),
          selected: isSelected,
          onSelected: (_) => onSelected(option),
          selectedColor: _olympusBlue,
          backgroundColor: Colors.white,
          side: BorderSide(
            color: isSelected ? _olympusGold : _olympusBlue.withOpacity(0.18),
          ),
          checkmarkColor: _olympusGold,
          labelStyle: TextStyle(
            color: isSelected ? Colors.white : _olympusBlue,
            fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
          ),
        );
      }).toList(),
    );
  }

  Widget _buildModeButtons() {
    return _buildChoiceButtons(
      options: _sendModes,
      selectedValue: _sendMode,
      onSelected: (value) {
        setState(() {
          _sendMode = value;
          _selectedUsers.clear();

          if (_sendMode != 'Por perfil') {
            _selectedProfile = null;
            _selectedCourtPosition = null;
          }

          if (_sendMode != '1 usuário' && _sendMode != 'Vários usuários') {
            _selectedGender = null;
          }
        });
        _applyFilter();
      },
    );
  }

  Widget _buildProfileButtons() {
    return _buildChoiceButtons(
      options: _profiles,
      selectedValue: _selectedProfile,
      labelBuilder: _profileLabelFromValue,
      onSelected: (value) {
        setState(() {
          _selectedProfile = value;
          if (_normalizeProfileValue(value) != 'athlete') {
            _selectedCourtPosition = null;
          }
        });
        _applyFilter();
      },
    );
  }

  Widget _buildGenderButtons() {
    final options = ['Todos', ..._genders];

    return _buildChoiceButtons(
      options: options,
      selectedValue: _selectedGender ?? 'Todos',
      onSelected: (value) {
        setState(() {
          _selectedGender = value == 'Todos' ? null : value;
        });
        _applyFilter();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final branding = OlympusBrandingController.instance.branding;
    final primary = branding.primaryColor;
    final onPrimary = Theme.of(context).colorScheme.onPrimary;
    final showProfile = _sendMode == 'Por perfil';
    final showGenderFilter =
        _sendMode == '1 usuário' || _sendMode == 'Vários usuários';
    final canSelectUsers =
        _sendMode == '1 usuário' || _sendMode == 'Vários usuários';
    final showCourtPositionFilter = (_sendMode == 'Por perfil' &&
            _normalizeProfileValue(_selectedProfile ?? '') == 'athlete') ||
        (_sendMode == 'Vários usuários');

    return Scaffold(
      backgroundColor: primary,
      appBar: AppBar(
        backgroundColor: primary,
        foregroundColor: onPrimary,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Criar mensagem',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
            Text(
              'Comunicação ${branding.teamName}',
              style: TextStyle(
                color: onPrimary.withOpacity(0.78),
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: OlympusBrandBackgroundImage(
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => ColoredBox(color: primary),
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color.lerp(primary, Colors.black, 0.68)!.withOpacity(0.84),
                    primary.withOpacity(0.92),
                  ],
                ),
              ),
            ),
          ),
          _loading
              ? Center(
                  child: CircularProgressIndicator(color: _olympusGold),
                )
              : ListView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 110),
                  children: [
                    _buildComposerHero(),
                    const SizedBox(height: 12),
                    _buildSectionCard(
                      title: 'Destinatários',
                      subtitle: 'Escolha como a mensagem será enviada.',
                      icon: Icons.groups_2_rounded,
                      step: 1,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Modo de envio',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 8),
                          _buildModeButtons(),
                          if (showProfile) ...[
                            const SizedBox(height: 16),
                            const Text(
                              'Perfil',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 8),
                            _buildProfileButtons(),
                          ],
                          if (showCourtPositionFilter) ...[
                            const SizedBox(height: 16),
                            DropdownButtonFormField<String>(
                              value: _singleOrNullValue(
                                _selectedCourtPosition,
                                ['Todas', ..._courtPositions],
                              ),
                              decoration: const InputDecoration(
                                labelText: 'Filtrar por posição',
                                border: OutlineInputBorder(),
                              ),
                              items: [
                                const DropdownMenuItem<String>(
                                  value: 'Todas',
                                  child: Text('Todas'),
                                ),
                                ..._courtPositions.map(
                                  (position) => DropdownMenuItem<String>(
                                    value: position,
                                    child: Text(position),
                                  ),
                                ),
                              ],
                              onChanged: (value) {
                                setState(() {
                                  _selectedCourtPosition =
                                      value == 'Todas' ? null : value;
                                });
                                _applyFilter();
                              },
                            ),
                          ],
                          if (showGenderFilter) ...[
                            const SizedBox(height: 16),
                            const Text(
                              'Filtrar por gênero',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 8),
                            _buildGenderButtons(),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (canSelectUsers) ...[
                      _buildSectionCard(
                        title: 'Seleção de usuários',
                        icon: Icons.person_search_rounded,
                        step: 2,
                        subtitle: canSelectUsers
                            ? 'Abra o seletor para escolher usuários sem poluir a tela.'
                            : 'A seleção manual só aparece nos modos 1 usuário e vários usuários.',
                        child: canSelectUsers
                            ? Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          _selectedUsers.isEmpty
                                              ? 'Nenhum usuário selecionado'
                                              : '${_selectedUsers.length} usuário(s) selecionado(s)',
                                        ),
                                      ),
                                      if (_selectedUsers.isNotEmpty)
                                        TextButton(
                                          onPressed: _clearSelection,
                                          child: const Text('Limpar'),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      if (_selectedUsers.isEmpty)
                                        const Chip(
                                          label: Text('Nenhum selecionado'),
                                        )
                                      else
                                        ..._selectedUsers.take(3).map(
                                              (user) => InputChip(
                                                label: Text(
                                                  (user['full_name'] ?? '')
                                                      .toString(),
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                                onDeleted: () {
                                                  setState(() {
                                                    _selectedUsers.removeWhere(
                                                      (item) =>
                                                          (item['id'] ?? '')
                                                              .toString() ==
                                                          (user['id'] ?? '')
                                                              .toString(),
                                                    );
                                                  });
                                                },
                                              ),
                                            ),
                                      if (_selectedUsers.length > 3)
                                        Chip(
                                          label: Text(
                                            '+${_selectedUsers.length - 3} selecionado(s)',
                                          ),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  OutlinedButton.icon(
                                    onPressed: _openUserSelectionSheet,
                                    icon: const Icon(Icons.people_alt_outlined),
                                    label: Text(
                                      _sendMode == '1 usuário'
                                          ? 'Escolher usuário'
                                          : 'Escolher usuários',
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Disponíveis com os filtros atuais: ${_filteredUsers.length} • selecionados entre os filtrados: $_selectedFilteredCount',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodySmall,
                                  ),
                                ],
                              )
                            : const Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  'Nenhuma seleção manual é necessária neste modo.',
                                ),
                              ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    _buildSectionCard(
                      title: 'Usar mensagem padrão',
                      icon: Icons.auto_awesome_rounded,
                      step: canSelectUsers ? 3 : 2,
                      subtitle:
                          'Selecione um modelo salvo para preencher assunto e mensagem.',
                      child: Column(
                        children: [
                          DropdownButtonFormField<String>(
                            value: _singleOrNullTemplateKey(
                              _selectedTemplateKey,
                            ),
                            decoration: const InputDecoration(
                              labelText: 'Mensagem padrão',
                              border: OutlineInputBorder(),
                            ),
                            items: [
                              const DropdownMenuItem<String>(
                                value: '',
                                child: Text('Selecionar'),
                              ),
                              ..._templates.map(
                                (template) => DropdownMenuItem<String>(
                                  value: _templateKey(template),
                                  child: Text(template['title'] ?? ''),
                                ),
                              ),
                            ],
                            onChanged: (value) {
                              if (value == null || value.isEmpty) {
                                setState(() => _selectedTemplateKey = null);
                                return;
                              }

                              final template = _templates
                                  .cast<Map<String, String>?>()
                                  .firstWhere(
                                    (item) =>
                                        item != null &&
                                        _templateKey(item) == value,
                                    orElse: () => null,
                                  );

                              if (template != null) {
                                _applyTemplate(template);
                              }
                            },
                          ),
                          const SizedBox(height: 12),
                          Align(
                            alignment: Alignment.centerRight,
                            child: OutlinedButton.icon(
                              onPressed: _openCreateTemplateDialog,
                              icon: const Icon(Icons.add_box_outlined),
                              label: const Text('Criar modelo'),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildSectionCard(
                      title: 'Conteúdo',
                      icon: Icons.edit_note_rounded,
                      step: canSelectUsers ? 4 : 3,
                      child: Column(
                        children: [
                          DropdownButtonFormField<String>(
                            value: _deliveryChannel,
                            decoration: const InputDecoration(
                              labelText: 'Canal de saída',
                              border: OutlineInputBorder(),
                            ),
                            items: _deliveryChannelLabels.entries
                                .map(
                                  (entry) => DropdownMenuItem<String>(
                                    value: entry.key,
                                    child: Text(entry.value),
                                  ),
                                )
                                .toList(),
                            onChanged: (value) {
                              if (value == null) return;
                              setState(() => _deliveryChannel = value);
                            },
                          ),
                          const SizedBox(height: 8),
                          SwitchListTile(
                            title: const Text(
                              'Enviar como notificação urgente',
                            ),
                            activeThumbColor: _olympusGold,
                            activeTrackColor: _olympusBlue,
                            value: _isUrgent,
                            contentPadding: EdgeInsets.zero,
                            onChanged: (value) {
                              setState(() => _isUrgent = value);
                            },
                          ),
                          SwitchListTile(
                            title: const Text('Programar envio'),
                            activeThumbColor: _olympusGold,
                            activeTrackColor: _olympusBlue,
                            subtitle: Text(
                              'Usa o horário local do telefone ($_deviceTimezone).',
                            ),
                            value: _scheduleSend,
                            contentPadding: EdgeInsets.zero,
                            onChanged: (value) {
                              setState(() {
                                _scheduleSend = value;
                                if (!_scheduleSend) {
                                  _scheduledDate = null;
                                  _scheduledTime = null;
                                }
                              });
                            },
                          ),
                          if (_scheduleSend) ...[
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: _pickScheduledDate,
                                    icon: const Icon(
                                      Icons.calendar_today_outlined,
                                    ),
                                    label: Text(_formattedScheduledDate()),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: _pickScheduledTime,
                                    icon: const Icon(
                                      Icons.access_time_outlined,
                                    ),
                                    label: Text(_formattedScheduledTime()),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                          ],
                          TextField(
                            controller: _subjectController,
                            textCapitalization: TextCapitalization.sentences,
                            decoration: const InputDecoration(
                              labelText: 'Assunto',
                              hintText: 'Digite um título claro e objetivo',
                              prefixIcon: Icon(Icons.title_rounded),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _messageController,
                            minLines: 5,
                            maxLines: 7,
                            textCapitalization: TextCapitalization.sentences,
                            decoration: InputDecoration(
                              labelText: 'Mensagem',
                              hintText: 'Escreva a mensagem que será enviada',
                              alignLabelWithHint: true,
                              helperText:
                                  '${_messageController.text.length} caracteres',
                            ),
                          ),
                          const SizedBox(height: 8),
                          SwitchListTile(
                            title: const Text('Permitir resposta'),
                            activeThumbColor: _olympusGold,
                            activeTrackColor: _olympusBlue,
                            subtitle: const Text(
                              'O destinatário poderá responder por uma conversa privada.',
                            ),
                            value: _allowReply,
                            contentPadding: EdgeInsets.zero,
                            onChanged: (value) {
                              setState(() => _allowReply = value);
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          decoration: BoxDecoration(
            color: _olympusBlue,
            border: Border(
              top: BorderSide(color: _olympusGold.withOpacity(0.45)),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.26),
                blurRadius: 16,
                offset: const Offset(0, -5),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: _olympusGold.withOpacity(0.16),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  _composerReady
                      ? Icons.mark_email_read_rounded
                      : Icons.edit_notifications_rounded,
                  color: _olympusGold,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _composerReady ? 'Mensagem pronta' : 'Complete as etapas',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      _recipientCount == 0
                          ? 'Selecione os destinatários'
                          : '$_recipientCount destinatário(s)',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFFCADBEA),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                height: 48,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: _olympusGold,
                    foregroundColor: _olympusBlue,
                    disabledBackgroundColor: Colors.white.withOpacity(0.16),
                    disabledForegroundColor: Colors.white54,
                    padding: const EdgeInsets.symmetric(horizontal: 17),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  onPressed: _sending || !_composerReady
                      ? null
                      : (_scheduleSend ? _scheduleMessage : _sendMessage),
                  icon: _sending
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          _scheduleSend
                              ? Icons.schedule_send_rounded
                              : Icons.send_rounded,
                        ),
                  label: Text(
                    _sending
                        ? (_scheduleSend ? 'Programando...' : 'Enviando...')
                        : (_scheduleSend ? 'Programar' : 'Enviar'),
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class AdminMessageThreadPage extends StatefulWidget {
  final String threadId;
  final String subject;
  final bool allowReply;

  const AdminMessageThreadPage({
    super.key,
    required this.threadId,
    required this.subject,
    required this.allowReply,
  });

  @override
  State<AdminMessageThreadPage> createState() => _AdminMessageThreadPageState();
}

class _AdminMessageThreadPageState extends State<AdminMessageThreadPage> {
  final SupabaseClient supabase = Supabase.instance.client;
  final AppMessageService _messageService = AppMessageService();
  final TextEditingController _replyController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  bool _loading = true;
  bool _sending = false;
  bool _loadingParticipants = false;
  bool _participantsExpanded = true;
  List<Map<String, dynamic>> _messages = [];
  List<Map<String, dynamic>> _participants = [];
  RealtimeChannel? _threadChannel;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await Future.wait([_loadMessages(), _loadParticipantsStatus()]);
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

  void _setupRealtime() {
    _threadChannel = supabase.channel('admin-thread-${widget.threadId}')
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
          await Future.wait([_loadMessages(), _loadParticipantsStatus()]);
        },
      )
      ..subscribe();
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
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadParticipantsStatus() async {
    final adminId = supabase.auth.currentUser?.id;
    if (adminId == null) return;

    if (mounted) setState(() => _loadingParticipants = true);

    try {
      final participantsResponse = await supabase
          .from('app_message_participants')
          .select('user_id, unread_count, is_read, viewed_at, is_admin_sender')
          .eq('thread_id', widget.threadId);

      final participantRows =
          List<Map<String, dynamic>>.from(participantsResponse).where((row) {
        final userId = (row['user_id'] ?? '').toString();
        return userId.isNotEmpty && userId != adminId;
      }).toList();

      final userIds = participantRows
          .map((row) => (row['user_id'] ?? '').toString())
          .where((id) => id.isNotEmpty)
          .toList();

      Map<String, Map<String, dynamic>> profileMap = {};

      if (userIds.isNotEmpty) {
        final profilesResponse = await supabase
            .from('profiles')
            .select('id, full_name, user_type')
            .inFilter('id', userIds);

        for (final item in List<Map<String, dynamic>>.from(profilesResponse)) {
          final id = (item['id'] ?? '').toString();
          if (id.isNotEmpty) {
            profileMap[id] = item;
          }
        }
      }

      final merged = participantRows.map((row) {
        final userId = (row['user_id'] ?? '').toString();
        final profile = profileMap[userId] ?? const <String, dynamic>{};

        return {
          'user_id': userId,
          'full_name': (profile['full_name'] ?? 'Usuário').toString(),
          'user_type': (profile['user_type'] ?? '').toString(),
          'unread_count': row['unread_count'] ?? 0,
          'is_read': row['is_read'] == true,
          'viewed_at': row['viewed_at'],
        };
      }).toList()
        ..sort(
          (a, b) => (a['full_name'] ?? '').toString().toLowerCase().compareTo(
                (b['full_name'] ?? '').toString().toLowerCase(),
              ),
        );

      if (!mounted) return;
      setState(() {
        _participants = merged;
      });
    } catch (e) {
      _showSnack('Erro ao carregar status de visualização: $e');
    } finally {
      if (mounted) setState(() => _loadingParticipants = false);
    }
  }

  List<Map<String, dynamic>> get _readParticipants =>
      _participants.where((item) => item['is_read'] == true).toList();

  List<Map<String, dynamic>> get _pendingParticipants =>
      _participants.where((item) => item['is_read'] != true).toList();

  Future<Map<String, dynamic>?> _loadSenderProfile(String userId) async {
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

    return null;
  }

  Future<void> _sendReply() async {
    final admin = supabase.auth.currentUser;
    if (admin == null) {
      _showSnack('Usuário admin não autenticado.');
      return;
    }

    final body = _replyController.text.trim();
    if (body.isEmpty) {
      _showSnack('Digite uma mensagem.');
      return;
    }

    setState(() => _sending = true);

    try {
      final profile = await _loadSenderProfile(admin.id);
      final senderName = (profile?['full_name'] ?? 'Admin').toString();
      final senderType = (profile?['user_type'] ?? 'admin').toString();
      final now = DateTime.now().toUtc().toIso8601String();

      await supabase.from('app_messages').insert({
        'thread_id': widget.threadId,
        'sender_id': admin.id,
        'sender_name': senderName,
        'sender_type': senderType,
        'body': body,
        'created_at': now,
      });

      await supabase
          .from('app_message_threads')
          .update({'last_message_at': now, 'preview': _buildPreview(body)}).eq(
              'id', widget.threadId);

      final participants = await supabase
          .from('app_message_participants')
          .select('user_id, unread_count')
          .eq('thread_id', widget.threadId);

      final participantRows = List<Map<String, dynamic>>.from(participants);

      for (final row in participantRows) {
        final participantId = (row['user_id'] ?? '').toString();
        if (participantId.isEmpty || participantId == admin.id) continue;

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

      final recipientUserIds = participantRows
          .map((row) => (row['user_id'] ?? '').toString())
          .where((id) => id.isNotEmpty && id != admin.id)
          .toSet()
          .toList();

      if (recipientUserIds.isNotEmpty) {
        await supabase.functions.invoke(
          'send-push-notification',
          body: {
            'recipientUserIds': recipientUserIds,
            'title': widget.subject,
            'body': 'Nova mensagem',
            'type': 'platform_message',
            'threadId': widget.threadId,
          },
        );
      }

      _replyController.clear();
      await Future.wait([_loadMessages(), _loadParticipantsStatus()]);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      _showSnack('Erro ao enviar resposta: $e');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  String _buildPreview(String body) {
    final normalized = body.replaceAll('\n', ' ').trim();
    if (normalized.length <= 120) return normalized;
    return '${normalized.substring(0, 120)}...';
  }

  bool _isCurrentUser(Map<String, dynamic> message) {
    final admin = supabase.auth.currentUser;
    if (admin == null) return false;
    return (message['sender_id'] ?? '').toString() == admin.id;
  }

  Future<void> _deleteMessage(Map<String, dynamic> message) async {
    final messageId = (message['id'] ?? '').toString();
    if (messageId.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Excluir mensagem'),
        content: const Text(
          'Deseja excluir esta mensagem para todos os participantes?',
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
      await _messageService.deleteMessageForEveryone(
        threadId: widget.threadId,
        messageId: messageId,
        allowAnySender: true,
      );
      await _loadMessages();
      _showSnack('Mensagem excluída para todos.');
    } catch (e) {
      _showSnack('Erro ao excluir mensagem: $e');
    }
  }

  String _formatDateTime(dynamic value) {
    final date = value is DateTime
        ? value.toLocal()
        : DateTime.tryParse((value ?? '').toString())?.toLocal();
    if (date == null) return '';
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');
    return '$day/$month $hour:$minute';
  }

  void _showSnack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Widget _buildStatusChip({
    required String label,
    required int count,
    required Color color,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 17, color: color),
          const SizedBox(width: 6),
          Text(
            '$label ($count)',
            style: TextStyle(fontWeight: FontWeight.w600, color: color),
          ),
        ],
      ),
    );
  }

  Widget _buildParticipantRow(Map<String, dynamic> item, {required bool read}) {
    final name = (item['full_name'] ?? 'Usuário').toString();
    final viewedAt = item['viewed_at'];
    final formattedViewedAt = read ? _formatDateTime(viewedAt) : '';

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            read ? Icons.visibility_outlined : Icons.schedule_outlined,
            size: 18,
            color: read ? Colors.green.shade700 : Colors.orange.shade700,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              read && formattedViewedAt.isNotEmpty
                  ? '$name • $formattedViewedAt'
                  : name,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildParticipantsCard() {
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () {
                setState(() {
                  _participantsExpanded = !_participantsExpanded;
                });
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    const Icon(Icons.remove_red_eye_outlined),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Status de visualização',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                    if (_loadingParticipants)
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    else ...[
                      _buildStatusChip(
                        label: 'Visualizaram',
                        count: _readParticipants.length,
                        color: Colors.green.shade700,
                        icon: Icons.check_circle_outline,
                      ),
                      const SizedBox(width: 8),
                      _buildStatusChip(
                        label: 'Pendentes',
                        count: _pendingParticipants.length,
                        color: Colors.orange.shade700,
                        icon: Icons.hourglass_bottom_outlined,
                      ),
                    ],
                    const SizedBox(width: 8),
                    Icon(
                      _participantsExpanded
                          ? Icons.expand_less
                          : Icons.expand_more,
                    ),
                  ],
                ),
              ),
            ),
            if (_participantsExpanded) ...[
              const SizedBox(height: 12),
              if (_loadingParticipants)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_participants.isEmpty)
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Nenhum destinatário encontrado nesta conversa.'),
                )
              else
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Visualizaram (${_readParticipants.length})',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    if (_readParticipants.isEmpty)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 12),
                        child: Text('Ninguém visualizou ainda.'),
                      )
                    else
                      ..._readParticipants.map(
                        (item) => _buildParticipantRow(item, read: true),
                      ),
                    const SizedBox(height: 8),
                    Text(
                      'Pendentes (${_pendingParticipants.length})',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    if (_pendingParticipants.isEmpty)
                      const Text('Todos visualizaram.')
                    else
                      ..._pendingParticipants.map(
                        (item) => _buildParticipantRow(item, read: false),
                      ),
                  ],
                ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.subject)),
      body: Column(
        children: [
          _buildParticipantsCard(),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _messages.isEmpty
                    ? const Center(
                        child: Text('Nenhuma mensagem nesta conversa.'))
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
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              senderName.isEmpty
                                                  ? (isMine
                                                      ? 'Você'
                                                      : 'Usuário')
                                                  : (isMine
                                                      ? 'Você'
                                                      : senderName),
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ),
                                          PopupMenuButton<String>(
                                            tooltip: 'Opções da mensagem',
                                            padding: EdgeInsets.zero,
                                            icon: const Icon(
                                              Icons.more_vert,
                                              size: 20,
                                            ),
                                            onSelected: (value) {
                                              if (value == 'delete') {
                                                _deleteMessage(message);
                                              }
                                            },
                                            itemBuilder: (_) => const [
                                              PopupMenuItem<String>(
                                                value: 'delete',
                                                child: Row(
                                                  children: [
                                                    Icon(Icons.delete_outline),
                                                    SizedBox(width: 10),
                                                    Text('Excluir mensagem'),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      Text(body),
                                      if (createdAt.isNotEmpty) ...[
                                        const SizedBox(height: 8),
                                        Text(
                                          createdAt,
                                          style: Theme.of(
                                            context,
                                          ).textTheme.bodySmall,
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
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
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
