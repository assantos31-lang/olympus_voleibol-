import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_masked_text2/flutter_masked_text2.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:typed_data';
import '../services/auth_service.dart';
import 'athlete_agenda_page.dart';
import 'athlete_financial_page.dart';

class AthleteDashboardPage extends StatefulWidget {
  const AthleteDashboardPage({super.key});

  @override
  State<AthleteDashboardPage> createState() => _AthleteDashboardPageState();
}

class _AthleteDashboardPageState extends State<AthleteDashboardPage> {
  final supabase = Supabase.instance.client;
  final _authService = AuthService();
  Map<String, dynamic>? _profile;
  bool _isLoading = true;
  // ✅ Contador de convocações pendentes
  int _pendingCount = 0;
  // ✅ Contador de pagamentos em atraso
  int _overdueFinancialCount = 0;
  // ✅ Mapa de pagamentos em atraso por mês
  Map<int, int> _overdueByMonth = {};
  // ✅ Eventos da semana
  List<Map<String, dynamic>> _weekEvents = [];

  // ✅ Cores do logo Olympus Voleibol
  static const Color olympusBlue = Color(0xFF1E3A5F);
  static const Color olympusGold = Color(0xFFD4AF37);
  static const Color olympusLightBlue = Color(0xFF2C5F8D);
  static const String _eventsEmbedFk = 'convocations_event_id_fkey';

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final user = supabase.auth.currentUser;
    if (user != null) {
      final profile = await _authService.getUserProfile(user.id);
      if (mounted) {
        setState(() {
          _profile = profile;
          _isLoading = false;
        });
        // ✅ NOVO: Carregar contador de pendentes após carregar perfil
        _loadPendingCount();
        _loadOverdueFinancialCount();
        _loadWeekEvents();
      }
    }
  }

  // ✅ NOVO: Carregar quantidade de convocações pendentes
  Future<void> _loadPendingCount() async {
    try {
      final user = supabase.auth.currentUser;
      if (user != null) {
        final response = await supabase
            .from('convocations')
            .select('id')
            .eq('user_id', user.id)
            .eq('status', 'pending');
        if (mounted) {
          setState(() {
            _pendingCount = response.length;
          });
        }
      }
    } catch (e) {
      debugPrint('Erro ao carregar pendentes: $e');
    }
  }

  // ✅ NOVO: Carregar quantidade de pagamentos em atraso agrupados por mês
  Future<void> _loadOverdueFinancialCount() async {
    try {
      final user = supabase.auth.currentUser;
      if (user != null) {
        final response = await supabase
            .from('financial_records')
            .select('day, month, year, status')
            .eq('athlete_id', user.id)
            .eq('status', 'pending');

        Map<int, int> overdueByMonth = {};
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);

        for (var record in response) {
          final day = record['day'] ?? 10;
          final month = record['month'];
          final year = record['year'];
          final dueDate = DateTime(year, month, day);

          if (today.isAfter(dueDate)) {
            overdueByMonth[month] = (overdueByMonth[month] ?? 0) + 1;
          }
        }

        if (mounted) {
          setState(() {
            _overdueByMonth = overdueByMonth;
            _overdueFinancialCount =
                overdueByMonth.values.fold(0, (a, b) => a + b);
          });
        }
      }
    } catch (e) {
      debugPrint('Erro ao carregar atrasos financeiros: $e');
    }
  }

  Future<void> _loadWeekEvents() async {
    try {
      final user = supabase.auth.currentUser;
      if (user == null) return;

      final response = await supabase.from('convocations').select('''
        status,
        events!$_eventsEmbedFk (
          id,
          event_name,
          event_date,
          event_time,
          event_type
        )
      ''').eq('user_id', user.id).neq('status', 'rejected');

      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final endOfWeek = today.add(const Duration(days: 7));

      final List<Map<String, dynamic>> weekEvents = [];

      for (final item in response) {
        final event = item['events'];
        if (event == null) continue;

        final eventMap = Map<String, dynamic>.from(event);
        final eventDate = _parseEventDateTime(
          (eventMap['event_date'] ?? '').toString(),
          (eventMap['event_time'] ?? '').toString(),
        );

        if (eventDate == null) continue;

        if (!eventDate.isBefore(today) && eventDate.isBefore(endOfWeek)) {
          weekEvents.add({
            ...eventMap,
            'status': item['status'],
            'event_datetime': eventDate,
          });
        }
      }

      weekEvents.sort(
        (a, b) => (a['event_datetime'] as DateTime)
            .compareTo(b['event_datetime'] as DateTime),
      );

      if (mounted) {
        setState(() {
          _weekEvents = weekEvents;
        });
      }
    } catch (e) {
      debugPrint('Erro ao carregar eventos da semana: $e');
    }
  }

  DateTime? _parseEventDateTime(String dateStr, String timeStr) {
    try {
      final dp = dateStr.trim().split('/');
      final tp = timeStr.trim().split(':');
      if (dp.length != 3 || tp.length < 2) return null;
      return DateTime(
        int.parse(dp[2]),
        int.parse(dp[1]),
        int.parse(dp[0]),
        int.parse(tp[0]),
        int.parse(tp[1]),
      );
    } catch (_) {
      return null;
    }
  }

  String _getAgendaSubtitle() {
    if (_weekEvents.isEmpty) {
      return 'Veja suas convocações e eventos';
    }
    final nextEvent = _weekEvents.first;
    final eventDate = nextEvent['event_datetime'] as DateTime;
    final dayLabel = DateFormat('EEE', 'pt_BR').format(eventDate);
    final dayLabelCapitalized =
        dayLabel[0].toUpperCase() + dayLabel.substring(1).replaceAll('.', '');
    return 'Próximo: $dayLabelCapitalized às ${DateFormat('HH:mm').format(eventDate)}';
  }

  Future<void> _redirectToLogin() async {
    await supabase.auth.signOut();
    if (mounted) {
      Navigator.pushNamedAndRemoveUntil(
        context,
        '/login',
        (route) => false,
      );
    }
  }

  void _navigateToProfilePage() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AthleteProfilePage(profile: _profile),
      ),
    ).then((_) => _loadProfile());
  }

  void _navigateToAgenda() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const AthleteAgendaPage(),
      ),
    ).then((_) {
      _loadPendingCount();
      _loadWeekEvents();
    });
  }

  void _navigateToFinancial() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const AthleteFinancialPage(),
      ),
    ).then((_) => _loadOverdueFinancialCount());
  }

  // ✅ Card de Informações do Atleta (Stat Card)
  Widget _buildAthleteInfoCard() {
    final firstName =
        _profile?['full_name']?.toString().split(' ').first ?? 'Atleta';
    final position = _profile?['court_position']?.toString() ?? 'Não definida';
    final avatarUrl = _profile?['avatar_url']?.toString();

    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [olympusBlue, olympusLightBlue],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: olympusGold.withOpacity(0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Foto do Atleta
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: olympusGold, width: 3),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: ClipOval(
                child: avatarUrl != null && avatarUrl.isNotEmpty
                    ? Image.network(
                        avatarUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (c, o, s) =>
                            _buildAvatarPlaceholder(firstName),
                      )
                    : _buildAvatarPlaceholder(firstName),
              ),
            ),
            const SizedBox(width: 16),
            // Informações
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Olá, $firstName!',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: olympusGold,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.sports_volleyball,
                          size: 16,
                          color: olympusBlue,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          position,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: olympusBlue,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildWeekEventsMiniCard(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWeekEventsMiniCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.white.withOpacity(0.18),
        ),
      ),
      child: _weekEvents.isEmpty
          ? Row(
              children: const [
                Icon(
                  Icons.event_available,
                  size: 16,
                  color: Colors.white70,
                ),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Nenhum evento nesta semana',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Eventos da semana',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                ..._weekEvents.take(2).map((event) {
                  final eventDate = event['event_datetime'] as DateTime;
                  final formattedDay = DateFormat('dd/MM').format(eventDate);
                  final formattedTime = DateFormat('HH:mm').format(eventDate);
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: olympusGold,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '$formattedDay • $formattedTime',
                            style: const TextStyle(
                              color: olympusBlue,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            (event['event_name'] ?? 'Evento').toString(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
                if (_weekEvents.length > 2)
                  Text(
                    '+${_weekEvents.length - 2} evento(s)',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _buildAvatarPlaceholder(String firstName) {
    return Container(
      color: olympusGold.withOpacity(0.2),
      child: Center(
        child: Text(
          firstName[0].toUpperCase(),
          style: const TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.bold,
            color: olympusBlue,
          ),
        ),
      ),
    );
  }

  // ✅ NOVO: Widget de Card/Tile de Dashboard
  Widget _buildDashboardCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
    int? badgeCount,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.2),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
          border: Border.all(
            color: color.withOpacity(0.3),
            width: 2,
          ),
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  // Ícone
                  Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      icon,
                      size: 32,
                      color: color,
                    ),
                  ),
                  const SizedBox(width: 16),
                  // Texto
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: color,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          subtitle,
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Seta
                  Icon(
                    Icons.arrow_forward_ios,
                    color: color.withOpacity(0.5),
                    size: 18,
                  ),
                ],
              ),
            ),
            // Badge de pendentes
            if (badgeCount != null && badgeCount > 0)
              Positioned(
                right: 12,
                top: 12,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.red,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.red.withOpacity(0.4),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Text(
                    badgeCount.toString(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ✅ NOVO: Card de Alerta Financeiro
  Widget _buildFinancialAlertCard() {
    if (_overdueFinancialCount == 0) return const SizedBox.shrink();

    // Construir mensagem com meses
    String monthMessage = '';
    final sortedMonths = _overdueByMonth.keys.toList()
      ..sort((a, b) => b.compareTo(a));

    for (int i = 0; i < sortedMonths.length; i++) {
      final month = sortedMonths[i];
      final count = _overdueByMonth[month]!;
      final monthName = DateFormat.MMMM('pt_BR').format(DateTime(2024, month));
      final monthNameCapitalized =
          monthName[0].toUpperCase() + monthName.substring(1);

      if (i > 0) {
        monthMessage += ' e ';
      }
      monthMessage +=
          '$count ${count == 1 ? "pagamento" : "pagamentos"} em atraso em $monthNameCapitalized';
    }

    return GestureDetector(
      onTap: _navigateToFinancial,
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Colors.red.shade50,
              Colors.red.shade100,
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: Colors.red.shade300,
            width: 2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.red.withOpacity(0.3),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Ícone de alerta
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: Colors.red.shade100,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.warning_rounded,
                  color: Colors.red.shade700,
                  size: 32,
                ),
              ),
              const SizedBox(width: 16),
              // Texto
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Pendência financeira em atraso',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.red.shade900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      monthMessage,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.red.shade700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Acesse o financeiro e regularize o quanto antes.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.red.shade600,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios,
                color: Colors.red.shade400,
                size: 16,
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Área do Atleta'),
        backgroundColor: olympusBlue,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.person, color: Colors.white),
            tooltip: 'Perfil',
            onPressed: _navigateToProfilePage,
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Sair',
            onPressed: _redirectToLogin,
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // ✅ Card de Informações do Atleta - MOVIDO PARA O TOPO
            _buildAthleteInfoCard(),
            // ✅ NOVO: Card de Alerta Financeiro (só aparece se houver atraso)
            _buildFinancialAlertCard(),
            const SizedBox(height: 12),
            // ✅ Cards de Dashboard
            _buildDashboardCard(
              icon: Icons.calendar_today,
              title: 'Minha Agenda',
              subtitle: _getAgendaSubtitle(),
              color: olympusGold,
              onTap: _navigateToAgenda,
              badgeCount: _pendingCount > 0 ? _pendingCount : null,
            ),
            _buildDashboardCard(
              icon: Icons.attach_money,
              title: 'Financeiro',
              subtitle: 'Acompanhe seus pagamentos',
              color: olympusBlue,
              onTap: _navigateToFinancial,
              badgeCount:
                  _overdueFinancialCount > 0 ? _overdueFinancialCount : null,
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// TELA DE PERFIL COMPLETA DO ATLETA
// ============================================================================
class AthleteProfilePage extends StatefulWidget {
  final Map<String, dynamic>? profile;

  const AthleteProfilePage({super.key, this.profile});

  @override
  State<AthleteProfilePage> createState() => _AthleteProfilePageState();
}

class _AthleteProfilePageState extends State<AthleteProfilePage> {
  final supabase = Supabase.instance.client;

  // ✅ Cores do logo Olympus Voleibol
  static const Color olympusBlue = Color(0xFF1E3A5F);
  static const Color olympusGold = Color(0xFFD4AF37);
  static const Color olympusLightBlue = Color(0xFF2C5F8D);

  void _showChangePasswordDialog() {
    final currentPasswordCtrl = TextEditingController();
    final newPasswordCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    bool _isLoading = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.lock, color: olympusGold),
              const SizedBox(width: 8),
              const Text('Mudar Senha'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: currentPasswordCtrl,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: 'Senha Atual *',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.lock, color: olympusGold),
                  focusedBorder: OutlineInputBorder(
                    borderSide: const BorderSide(color: olympusGold, width: 2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: newPasswordCtrl,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: 'Nova Senha *',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.lock, color: olympusGold),
                  focusedBorder: OutlineInputBorder(
                    borderSide: const BorderSide(color: olympusGold, width: 2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: confirmCtrl,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: 'Confirmar Nova Senha *',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.lock, color: olympusGold),
                  focusedBorder: OutlineInputBorder(
                    borderSide: const BorderSide(color: olympusGold, width: 2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: _isLoading
                  ? null
                  : () async {
                      if (newPasswordCtrl.text != confirmCtrl.text) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('As senhas não conferem'),
                            backgroundColor: Colors.red,
                          ),
                        );
                        return;
                      }
                      if (newPasswordCtrl.text.length < 6) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Mínimo 6 caracteres'),
                            backgroundColor: Colors.red,
                          ),
                        );
                        return;
                      }

                      setDialogState(() => _isLoading = true);
                      try {
                        final user = supabase.auth.currentUser;
                        if (user == null || user.email == null) {
                          throw Exception('Usuário não autenticado');
                        }

                        try {
                          await supabase.auth.signInWithPassword(
                            email: user.email!,
                            password: currentPasswordCtrl.text,
                          );
                        } catch (e) {
                          throw Exception('Senha atual incorreta');
                        }

                        await supabase.auth.updateUser(
                          UserAttributes(password: newPasswordCtrl.text),
                        );

                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('✅ Senha alterada com sucesso!'),
                            backgroundColor: olympusBlue,
                          ),
                        );
                        Navigator.pop(context);
                      } catch (e) {
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Erro: ${e.toString()}'),
                            backgroundColor: Colors.red,
                          ),
                        );
                      } finally {
                        if (mounted) {
                          setDialogState(() => _isLoading = false);
                        }
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: olympusGold,
                foregroundColor: olympusBlue,
              ),
              child: _isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(olympusBlue),
                      ),
                    )
                  : const Text('Salvar'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final profile = widget.profile;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Meu Perfil'),
        backgroundColor: olympusBlue,
        foregroundColor: Colors.white,
        elevation: 2,
      ),
      body: profile == null
          ? Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(olympusGold),
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Column(
                      children: [
                        CircleAvatar(
                          radius: 60,
                          backgroundColor: olympusGold.withOpacity(0.2),
                          backgroundImage: profile['avatar_url'] != null &&
                                  profile['avatar_url'].toString().isNotEmpty
                              ? NetworkImage(profile['avatar_url'])
                              : null,
                          child: profile['avatar_url'] == null ||
                                  profile['avatar_url'].toString().isEmpty
                              ? Text(
                                  profile['full_name']?[0]?.toUpperCase() ??
                                      '?',
                                  style: const TextStyle(
                                    fontSize: 40,
                                    fontWeight: FontWeight.bold,
                                    color: olympusBlue,
                                  ),
                                )
                              : null,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          profile['full_name'] ?? 'Sem nome',
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: olympusBlue,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        Text(
                          _getUserTypeLabel(profile['user_type']),
                          style: TextStyle(
                            fontSize: 16,
                            color: olympusGold,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) =>
                                    _AthleteProfileEditDialog(profile: profile),
                              ),
                            ).then((_) => Navigator.pop(context, true));
                          },
                          icon: const Icon(Icons.edit),
                          label: const Text('Alterar Dados'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: olympusGold,
                            foregroundColor: olympusBlue,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _showChangePasswordDialog,
                          icon: const Icon(Icons.lock),
                          label: const Text('Alterar Senha'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: olympusBlue,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  _buildSectionTitle('Dados Pessoais'),
                  _buildInfoTile(Icons.person, 'Nome', profile['full_name']),
                  _buildInfoTile(Icons.email, 'E-mail',
                      profile['email'] ?? 'Não informado'),
                  _buildInfoTile(
                      Icons.phone, 'Telefone', _formatPhone(profile['phone'])),
                  _buildInfoTile(
                      Icons.credit_card, 'CPF', _formatCpf(profile['cpf'])),
                  _buildInfoTile(
                      Icons.badge, 'RG', profile['rg'] ?? 'Não informado'),
                  _buildInfoTile(Icons.calendar_today, 'Data de Nascimento',
                      _formatDate(profile['birth_date'])),
                  _buildInfoTile(
                      Icons.transgender, 'Gênero', profile['gender']),
                  if (profile['court_position'] != null &&
                      profile['court_position'].toString().isNotEmpty)
                    _buildInfoTile(Icons.sports_volleyball, 'Posição na Quadra',
                        profile['court_position']),
                  const SizedBox(height: 24),
                  _buildSectionTitle('Endereço'),
                  _buildInfoTile(Icons.location_on, 'CEP',
                      _formatCep(profile['zip_code'])),
                  _buildInfoTile(Icons.home, 'Rua', profile['street']),
                  _buildInfoTile(Icons.pin, 'Número', profile['street_number']),
                  if (profile['complement'] != null &&
                      profile['complement'].toString().isNotEmpty)
                    _buildInfoTile(
                        Icons.apartment, 'Complemento', profile['complement']),
                  _buildInfoTile(
                      Icons.location_city, 'Bairro', profile['neighborhood']),
                  _buildInfoTile(
                      Icons.location_city, 'Cidade', profile['city']),
                  _buildInfoTile(Icons.public, 'Estado', profile['state']),
                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 20,
            decoration: BoxDecoration(
              color: olympusGold,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: olympusBlue,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoTile(IconData icon, String label, String? value) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: olympusGold.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: olympusGold, size: 20),
      ),
      title: Text(
        label,
        style: const TextStyle(fontSize: 12, color: Colors.grey),
      ),
      subtitle: Text(
        value ?? 'Não informado',
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w500,
          color: olympusBlue,
        ),
      ),
      contentPadding: EdgeInsets.zero,
    );
  }

  String _formatPhone(String? phone) {
    if (phone == null) return 'Não informado';
    final numbers = phone.replaceAll(RegExp(r'\D'), '');
    if (numbers.length == 11) {
      return '(${numbers.substring(0, 2)}) ${numbers.substring(2, 7)}-${numbers.substring(7)}';
    } else if (numbers.length == 10) {
      return '(${numbers.substring(0, 2)}) ${numbers.substring(2, 6)}-${numbers.substring(6)}';
    }
    return phone;
  }

  String _formatCpf(String? cpf) {
    if (cpf == null) return 'Não informado';
    final numbers = cpf.replaceAll(RegExp(r'\D'), '');
    if (numbers.length != 11) return cpf;
    return '${numbers.substring(0, 3)}.${numbers.substring(3, 6)}.${numbers.substring(6, 9)}-${numbers.substring(9)}';
  }

  String _formatCep(String? cep) {
    if (cep == null) return 'Não informado';
    final numbers = cep.replaceAll(RegExp(r'\D'), '');
    if (numbers.length != 8) return cep;
    return '${numbers.substring(0, 5)}-${numbers.substring(5)}';
  }

  String _formatDate(String? date) {
    if (date == null) return 'Não informado';
    try {
      final dt = DateTime.parse(date);
      return DateFormat('dd/MM/yyyy').format(dt);
    } catch (e) {
      return date;
    }
  }

  String _getUserTypeLabel(String? userType) {
    switch (userType) {
      case 'athlete':
        return 'Atleta';
      case 'coach':
        return 'Técnico';
      case 'admin':
        return 'Administrador';
      default:
        return 'Membro';
    }
  }
}

