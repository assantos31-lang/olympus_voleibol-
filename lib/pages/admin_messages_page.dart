import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AdminMessagesPage extends StatefulWidget {
  const AdminMessagesPage({super.key});

  @override
  State<AdminMessagesPage> createState() => _AdminMessagesPageState();
}

class _AdminMessagesPageState extends State<AdminMessagesPage> {
  final SupabaseClient supabase = Supabase.instance.client;

  bool _loading = true;
  bool _loadingHistory = false;
  List<Map<String, dynamic>> _sentThreads = [];

  @override
  void initState() {
    super.initState();
    _loadSentThreads();
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
        _loading = _sentThreads.isEmpty;
      });
    }

    try {
      final response = await supabase
          .from('app_message_threads')
          .select(
            'id, subject, preview, created_at, last_message_at, target_mode, '
            'target_user_type, created_by, allow_reply, app_message_participants(user_id)',
          )
          .eq('created_by', admin.id)
          .order('last_message_at', ascending: false)
          .order('created_at', ascending: false);

      if (!mounted) return;
      setState(() {
        _sentThreads = List<Map<String, dynamic>>.from(response);
      });
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

  Future<void> _openThread(Map<String, dynamic> thread) async {
    final threadId = (thread['id'] ?? '').toString();
    if (threadId.isEmpty) return;

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
      await _loadSentThreads();
    }
  }

  Future<void> _openCreatePage() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => const AdminCreateMessagePage(),
      ),
    );

    if (created == true) {
      await _loadSentThreads();
    }
  }

  int _recipientCountForThread(Map<String, dynamic> thread) {
    final participants = List<Map<String, dynamic>>.from(
        (thread['app_message_participants'] as List?) ?? const []);
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
    final createdAt =
        DateTime.tryParse((thread['created_at'] ?? '').toString())?.toLocal();

    final parts = <String>[
      if (recipients > 0) '$recipients destinatário(s)',
      if (profileLabel.isNotEmpty) profileLabel,
      if (createdAt != null)
        '${createdAt.day.toString().padLeft(2, '0')}/${createdAt.month.toString().padLeft(2, '0')}/${createdAt.year} '
            '${createdAt.hour.toString().padLeft(2, '0')}:${createdAt.minute.toString().padLeft(2, '0')}',
    ];

    return parts.join(' • ');
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

  void _showSnack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text)),
    );
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
                    'Abra uma conversa salva ou toque em criar mensagem.',
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
                    'Envie avisos, lembretes e comunicados de forma organizada.',
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
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _openThread(thread),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
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
                          fontSize: 15, fontWeight: FontWeight.w700),
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

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return RefreshIndicator(
      onRefresh: _loadSentThreads,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _buildHeaderCard(),
          const SizedBox(height: 12),
          _buildActionCard(),
          const SizedBox(height: 16),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Conversas salvas',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
              IconButton(
                tooltip: 'Atualizar histórico',
                onPressed: _loadingHistory ? null : _loadSentThreads,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_loadingHistory && _sentThreads.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_sentThreads.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    const Icon(Icons.mark_chat_read_outlined, size: 48),
                    const SizedBox(height: 12),
                    const Text(
                      'Nenhuma mensagem salva até o momento.',
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
          else
            ..._sentThreads.map(_buildThreadCard),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mensagens'),
      ),
      body: _buildBody(),
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

  final TextEditingController _subjectController = TextEditingController();
  final TextEditingController _messageController = TextEditingController();
  final TextEditingController _templateTitleController =
      TextEditingController();
  final TextEditingController _templateBodyController = TextEditingController();

  bool _loading = true;
  bool _sending = false;
  bool _allowReply = true;
  bool _isUrgent = false;

  String _sendMode = 'Por perfil';
  String? _selectedProfile;
  String? _selectedGender;
  String? _selectedTemplateKey;
  String? _selectedCourtPosition;
  String _deliveryChannel = 'both';

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
    'coach': 'Técnico',
    'member': 'Membro',
    'athlete': 'Atleta',
  };

  static const Map<String, String> _deliveryChannelLabels = {
    'in_app': 'Apenas no mural',
    'push': 'Apenas push',
    'both': 'Push + mural',
  };

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _subjectController.dispose();
    _messageController.dispose();
    _templateTitleController.dispose();
    _templateBodyController.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    await Future.wait([
      _loadUsers(),
      _loadTemplates(),
    ]);
  }

  Future<void> _loadUsers() async {
    if (mounted) setState(() => _loading = true);

    try {
      final response = await supabase
          .from('profiles')
          .select('id, user_type, full_name, email, gender, court_position')
          .neq('user_type', 'admin')
          .order('full_name');

      _allUsers = List<Map<String, dynamic>>.from(response);
      _applyFilter();
    } catch (e) {
      _showSnack('Erro ao carregar usuários: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _normalizeProfileValue(String value) {
    return value.trim().toLowerCase();
  }

  String _profileLabelFromValue(String value) {
    return _fixedProfileLabels[_normalizeProfileValue(value)] ?? value.trim();
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
      ..sort((a, b) => _profileLabelFromValue(a)
          .toLowerCase()
          .compareTo(_profileLabelFromValue(b).toLowerCase()));
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
        .where((e) =>
            _normalizeProfileValue((e['user_type'] ?? '').toString()) ==
            'athlete')
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
          .map((template) => {
                'title': template['title'] ?? '',
                'body': template['body'] ?? '',
              })
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
            .where((u) =>
                (u['court_position'] ?? '').toString().trim() ==
                _selectedCourtPosition)
            .toList();
      }
    }

    if (_sendMode == 'Vários usuários' &&
        _selectedGender != null &&
        _selectedGender!.isNotEmpty) {
      users = users
          .where((u) => (u['gender'] ?? '').toString() == _selectedGender)
          .toList();
    }

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
        _selectedUsers
            .removeWhere((u) => u['id'].toString() == user['id'].toString());
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

  Future<List<String>> _loadDeviceTokens(List<String> userIds) async {
    if (userIds.isEmpty) return [];

    final response = await supabase
        .from('user_push_tokens')
        .select('device_token')
        .inFilter('user_id', userIds);

    final rows = List<Map<String, dynamic>>.from(response);

    return rows
        .map((e) => (e['device_token'] ?? '').toString().trim())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList();
  }

  Future<void> _sendPushNotification({
    required List<String> tokens,
    required String title,
    required String body,
    String? threadId,
    required bool isUrgent,
  }) async {
    for (final token in tokens) {
      try {
        await supabase.functions.invoke(
          'send-push-notification',
          body: {
            'token': token,
            'device_token': token,
            'title': isUrgent ? 'URGENTE: $title' : title,
            'body': body,
            'data': {
              'thread_id': threadId,
              'type': 'admin_message',
              'is_urgent': isUrgent,
            },
          },
        );
      } catch (_) {}
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
        return 'single';
      case 'Vários usuários':
        return 'multiple';
      default:
        return 'custom';
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

    List<Map<String, dynamic>> recipients = [];

    switch (_sendMode) {
      case 'Por perfil':
        if (_selectedProfile == null || _selectedProfile!.isEmpty) {
          _showSnack('Selecione um perfil.');
          return;
        }
        recipients = _allUsers
            .where((u) => _matchesProfile(u['user_type'], _selectedProfile))
            .where((u) =>
                _selectedCourtPosition == null ||
                _selectedCourtPosition!.isEmpty ||
                (u['court_position'] ?? '').toString().trim() ==
                    _selectedCourtPosition)
            .toList();
        break;
      case '1 usuário':
        if (_selectedUsers.length != 1) {
          _showSnack('Selecione exatamente 1 usuário.');
          return;
        }
        recipients = List<Map<String, dynamic>>.from(_selectedUsers);
        break;
      case 'Vários usuários':
        if (_selectedUsers.isEmpty) {
          _showSnack('Selecione ao menos 1 usuário.');
          return;
        }
        recipients = List<Map<String, dynamic>>.from(_selectedUsers);
        break;
    }

    if (recipients.isEmpty) {
      _showSnack('Nenhum destinatário encontrado.');
      return;
    }

    setState(() => _sending = true);

    try {
      final adminProfile = await supabase
          .from('profiles')
          .select('full_name, user_type')
          .eq('id', admin.id)
          .maybeSingle();

      final adminName = (adminProfile?['full_name'] ?? 'Admin').toString();
      final adminType = (adminProfile?['user_type'] ?? 'admin').toString();
      final now = DateTime.now().toIso8601String();

      final dedupRecipients = <String, Map<String, dynamic>>{};
      for (final user in recipients) {
        final id = (user['id'] ?? '').toString();
        if (id.isNotEmpty && id != admin.id) {
          dedupRecipients[id] = user;
        }
      }
      recipients = dedupRecipients.values.toList();

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
          'created_at': now,
        },
        ...recipients.map(
          (user) => {
            'thread_id': threadId,
            'user_id': user['id'],
            'is_admin_sender': false,
            'unread_count': 1,
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
            .toList();

        final tokens = await _loadDeviceTokens(recipientIds);

        if (tokens.isNotEmpty) {
          await _sendPushNotification(
            tokens: tokens,
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

  void _showSnack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text)),
    );
  }

  Widget _buildSectionCard({
    required String title,
    String? subtitle,
    required Widget child,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            if (subtitle != null && subtitle.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(subtitle),
            ],
            const SizedBox(height: 12),
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

  @override
  Widget build(BuildContext context) {
    final showProfile = _sendMode == 'Por perfil';
    final showGenderFilter = _sendMode == 'Vários usuários';
    final canSelectUsers =
        _sendMode == '1 usuário' || _sendMode == 'Vários usuários';
    final showCourtPositionFilter = (_sendMode == 'Por perfil' &&
            _normalizeProfileValue(_selectedProfile ?? '') == 'athlete') ||
        (_sendMode == 'Vários usuários');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Criar mensagem'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(12),
              children: [
                _buildSectionCard(
                  title: 'Destinatários',
                  subtitle: 'Escolha como a mensagem será enviada.',
                  child: Column(
                    children: [
                      DropdownButtonFormField<String>(
                        value: _sendMode,
                        decoration: const InputDecoration(
                          labelText: 'Modo de envio',
                          border: OutlineInputBorder(),
                        ),
                        items: _sendModes
                            .map((mode) => DropdownMenuItem(
                                value: mode, child: Text(mode)))
                            .toList(),
                        onChanged: (value) {
                          if (value == null) return;
                          setState(() {
                            _sendMode = value;
                            _selectedUsers.clear();
                            if (_sendMode != 'Por perfil') {
                              _selectedProfile = null;
                              _selectedCourtPosition = null;
                            }
                            if (_sendMode != 'Vários usuários') {
                              _selectedGender = null;
                            }
                          });
                          _applyFilter();
                        },
                      ),
                      if (showProfile) ...[
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          value:
                              _singleOrNullValue(_selectedProfile, _profiles),
                          decoration: const InputDecoration(
                            labelText: 'Perfil',
                            border: OutlineInputBorder(),
                          ),
                          items: _profiles
                              .map((profile) => DropdownMenuItem(
                                    value: profile,
                                    child:
                                        Text(_profileLabelFromValue(profile)),
                                  ))
                              .toList(),
                          onChanged: (value) {
                            setState(() {
                              _selectedProfile = value;
                              if (_normalizeProfileValue(value ?? '') !=
                                  'athlete') {
                                _selectedCourtPosition = null;
                              }
                            });
                            _applyFilter();
                          },
                        ),
                      ],
                      if (showCourtPositionFilter) ...[
                        const SizedBox(height: 12),
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
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          value: _singleOrNullValue(
                              _selectedGender, ['Todos', ..._genders]),
                          decoration: const InputDecoration(
                            labelText: 'Filtrar por gênero',
                            border: OutlineInputBorder(),
                          ),
                          items: [
                            const DropdownMenuItem<String>(
                              value: 'Todos',
                              child: Text('Todos'),
                            ),
                            ..._genders.map(
                              (gender) => DropdownMenuItem<String>(
                                value: gender,
                                child: Text(gender),
                              ),
                            ),
                          ],
                          onChanged: (value) {
                            setState(() {
                              _selectedGender = value == 'Todos' ? null : value;
                            });
                            _applyFilter();
                          },
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                _buildSectionCard(
                  title: 'Seleção de usuários',
                  subtitle: canSelectUsers
                      ? 'Selecione os destinatários logo após escolher o modo de envio.'
                      : 'A seleção manual só aparece nos modos 1 usuário e vários usuários.',
                  child: canSelectUsers
                      ? Column(
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                      'Selecionados: ${_selectedUsers.length}'),
                                ),
                                if (_sendMode == 'Vários usuários')
                                  TextButton(
                                    onPressed: _selectAllFiltered,
                                    child: const Text('Selecionar todos'),
                                  ),
                                TextButton(
                                  onPressed: _clearSelection,
                                  child: const Text('Limpar'),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            ..._filteredUsers.map((user) {
                              final selected = _selectedUsers.any(
                                (u) =>
                                    u['id'].toString() == user['id'].toString(),
                              );
                              final subtitle = _userSubtitle(user);

                              return CheckboxListTile(
                                value: selected,
                                onChanged: (_) => _toggleUser(user),
                                title:
                                    Text((user['full_name'] ?? '').toString()),
                                subtitle:
                                    subtitle.isEmpty ? null : Text(subtitle),
                                controlAffinity:
                                    ListTileControlAffinity.trailing,
                                contentPadding: EdgeInsets.zero,
                              );
                            }),
                          ],
                        )
                      : const Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                              'Nenhuma seleção manual é necessária neste modo.'),
                        ),
                ),
                _buildSectionCard(
                  title: 'Usar mensagem padrão',
                  subtitle:
                      'Selecione um modelo salvo para preencher assunto e mensagem.',
                  child: Column(
                    children: [
                      DropdownButtonFormField<String>(
                        value: _singleOrNullTemplateKey(_selectedTemplateKey),
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
                                    item != null && _templateKey(item) == value,
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
                  child: Column(
                    children: [
                      DropdownButtonFormField<String>(
                        value: _deliveryChannel,
                        decoration: const InputDecoration(
                          labelText: 'Canal de saída',
                          border: OutlineInputBorder(),
                        ),
                        items: _deliveryChannelLabels.entries
                            .map((entry) => DropdownMenuItem<String>(
                                  value: entry.key,
                                  child: Text(entry.value),
                                ))
                            .toList(),
                        onChanged: (value) {
                          if (value == null) return;
                          setState(() => _deliveryChannel = value);
                        },
                      ),
                      const SizedBox(height: 8),
                      SwitchListTile(
                        title: const Text('Enviar como notificação urgente'),
                        value: _isUrgent,
                        contentPadding: EdgeInsets.zero,
                        onChanged: (value) {
                          setState(() => _isUrgent = value);
                        },
                      ),
                      TextField(
                        controller: _subjectController,
                        decoration: const InputDecoration(
                          hintText: 'Assunto',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _messageController,
                        minLines: 5,
                        maxLines: 7,
                        decoration: const InputDecoration(
                          hintText: 'Mensagem',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SwitchListTile(
                        title: const Text('Permitir resposta'),
                        value: _allowReply,
                        contentPadding: EdgeInsets.zero,
                        onChanged: (value) {
                          setState(() => _allowReply = value);
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                const SizedBox(height: 24),
              ],
            ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: SizedBox(
            height: 52,
            child: FilledButton.icon(
              onPressed: _sending ? null : _sendMessage,
              icon: _sending
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send),
              label: Text(_sending ? 'Enviando...' : 'Enviar mensagem'),
            ),
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
  final TextEditingController _replyController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  bool _loading = true;
  bool _sending = false;
  List<Map<String, dynamic>> _messages = [];
  RealtimeChannel? _threadChannel;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
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
          await _loadMessages();
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
      final now = DateTime.now().toIso8601String();

      await supabase.from('app_messages').insert({
        'thread_id': widget.threadId,
        'sender_id': admin.id,
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
        if (participantId.isEmpty || participantId == admin.id) continue;

        final currentUnread = (row['unread_count'] ?? 0) as int;

        await supabase
            .from('app_message_participants')
            .update({'unread_count': currentUnread + 1})
            .eq('thread_id', widget.threadId)
            .eq('user_id', participantId);
      }

      _replyController.clear();
      await _loadMessages();
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

  String _formatDateTime(dynamic value) {
    final date = DateTime.tryParse((value ?? '').toString())?.toLocal();
    if (date == null) return '';
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');
    return '$day/$month $hour:$minute';
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
        title: Text(widget.subject),
      ),
      body: Column(
        children: [
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _messages.isEmpty
                    ? const Center(
                        child: Text('Nenhuma mensagem nesta conversa.'),
                      )
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
                                      Text(
                                        senderName.isEmpty
                                            ? (isMine ? 'Você' : 'Usuário')
                                            : (isMine ? 'Você' : senderName),
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w700),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(body),
                                      if (createdAt.isNotEmpty) ...[
                                        const SizedBox(height: 8),
                                        Text(
                                          createdAt,
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall,
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
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
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
