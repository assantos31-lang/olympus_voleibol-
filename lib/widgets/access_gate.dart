import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AccessGate extends StatefulWidget {
  final String permission; // 🔥 mudou aqui
  final Widget child;
  final String title;
  final String deniedMessage;

  const AccessGate({
    super.key,
    required this.permission,
    required this.child,
    this.title = 'Acesso restrito',
    this.deniedMessage = 'Você não tem permissão para acessar esta área.',
  });

  @override
  State<AccessGate> createState() => _AccessGateState();
}

class _AccessGateState extends State<AccessGate> {
  final supabase = Supabase.instance.client;

  bool _isLoading = true;
  bool _hasAccess = false;

  @override
  void initState() {
    super.initState();
    _checkAccess();
  }

  Future<void> _checkAccess() async {
    try {
      final user = supabase.auth.currentUser;

      if (user == null) {
        if (!mounted) return;
        Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
        return;
      }

      final permissions = await supabase
          .from('user_permissions')
          .select()
          .eq('user_id', user.id)
          .maybeSingle();

      if (!mounted) return;

      final hasPermission = permissions?[widget.permission] == true;

      setState(() {
        _hasAccess = hasPermission;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Erro ao validar acesso: $e');
      if (!mounted) return;
      setState(() {
        _hasAccess = false;
        _isLoading = false;
      });
    }
  }

  void _goBackHome() {
    Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (!_hasAccess) {
      return Scaffold(
        appBar: AppBar(
          title: Text(widget.title),
          backgroundColor: const Color(0xFF1E3A5F),
          foregroundColor: Colors.white,
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.lock_outline_rounded,
                    size: 56, color: Colors.redAccent),
                const SizedBox(height: 16),
                const Text(
                  'Acesso restrito',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(widget.deniedMessage, textAlign: TextAlign.center),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: _goBackHome,
                  child: const Text('Voltar'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return widget.child;
  }
}