// ============================================================================
// DIÁLOGO DE EDIÇÃO DE PERFIL (COM FILTRO DE POSIÇÃO POR GÊNERO)
// ============================================================================
class _AthleteProfileEditDialog extends StatefulWidget {
  final Map<String, dynamic> profile;

  const _AthleteProfileEditDialog({required this.profile});

  @override
  State<_AthleteProfileEditDialog> createState() =>
      _AthleteProfileEditDialogState();
}

class _AthleteProfileEditDialogState extends State<_AthleteProfileEditDialog> {
  final _formKey = GlobalKey<FormState>();
  final _picker = ImagePicker();
  final supabase = Supabase.instance.client;

  late TextEditingController _fullNameController;
  late MaskedTextController _phoneController;
  late TextEditingController _birthDateController;
  late MaskedTextController _rgController;
  late MaskedTextController _cpfController;
  late TextEditingController _genderController;
  late TextEditingController _positionController;
  late MaskedTextController _zipCodeController;
  late TextEditingController _streetController;
  late TextEditingController _streetNumberController;
  late TextEditingController _complementController;
  late TextEditingController _neighborhoodController;
  late TextEditingController _cityController;
  late TextEditingController _stateController;

  XFile? _selectedImage;
  bool _isLoading = false;
  bool _isUploading = false;
  bool _isFetchingCep = false;
  String _selectedGender = '';

