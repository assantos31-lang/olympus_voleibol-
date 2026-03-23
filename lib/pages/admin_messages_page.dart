import 'dart:ui';
import 'package:flutter/material.dart';
import '../models/app_message.dart';
import '../services/messaging_service.dart';
import 'message_thread_page.dart';

class AdminMessagesPage extends StatefulWidget {
  const AdminMessagesPage({super.key});

  @override
  State<AdminMessagesPage> createState() => _AdminMessagesPageState();
}

class _AdminMessagesPageState extends State<AdminMessagesPage> {
  final MessagingService _service = MessagingService();
  final TextEditingController _subjectController = TextEditingController();
  final TextEditingController _bodyController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();

  static const Color olympusBlue = Color(0xFF1E3A5F);
  static const Color olympusGold = Color(0xFFD4AF37);
  static const Color olympusDark = Color(0xFF0B1420);

  bool _isLoading = true;
  bool _isSending = false;
  bool _allowReply = true;

  String _targetMode = 'all';
  String _targetUserType = 'athlete';

  List<AppMessageThread> _threads = [];
  List<MessageRecipientOption> _recipients = [];
  final Set<String> _selectedUserIds = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _subjectController.dispose();
    _bodyController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final threads = await _service.getAdminCreatedThreads();
      final recipients = await _service.searchRecipients(
        query: _searchController.text,
        userType: _targetMode == 'by_role' ? _targetUserType : 'all',
      );

      if (!mounted) return;
      setState(() {
        _threads = threads;
        _recipients = recipients;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao carregar mensagens: $e')),
      );
    }
  }

  Future<void> _send() async {
    if (_subjectController.text.trim().isEmpty ||
        _bodyController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Preencha assunto e mensagem.')),
      );
      return;
    }

    if ((_targetMode == 'single' || _targetMode == 'multiple') &&
        _selectedUserIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecione ao menos um destinatário.')),
      );
      return;
    }

    setState(() => _isSending = true);

    try {
      await _service.createThreadAndSend(
        subject: _subjectController.text,
        body: _bodyController.text,
        allowReply: _allowReply,
        targetMode: _targetMode,
        targetUserType: _targetUserType,
        selectedUserIds: _selectedUserIds.toList(),
      );

      _subjectController.clear();
      _bodyController.clear();
      _selectedUserIds.clear();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Mensagem enviada com sucesso.')),
      );

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

  InputDecoration _input(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(color: Colors.white.withOpacity(0.70)),
      filled: true,
      fillColor: Colors.white.withOpacity(0.08),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: Colors.white.withOpacity(0.10)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: olympusGold.withOpacity(0.70)),
      ),
    );
  }

  Widget _panel({required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF122235), Color(0xFF18324D)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: olympusGold.withOpacity(0.22)),
      ),
      child: child,
    );
  }

  Widget _buildModeSection() {
    return Column(
      children: [
        DropdownButtonFormField<String>(
          value: _targetMode,
          dropdownColor: const Color(0xFF122235),
          style: const TextStyle(color: Colors.white),
          decoration: _input('Enviar para'),
          items: const [
            DropdownMenuItem(value: 'all', child: Text('Todos')),
            DropdownMenuItem(value: 'by_role', child: Text('Por perfil')),
            DropdownMenuItem(value: 'single', child: Text('1 usuário')),
            DropdownMenuItem(value: 'multiple', child: Text('Vários usuários')),
          ],
          onChanged: (value) async {
            setState(() {
              _targetMode = value ?? 'all';
              _selectedUserIds.clear();
            });
            await _load();
          },
        ),
        if (_targetMode == 'by_role') ...[
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _targetUserType,
            dropdownColor: const Color(0xFF122235),
            style: const TextStyle(color: Colors.white),
            decoration: _input('Perfil'),
            items: const [
              DropdownMenuItem(value: 'athlete', child: Text('Atletas')),
              DropdownMenuItem(value: 'coach', child: Text('Técnicos')),
              DropdownMenuItem(value: 'member', child: Text('Membros')),
            ],
            onChanged: (value) async {
              setState(() => _targetUserType = value ?? 'athlete');
              await _load();
            },
          ),
        ],
        if (_targetMode == 'single' || _targetMode == 'multiple') ...[
          const SizedBox(height: 12),
          TextField(
            controller: _searchController,
            onChanged: (_) => _load(),
            style: const TextStyle(color: Colors.white),
            decoration: _input('Buscar usuário').copyWith(
              suffixIcon: const Icon(Icons.search, color: Colors.white70),
            ),
          ),
          const SizedBox(height: 10),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 220),
            child: _recipients.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        'Nenhum destinatário encontrado.',
                        style: TextStyle(color: Colors.white.withOpacity(0.65)),
                      ),
                    ),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: _recipients.length,
                    itemBuilder: (context, index) {
                      final item = _recipients[index];
                      final selected = _selectedUserIds.contains(item.id);

                      return CheckboxListTile(
                        dense: true,
                        value: selected,
                        activeColor: olympusGold,
                        checkColor: olympusBlue,
                        onChanged: (_) {
                          setState(() {
                            if (_targetMode == 'single') {
                              _selectedUserIds
                                ..clear()
                                ..add(item.id);
                            } else {
                              if (selected) {
                                _selectedUserIds.remove(item.id);
                              } else {
                                _selectedUserIds.add(item.id);
                              }
                            }
                          });
                        },
                        title: Text(
                          item.fullName.isEmpty ? 'Sem nome' : item.fullName,
                          style: const TextStyle(color: Colors.white),
                        ),
                        subtitle: Text(
                          item.email,
                          style:
                              TextStyle(color: Colors.white.withOpacity(0.62)),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ],
    );
  }

  Widget _buildComposer() {
    return _panel(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Nova mensagem',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 12),
            _buildModeSection(),
            const SizedBox(height: 12),
            TextField(
              controller: _subjectController,
              style: const TextStyle(color: Colors.white),
              decoration: _input('Assunto'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _bodyController,
              style: const TextStyle(color: Colors.white),
              maxLines: 5,
              decoration: _input('Mensagem'),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              value: _allowReply,
              activeColor: olympusGold,
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'Permitir resposta do usuário',
                style: TextStyle(color: Colors.white),
              ),
              onChanged: (value) => setState(() => _allowReply = value),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isSending ? null : _send,
                style: ElevatedButton.styleFrom(
                  backgroundColor: olympusGold,
                  foregroundColor: olympusBlue,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                icon: _isSending
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send_rounded),
                label: const Text('Enviar mensagem'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildThreadTile(AppMessageThread thread) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
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
            trailing: const Icon(Icons.chevron_right, color: Colors.white70),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: olympusDark,
      appBar: AppBar(
        title: const Text('Mensagens Admin'),
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
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _buildComposer(),
                      const SizedBox(height: 16),
                      const Text(
                        'Conversas enviadas',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 10),
                      if (_threads.isEmpty)
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.06),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Text(
                            'Nenhuma conversa enviada ainda.',
                            style: TextStyle(
                                color: Colors.white.withOpacity(0.70)),
                          ),
                        )
                      else
                        ..._threads.map(_buildThreadTile),
                    ],
                  ),
                ),
        ],
      ),
    );
  }
}
