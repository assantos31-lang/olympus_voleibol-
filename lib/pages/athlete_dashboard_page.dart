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
import 'chat_rooms_page.dart';

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
  int _pendingCount = 0;
  int _overdueFinancialCount = 0;
  Map<int, int> _overdueByMonth = {};
  List<Map<String, dynamic>> _weekEvents = [];

  int _confirmedPresenceCount = 0;
  int _rejectedPresenceCount = 0;
  int _monthlyTrainingTotal = 0;
  int _monthlyPresenceCount = 0;
  int _monthlyAbsenceCount = 0;
  double _monthlyPresencePercent = 0;

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
        _loadPendingCount();
        _loadOverdueFinancialCount();
        _loadWeekEvents();
        _loadAttendanceAndPerformance();
      }
    }
  }

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

  Future<void> _loadAttendanceAndPerformance() async {
    try {
      final user = supabase.auth.currentUser;
      if (user == null) return;

      final response = await supabase.from('convocations').select('''
event_id,
status,
justification,
events!$_eventsEmbedFk (
id,
event_name,
event_type,
event_date,
event_time
)
''').eq('user_id', user.id);

      final now = DateTime.now();
      final month = now.month;
      final year = now.year;

      final List<Map<String, dynamic>> trainingEvents = [];
      final List<String> trainingEventIds = [];

      int confirmedPresence = 0;
      int rejectedPresence = 0;

      for (final item in response) {
        final event = item['events'];
        if (event == null) continue;

        final status = (item['status'] ?? '').toString().toLowerCase().trim();
        final justification =
            (item['justification'] ?? '').toString().toLowerCase().trim();

        if (status == 'rejected') {
          rejectedPresence++;
        }

        final eventMap = Map<String, dynamic>.from(event);
        final eventType =
            (eventMap['event_type'] ?? '').toString().toLowerCase().trim();

        if (eventType != 'treino') continue;

        final eventDate = _parseEventDateTime(
          (eventMap['event_date'] ?? '').toString(),
          (eventMap['event_time'] ?? '').toString(),
        );
        if (eventDate == null) continue;
        if (eventDate.month != month || eventDate.year != year) continue;

        final eventId = (eventMap['id'] ?? '').toString();
        if (eventId.isEmpty) continue;

        trainingEvents.add({
          ...eventMap,
          'status': status,
          'justification': justification,
          'event_datetime': eventDate,
        });
        trainingEventIds.add(eventId);
      }

      final checkins = trainingEventIds.isEmpty
          ? <dynamic>[]
          : await supabase
              .from('checkins')
              .select('event_id, check_in_status')
              .eq('user_id', user.id)
              .inFilter('event_id', trainingEventIds);

      final Map<String, String> checkinMap = {};
      for (final row in checkins) {
        final eventId = (row['event_id'] ?? '').toString();
        if (eventId.isEmpty) continue;
        checkinMap[eventId] =
            (row['check_in_status'] ?? '').toString().toLowerCase().trim();
      }

      int monthlyPresence = 0;
      int monthlyAbsence = 0;

      for (final event in trainingEvents) {
        final eventId = (event['id'] ?? '').toString();
        final status = (event['status'] ?? '').toString().toLowerCase().trim();
        final justification =
            (event['justification'] ?? '').toString().toLowerCase().trim();
        final checkinStatus = (checkinMap[eventId] ?? '').toLowerCase().trim();
        final eventDate = event['event_datetime'] as DateTime;

        if (checkinStatus == 'ok') {
          monthlyPresence++;
          confirmedPresence++;
          continue;
        }

        final checkinExpired =
            now.isAfter(eventDate.add(const Duration(minutes: 30)));

        final isAbsence = checkinExpired &&
            ((status == 'accepted' && checkinStatus != 'ok') ||
                (status == 'rejected' && justification == 'prazo expirado'));

        if (isAbsence) {
          monthlyAbsence++;
        }
      }

      final totalTrainings = trainingEvents.length;
      final presencePercent =
          totalTrainings > 0 ? (monthlyPresence / totalTrainings) * 100 : 0.0;

      if (mounted) {
        setState(() {
          _confirmedPresenceCount = confirmedPresence;
          _rejectedPresenceCount = rejectedPresence;
          _monthlyTrainingTotal = totalTrainings;
          _monthlyPresenceCount = monthlyPresence;
          _monthlyAbsenceCount = monthlyAbsence;
          _monthlyPresencePercent = presencePercent;
        });
      }
    } catch (e) {
      debugPrint('Erro ao carregar presença/desempenho: $e');
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

  String _getPerformanceLevel() {
    if (_monthlyPresencePercent <= 40) {
      return 'Iniciante';
    } else if (_monthlyPresencePercent <= 50) {
      return 'Participante';
    } else if (_monthlyPresencePercent <= 60) {
      return 'Regular';
    } else if (_monthlyPresencePercent <= 70) {
      return 'Comprometido';
    } else if (_monthlyPresencePercent <= 80) {
      return 'Intermediário';
    } else if (_monthlyPresencePercent <= 90) {
      return 'Avançado';
    }
    return 'Elite';
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
      _loadAttendanceAndPerformance();
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

  void _navigateToChat() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const ChatRoomsPage(),
      ),
    );
  }

  Widget _buildAthleteInfoCard() {
    final firstName =
        _profile?['full_name']?.toString().split(' ').first ?? 'Atleta';
    final position = _profile?['court_position']?.toString() ?? 'Não definida';
    final avatarUrl = _profile?['avatar_url']?.toString();

    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: const Color(0xFF9FB6C9).withOpacity(0.75),
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.25),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
          BoxShadow(
            color: olympusGold.withOpacity(0.12),
            blurRadius: 24,
            spreadRadius: 1,
          ),
        ],
        gradient: const LinearGradient(
          colors: [
            Color(0xFF0D223B),
            Color(0xFF123861),
            Color(0xFF235E94),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          children: [
            Positioned.fill(
              child: Opacity(
                opacity: 0.12,
                child: avatarUrl != null && avatarUrl.isNotEmpty
                    ? Image.network(
                        avatarUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                      )
                    : const SizedBox.shrink(),
              ),
            ),
            Positioned(
              top: -40,
              right: -30,
              child: Container(
                width: 140,
                height: 140,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withOpacity(0.08),
                ),
              ),
            ),
            Positioned(
              bottom: -50,
              left: -30,
              child: Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: olympusGold.withOpacity(0.08),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
              child: Column(
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 68,
                        height: 68,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(18),
                          gradient: const LinearGradient(
                            colors: [Color(0xFFF0D771), Color(0xFFB48A23)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: olympusGold.withOpacity(0.45),
                              blurRadius: 12,
                              spreadRadius: 1,
                            ),
                          ],
                        ),
                        padding: const EdgeInsets.all(2.2),
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            color: const Color(0xFF113457),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(15),
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
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Olá, $firstName!',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                  height: 1.1,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(22),
                                  gradient: const LinearGradient(
                                    colors: [
                                      Color(0xFFD7E3EE),
                                      Color(0xFFBFCFDD),
                                    ],
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                  ),
                                  border: Border.all(
                                    color: const Color(0xFF90A9BF),
                                    width: 1.2,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.white.withOpacity(0.35),
                                      blurRadius: 2,
                                      offset: const Offset(0, -1),
                                    ),
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.18),
                                      blurRadius: 6,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.sports_volleyball,
                                      size: 15,
                                      color: Color(0xFF42576B),
                                    ),
                                    const SizedBox(width: 6),
                                    Flexible(
                                      child: Text(
                                        position,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                          color: Color(0xFF2E4053),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (_weekEvents.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                _buildCompactWeekEventsPreview(),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _buildEmbeddedPerformanceCompactCard(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCompactWeekEventsPreview() {
    final nextEvent = _weekEvents.first;
    final eventDate = nextEvent['event_datetime'] as DateTime;
    final weekday = DateFormat('EEEE', 'pt_BR').format(eventDate).toUpperCase();
    final cleanWeekday = weekday.replaceAll('-FEIRA', '');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: const LinearGradient(
          colors: [
            Color(0xFF0E2440),
            Color(0xFF122B4A),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(
          color: const Color(0xFF2D4561),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.22),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              color: Colors.white.withOpacity(0.06),
              border: Border.all(color: Colors.white.withOpacity(0.12)),
            ),
            child: const Icon(
              Icons.calendar_today_outlined,
              size: 15,
              color: Colors.white70,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: RichText(
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              text: TextSpan(
                children: [
                  TextSpan(
                    text: '$cleanWeekday\n',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
                  TextSpan(
                    text:
                        '${DateFormat('dd/MM').format(eventDate)} • ${DateFormat('HH:mm').format(eventDate)} • ${(nextEvent['event_name'] ?? 'Evento').toString()}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      height: 1.2,
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

  Widget _buildEmbeddedPerformanceCompactCard() {
    final progress = _monthlyTrainingTotal > 0
        ? (_monthlyPresenceCount / _monthlyTrainingTotal).clamp(0.0, 1.0)
        : 0.0;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: const LinearGradient(
          colors: [Color(0xFF132743), Color(0xFF1B3154)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(
          color: olympusGold.withOpacity(0.55),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.18),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
          BoxShadow(
            color: olympusGold.withOpacity(0.08),
            blurRadius: 12,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Column(
        children: [
          Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.centerLeft,
            children: [
              Container(
                height: 8,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.05),
                  ),
                ),
              ),
              FractionallySizedBox(
                widthFactor: progress,
                child: Container(
                  height: 8,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    gradient: const LinearGradient(
                      colors: [Color(0xFF8AF26D), Color(0xFFF3D94F)],
                    ),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0xFF9AF07A),
                        blurRadius: 8,
                        spreadRadius: 0.2,
                      ),
                    ],
                  ),
                ),
              ),
              if (progress > 0)
                Positioned(
                  left: ((MediaQuery.of(context).size.width - 56) * progress)
                      .clamp(0.0, MediaQuery.of(context).size.width - 56),
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        colors: [Color(0xFFFFF27E), Color(0xFFDABF2B)],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFF3D94F).withOpacity(0.75),
                          blurRadius: 10,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(
                  '${_monthlyPresenceCount.toString().padLeft(2, '0')}/${_monthlyTrainingTotal.toString().padLeft(2, '0')} TREINOS',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
              Text(
                _getPerformanceLevel(),
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _buildMiniMetric(
                  icon: Icons.check_circle_outline,
                  label: 'Presenças',
                  helper: 'Taxa de presença',
                  value: '${_monthlyPresencePercent.toStringAsFixed(0)}%',
                  valueColor: const Color(0xFFFFF2A8),
                  accentColor: const Color(0xFFE7CC44),
                  chartType: _MiniChartType.line,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildMiniMetric(
                  icon: Icons.warning_amber_rounded,
                  label: 'Faltas',
                  helper: 'Faltas no mês',
                  value: _monthlyAbsenceCount.toString(),
                  valueColor: Colors.white,
                  accentColor: const Color(0xFFE15A5A),
                  chartType: _MiniChartType.barsRed,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildMiniMetric(
                  icon: Icons.bar_chart_rounded,
                  label: 'Volume de treino',
                  helper: 'Treinos do mês',
                  value: _monthlyTrainingTotal.toString(),
                  valueColor: const Color(0xFFFFF2A8),
                  accentColor: const Color(0xFF4FA3FF),
                  chartType: _MiniChartType.grid,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMiniMetric({
    required IconData icon,
    required String label,
    required String helper,
    required String value,
    required Color valueColor,
    required Color accentColor,
    required _MiniChartType chartType,
  }) {
    return Container(
      height: 92,
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        gradient: LinearGradient(
          colors: [
            const Color(0xFF0F2138),
            accentColor.withOpacity(0.10),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: accentColor.withOpacity(0.85), width: 1.1),
        boxShadow: [
          BoxShadow(
            color: accentColor.withOpacity(0.16),
            blurRadius: 10,
            spreadRadius: 0.5,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  color: accentColor.withOpacity(0.16),
                  border: Border.all(color: accentColor.withOpacity(0.7)),
                ),
                child: Icon(icon, size: 10, color: accentColor),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 8,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            helper,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white54,
              fontSize: 7,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              color: valueColor,
              fontSize: 22,
              fontWeight: FontWeight.w800,
              height: 1,
            ),
          ),
          const Spacer(),
          _buildMiniChart(chartType, accentColor),
        ],
      ),
    );
  }

  Widget _buildMiniChart(_MiniChartType type, Color accentColor) {
    switch (type) {
      case _MiniChartType.line:
        return CustomPaint(
          size: const Size(double.infinity, 18),
          painter: _MiniLinePainter(color: accentColor),
        );
      case _MiniChartType.barsRed:
        return Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: List.generate(8, (index) {
            final heights = [6.0, 10.0, 14.0, 7.0, 18.0, 12.0, 16.0, 9.0];
            return Expanded(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 1),
                height: heights[index],
                decoration: BoxDecoration(
                  color: accentColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            );
          }),
        );
      case _MiniChartType.grid:
        return Column(
          children: List.generate(3, (row) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Row(
                children: List.generate(8, (col) {
                  final active = (row + col) % 2 == 0 || col > 4;
                  return Expanded(
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 1),
                      height: 5,
                      decoration: BoxDecoration(
                        color: active
                            ? const Color(0xFFE1C84B)
                            : accentColor.withOpacity(0.22),
                        borderRadius: BorderRadius.circular(1.5),
                      ),
                    ),
                  );
                }),
              ),
            );
          }),
        );
    }
  }

  Widget _buildWeekEventsSectionCard() {
    if (_weekEvents.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: olympusGold.withOpacity(0.25)),
        boxShadow: [
          BoxShadow(
            color: olympusGold.withOpacity(0.12),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.calendar_month,
                color: olympusGold,
                size: 18,
              ),
              const SizedBox(width: 8),
              const Text(
                'Eventos da semana',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: olympusBlue,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ..._weekEvents.take(3).map((event) {
            final eventDate = event['event_datetime'] as DateTime;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: olympusGold.withOpacity(0.14),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${DateFormat('dd/MM').format(eventDate)} • ${DateFormat('HH:mm').format(eventDate)}',
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: olympusBlue,
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
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF2C3E5A),
                      ),
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
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

  Widget _buildPresenceSummaryCard() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: olympusBlue.withOpacity(0.12)),
        boxShadow: [
          BoxShadow(
            color: olympusBlue.withOpacity(0.08),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: _buildPresenceMetric(
              icon: Icons.check_circle,
              label: 'Confirmado',
              value: _confirmedPresenceCount,
              color: Colors.green,
            ),
          ),
          Container(
            width: 1,
            height: 42,
            color: Colors.grey.withOpacity(0.18),
          ),
          Expanded(
            child: _buildPresenceMetric(
              icon: Icons.schedule,
              label: 'Pendente',
              value: _pendingCount,
              color: Colors.orange,
            ),
          ),
          Container(
            width: 1,
            height: 42,
            color: Colors.grey.withOpacity(0.18),
          ),
          Expanded(
            child: _buildPresenceMetric(
              icon: Icons.cancel,
              label: 'Recusado',
              value: _rejectedPresenceCount,
              color: Colors.red,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPresenceMetric({
    required IconData icon,
    required String label,
    required int value,
    required Color color,
  }) {
    return Column(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(height: 6),
        Text(
          value.toString(),
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: Colors.grey[700],
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

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
                  Icon(
                    Icons.arrow_forward_ios,
                    color: color.withOpacity(0.5),
                    size: 18,
                  ),
                ],
              ),
            ),
            if (badgeCount != null && badgeCount > 0)
              Positioned(
                right: 12,
                top: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
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

  Widget _buildFinancialAlertCard() {
    if (_overdueFinancialCount == 0) return const SizedBox.shrink();

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
            _buildAthleteInfoCard(),
            _buildFinancialAlertCard(),
            _buildPresenceSummaryCard(),
            _buildWeekEventsSectionCard(),
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
            _buildDashboardCard(
              icon: Icons.chat,
              title: 'Chat do Time',
              subtitle: 'Converse com sua equipe',
              color: olympusLightBlue,
              onTap: _navigateToChat,
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}

enum _MiniChartType {
  line,
  barsRed,
  grid,
}

class _MiniLinePainter extends CustomPainter {
  final Color color;
  _MiniLinePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final glowPaint = Paint()
      ..color = color.withOpacity(0.35)
      ..strokeWidth = 5
      ..style = PaintingStyle.stroke
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);

    final dotPaint = Paint()..color = color;

    final path = Path();
    final points = [
      Offset(0, size.height - 10),
      Offset(size.width * 0.20, size.height - 11),
      Offset(size.width * 0.40, size.height - 8),
      Offset(size.width * 0.60, size.height - 12),
      Offset(size.width * 0.80, size.height - 4),
      Offset(size.width, size.height - 7),
    ];

    path.moveTo(points.first.dx, points.first.dy);
    for (final point in points.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }

    canvas.drawPath(path, glowPaint);
    canvas.drawPath(path, linePaint);
    canvas.drawCircle(points.last, 2.8, dotPaint);
  }

  @override
  bool shouldRepaint(covariant _MiniLinePainter oldDelegate) {
    return oldDelegate.color != color;
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
      await supabase.storage.from('avatars').uploadBinary(fileName, fileBytes,
          fileOptions: const FileOptions(upsert: true));
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