  // ✅ Cores do logo Olympus Voleibol
  static const Color olympusBlue = Color(0xFF1E3A5F);
  static const Color olympusGold = Color(0xFFD4AF37);
  static const Color olympusLightBlue = Color(0xFF2C5F8D);

  final Map<String, List<Map<String, String>>> _positions = {
    'Masculino': [
      {'value': 'Ponteiro', 'label': 'Ponteiro'},
      {'value': 'Levantador', 'label': 'Levantador'},
      {'value': 'Central', 'label': 'Central'},
      {'value': 'Oposto', 'label': 'Oposto'},
      {'value': 'Líbero', 'label': 'Líbero'},
    ],
    'Feminino': [
      {'value': 'Ponteira', 'label': 'Ponteira'},
      {'value': 'Levantadora', 'label': 'Levantadora'},
      {'value': 'Central', 'label': 'Central'},
      {'value': 'Oposta', 'label': 'Oposta'},
      {'value': 'Líbero', 'label': 'Líbero'},
    ],
  };

  @override
  void initState() {
    super.initState();
    _fullNameController =
        TextEditingController(text: widget.profile['full_name'] ?? '');
    _phoneController = MaskedTextController(
        mask: '(00) 00000-0000', text: widget.profile['phone'] ?? '');
    _birthDateController =
        TextEditingController(text: widget.profile['birth_date'] ?? '');
    _rgController = MaskedTextController(
        mask: '00.000.000-0', text: widget.profile['rg'] ?? '');
    _cpfController = MaskedTextController(
        mask: '000.000.000-00', text: widget.profile['cpf'] ?? '');
    _genderController =
        TextEditingController(text: widget.profile['gender'] ?? '');
    _positionController =
        TextEditingController(text: widget.profile['court_position'] ?? '');
    _zipCodeController = MaskedTextController(
        mask: '00000-000', text: widget.profile['zip_code'] ?? '');
    _streetController =
        TextEditingController(text: widget.profile['street'] ?? '');
    _streetNumberController =
        TextEditingController(text: widget.profile['street_number'] ?? '');
    _complementController =
        TextEditingController(text: widget.profile['complement'] ?? '');
    _neighborhoodController =
        TextEditingController(text: widget.profile['neighborhood'] ?? '');
    _cityController = TextEditingController(text: widget.profile['city'] ?? '');
    _stateController =
        TextEditingController(text: widget.profile['state'] ?? '');

    _selectedGender = widget.profile['gender'] ?? '';

    _zipCodeController.addListener(_onZipCodeChanged);
  }

  void _onZipCodeChanged() {
    final cep = _zipCodeController.text.replaceAll(RegExp(r'\D'), '');
    if (cep.length == 8 && !_isFetchingCep) {
      _fetchAddressByCep(cep);
    }
  }

  Future<void> _fetchAddressByCep(String cep) async {
    setState(() => _isFetchingCep = true);
    try {
      final response =
          await http.get(Uri.parse('https://viacep.com.br/ws/$cep/json/'));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['erro'] == null && mounted) {
          setState(() {
            _streetController.text = data['logradouro'] ?? '';
            _neighborhoodController.text = data['bairro'] ?? '';
            _cityController.text = data['localidade'] ?? '';
            _stateController.text = data['uf'] ?? '';
          });
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('✅ Endereço preenchido automaticamente!'),
                duration: Duration(seconds: 2),
                backgroundColor: olympusBlue,
              ),
            );
          }
        }
      }
    } catch (e) {
      debugPrint('Erro ao buscar CEP: $e');
    } finally {
      if (mounted) {
        setState(() => _isFetchingCep = false);
      }
    }
  }

  Future<void> _pickImage() async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 85,
      );
      if (image != null && mounted) {
        setState(() {
          _selectedImage = image;
        });
      }
    } catch (e) {
      debugPrint('Erro ao selecionar imagem: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Erro ao selecionar imagem'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<String?> _uploadImage() async {
    if (_selectedImage == null) return null;

    setState(() => _isUploading = true);
    try {
      final user = supabase.auth.currentUser;
      final fileName =
          '${DateTime.now().millisecondsSinceEpoch}_${user?.id}.jpg';
      final Uint8List? fileBytes = await _selectedImage!.readAsBytes();
      if (fileBytes == null) return null;

      await supabase.storage.from('avatars').uploadBinary(
            fileName,
            fileBytes,
            fileOptions: const FileOptions(upsert: true),
          );

      final publicUrl = supabase.storage.from('avatars').getPublicUrl(fileName);
      return publicUrl;
    } catch (e) {
      debugPrint('Erro ao fazer upload: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao fazer upload: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return null;
    } finally {
      if (mounted) {
        setState(() => _isUploading = false);
      }
    }
  }

  Future<void> _selectDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: olympusGold,
              onPrimary: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null && mounted) {
      setState(() {
        _birthDateController.text = DateFormat('dd/MM/yyyy').format(picked);
      });
    }
  }

  String _removeMask(String? text) {
    if (text == null || text.isEmpty) return '';
    return text.replaceAll(RegExp(r'\D'), '');
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    try {
      String? avatarUrl;
      if (_selectedImage != null) {
        avatarUrl = await _uploadImage();
      }

      final user = supabase.auth.currentUser;
      if (user == null) throw Exception('Usuário não autenticado');

      final data = <String, dynamic>{
        'full_name': _fullNameController.text.trim(),
        'phone': _removeMask(_phoneController.text),
        'birth_date': _birthDateController.text,
        'rg': _removeMask(_rgController.text),
        'cpf': _removeMask(_cpfController.text),
        'gender': _genderController.text.trim(),
        'court_position': _positionController.text.trim(),
        'zip_code': _removeMask(_zipCodeController.text),
        'street': _streetController.text.trim(),
        'street_number': _streetNumberController.text.trim(),
        'complement': _complementController.text.trim(),
        'neighborhood': _neighborhoodController.text.trim(),
        'city': _cityController.text.trim(),
        'state': _stateController.text.trim().toUpperCase(),
        'updated_at': DateTime.now().toIso8601String(),
        if (avatarUrl != null) 'avatar_url': avatarUrl,
      };

      await supabase.from('profiles').update(data).eq('id', user.id);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Perfil atualizado com sucesso!'),
          backgroundColor: olympusBlue,
        ),
      );
      Navigator.pop(context);
    } catch (e) {
      debugPrint('❌ Erro ao salvar perfil: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao salvar: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Editar Perfil'),
        backgroundColor: olympusBlue,
        foregroundColor: Colors.white,
        elevation: 2,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: GestureDetector(
                  onTap: _pickImage,
                  child: Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      color: olympusGold.withOpacity(0.1),
                      shape: BoxShape.circle,
                      border: Border.all(color: olympusGold, width: 3),
                    ),
                    child: ClipOval(
                      child: _getAvatarImage(),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Center(
                child: TextButton.icon(
                  onPressed: _pickImage,
                  icon: const Icon(Icons.photo_camera, color: olympusGold),
                  label: const Text(
                    'Selecionar Foto',
                    style: TextStyle(color: olympusBlue),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _fullNameController,
                decoration: InputDecoration(
                  labelText: 'Nome Completo *',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.person, color: olympusGold),
                  focusedBorder: OutlineInputBorder(
                    borderSide: const BorderSide(color: olympusGold, width: 2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                validator: (value) =>
                    value?.isEmpty ?? true ? 'Campo obrigatório' : null,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _cpfController,
                      decoration: InputDecoration(
                        labelText: 'CPF *',
                        border: const OutlineInputBorder(),
                        prefixIcon:
                            const Icon(Icons.credit_card, color: olympusGold),
                        focusedBorder: OutlineInputBorder(
                          borderSide:
                              const BorderSide(color: olympusGold, width: 2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      keyboardType: TextInputType.number,
                      validator: (value) => _removeMask(value).length != 11
                          ? 'CPF inválido'
                          : null,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      controller: _rgController,
                      decoration: InputDecoration(
                        labelText: 'RG *',
                        border: const OutlineInputBorder(),
                        prefixIcon:
                            const Icon(Icons.credit_card, color: olympusGold),
                        focusedBorder: OutlineInputBorder(
                          borderSide:
                              const BorderSide(color: olympusGold, width: 2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      keyboardType: TextInputType.number,
                      validator: (value) =>
                          value?.isEmpty ?? true ? 'Campo obrigatório' : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _phoneController,
                      decoration: InputDecoration(
                        labelText: 'Telefone *',
                        border: const OutlineInputBorder(),
                        prefixIcon: const Icon(Icons.phone, color: olympusGold),
                        focusedBorder: OutlineInputBorder(
                          borderSide:
                              const BorderSide(color: olympusGold, width: 2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      keyboardType: TextInputType.phone,
                      validator: (value) => _removeMask(value).length < 10
                          ? 'Telefone inválido'
                          : null,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value:
                          _selectedGender.isNotEmpty ? _selectedGender : null,
                      decoration: InputDecoration(
                        labelText: 'Gênero *',
                        border: const OutlineInputBorder(),
                        prefixIcon:
                            const Icon(Icons.transgender, color: olympusGold),
                        focusedBorder: OutlineInputBorder(
                          borderSide:
                              const BorderSide(color: olympusGold, width: 2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      items: const [
                        DropdownMenuItem(
                            value: 'Masculino', child: Text('Masculino')),
                        DropdownMenuItem(
                            value: 'Feminino', child: Text('Feminino')),
                      ],
                      onChanged: (value) {
                        setState(() {
                          _selectedGender = value ?? '';
                          _positionController.text = '';
                          _genderController.text = value ?? '';
                        });
                      },
                      validator: (value) =>
                          value == null ? 'Campo obrigatório' : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _birthDateController,
                decoration: InputDecoration(
                  labelText: 'Data de Nascimento',
                  border: const OutlineInputBorder(),
                  prefixIcon:
                      const Icon(Icons.calendar_today, color: olympusGold),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.calendar_today, color: olympusGold),
                    onPressed: _selectDate,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: const BorderSide(color: olympusGold, width: 2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                readOnly: true,
              ),
              const SizedBox(height: 12),
              if (_selectedGender.isNotEmpty)
                DropdownButtonFormField<String>(
                  value: _positionController.text.isNotEmpty
                      ? _positionController.text
                      : null,
                  decoration: InputDecoration(
                    labelText: 'Posição na Quadra',
                    border: const OutlineInputBorder(),
                    prefixIcon:
                        const Icon(Icons.sports_volleyball, color: olympusGold),
                    focusedBorder: OutlineInputBorder(
                      borderSide:
                          const BorderSide(color: olympusGold, width: 2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  items: (_positions[_selectedGender] ?? [])
                      .map((pos) => DropdownMenuItem(
                            value: pos['value'],
                            child: Text(pos['label']!),
                          ))
                      .toList(),
                  onChanged: (value) =>
                      setState(() => _positionController.text = value ?? ''),
                ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Icon(Icons.location_on, color: olympusGold, size: 20),
                  const SizedBox(width: 8),
                  const Text(
                    'Endereço',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: olympusBlue,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _zipCodeController,
                decoration: InputDecoration(
                  labelText: 'CEP *',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.location_on, color: olympusGold),
                  suffixIcon: _isFetchingCep
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(olympusGold),
                          ),
                        )
                      : null,
                  focusedBorder: OutlineInputBorder(
                    borderSide: const BorderSide(color: olympusGold, width: 2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                keyboardType: TextInputType.number,
                maxLength: 9,
                validator: (value) =>
                    _removeMask(value).length != 8 ? 'CEP inválido' : null,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: TextFormField(
                      controller: _streetController,
                      decoration: InputDecoration(
                        labelText: 'Rua *',
                        border: const OutlineInputBorder(),
                        focusedBorder: OutlineInputBorder(
                          borderSide:
                              const BorderSide(color: olympusGold, width: 2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      validator: (value) =>
                          value?.isEmpty ?? true ? 'Campo obrigatório' : null,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      controller: _streetNumberController,
                      decoration: InputDecoration(
                        labelText: 'Número *',
                        border: const OutlineInputBorder(),
                        focusedBorder: OutlineInputBorder(
                          borderSide:
                              const BorderSide(color: olympusGold, width: 2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      keyboardType: TextInputType.number,
                      validator: (value) =>
                          value?.isEmpty ?? true ? 'Campo obrigatório' : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _complementController,
                decoration: InputDecoration(
                  labelText: 'Complemento',
                  border: const OutlineInputBorder(),
                  focusedBorder: OutlineInputBorder(
                    borderSide: const BorderSide(color: olympusGold, width: 2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _neighborhoodController,
                decoration: InputDecoration(
                  labelText: 'Bairro *',
                  border: const OutlineInputBorder(),
                  focusedBorder: OutlineInputBorder(
                    borderSide: const BorderSide(color: olympusGold, width: 2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                validator: (value) =>
                    value?.isEmpty ?? true ? 'Campo obrigatório' : null,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: TextFormField(
                      controller: _cityController,
                      decoration: InputDecoration(
                        labelText: 'Cidade *',
                        border: const OutlineInputBorder(),
                        focusedBorder: OutlineInputBorder(
                          borderSide:
                              const BorderSide(color: olympusGold, width: 2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      validator: (value) =>
                          value?.isEmpty ?? true ? 'Campo obrigatório' : null,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      controller: _stateController,
                      decoration: InputDecoration(
                        labelText: 'Estado *',
                        border: const OutlineInputBorder(),
                        focusedBorder: OutlineInputBorder(
                          borderSide:
                              const BorderSide(color: olympusGold, width: 2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      maxLength: 2,
                      validator: (value) =>
                          value?.isEmpty ?? true ? 'Campo obrigatório' : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),
              SizedBox(
                height: 50,
                child: ElevatedButton(
                  onPressed: _isLoading || _isUploading ? null : _saveProfile,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: olympusGold,
                    foregroundColor: olympusBlue,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 2,
                    shadowColor: olympusGold.withOpacity(0.4),
                  ),
                  child: _isLoading || _isUploading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(olympusBlue),
                          ),
                        )
                      : const Text(
                          'Salvar Alterações',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _getAvatarImage() {
    if (_selectedImage != null) {
      return FutureBuilder<Uint8List?>(
        future: _selectedImage!.readAsBytes(),
        builder: (context, snapshot) {
          if (snapshot.hasData && snapshot.data != null) {
            return Image.memory(snapshot.data!, fit: BoxFit.cover);
          }
          return const Icon(Icons.person, size: 60, color: Colors.grey);
        },
      );
    }
    if (widget.profile['avatar_url'] != null &&
        widget.profile['avatar_url'].toString().isNotEmpty) {
      return Image.network(
        widget.profile['avatar_url'],
        fit: BoxFit.cover,
        errorBuilder: (c, o, s) =>
            const Icon(Icons.person, size: 60, color: Colors.grey),
      );
    }
    return const Icon(Icons.person, size: 60, color: Colors.grey);
  }

  @override
  void dispose() {
    _zipCodeController.removeListener(_onZipCodeChanged);
    _fullNameController.dispose();
    _phoneController.dispose();
    _birthDateController.dispose();
    _rgController.dispose();
    _cpfController.dispose();
    _genderController.dispose();
    _positionController.dispose();
    _zipCodeController.dispose();
    _streetController.dispose();
    _streetNumberController.dispose();
    _complementController.dispose();
    _neighborhoodController.dispose();
    _cityController.dispose();
    _stateController.dispose();
    super.dispose();
  }
}
