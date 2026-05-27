import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AthleteStatisticsPage extends StatefulWidget {
  const AthleteStatisticsPage({super.key});

  static const String heroTag = AthleteStatisticsDetailPage.heroTag;

  static Route<void> route() {
    return PageRouteBuilder<void>(
      transitionDuration: const Duration(milliseconds: 420),
      reverseTransitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (context, animation, secondaryAnimation) {
        return const AthleteStatisticsPage();
      },
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        final curvedAnimation = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );

        final offsetAnimation = Tween<Offset>(
          begin: const Offset(0.035, 0.02),
          end: Offset.zero,
        ).animate(curvedAnimation);

        return FadeTransition(
          opacity: curvedAnimation,
          child: SlideTransition(
            position: offsetAnimation,
            child: child,
          ),
        );
      },
    );
  }

  @override
  State<AthleteStatisticsPage> createState() => _AthleteStatisticsHubState();
}

class _AthleteStatisticsHubState extends State<AthleteStatisticsPage> {
  final SupabaseClient _supabase = Supabase.instance.client;

  static const Color olympusBlue = Color(0xFF1E3A5F);
  static const Color olympusGold = Color(0xFFD4AF37);
  static const Color olympusLightBlue = Color(0xFF2C5F8D);
  static const Color olympusBg = Color(0xFFF4F7FB);
  static const Color olympusSuccess = Color(0xFF16A34A);
  static const Color olympusDanger = Color(0xFFDC2626);
  static const Color olympusMuted = Color(0xFF53657B);
  static const Color olympusBorder = Color(0xFFE4EDF5);
  static const String _eventsEmbedFk = 'convocations_event_id_fkey';
  static final DateTime _statsRuleStartDate = DateTime(2026, 5, 1);

  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _profile;
  List<Map<String, dynamic>> _convocations = [];
  List<Map<String, dynamic>> _checkins = [];
  Map<String, Map<String, dynamic>> _eventsById = {};
  int? _selectedTrainingMonth;
  int? _selectedChampionshipMonth;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final user = _supabase.auth.currentUser;
      if (user == null) {
        throw Exception('Usuário não autenticado.');
      }

      final profileRows = await _supabase
          .from('profiles')
          .select('id, full_name, avatar_url, gender, user_type')
          .eq('id', user.id)
          .limit(1);

      final convocationRows = await _supabase
          .from('convocations')
          .select(
            'id, user_id, event_id, status, justification, created_at, '
            'events!$_eventsEmbedFk(id, event_name, event_type, gender, '
            'event_date, event_time, championship_name)',
          )
          .eq('user_id', user.id);

      final checkinRows = await _supabase
          .from('checkins')
          .select(
            'id, user_id, event_id, check_in_status, created_at, checked_in_at, '
            'check_in_latitude, check_in_longitude, latitude, longitude',
          )
          .eq('user_id', user.id);

      final profiles = List<Map<String, dynamic>>.from(profileRows as List);
      final convocations = List<Map<String, dynamic>>.from(
        convocationRows as List,
      );
      final checkins = List<Map<String, dynamic>>.from(checkinRows as List);
      final eventsById = <String, Map<String, dynamic>>{};

      for (final convocation in convocations) {
        final eventId = (convocation['event_id'] ?? '').toString();
        final event = convocation['events'];
        if (eventId.isEmpty || event is! Map) continue;
        eventsById[eventId] = Map<String, dynamic>.from(event);
      }

      final missingEventIds = checkins
          .map((row) => (row['event_id'] ?? '').toString())
          .where((id) => id.isNotEmpty && !eventsById.containsKey(id))
          .toSet()
          .toList();

      if (missingEventIds.isNotEmpty) {
        try {
          final eventRows = await _supabase
              .from('events')
              .select(
                'id, event_name, event_type, gender, event_date, event_time, championship_name',
              )
              .inFilter('id', missingEventIds);

          for (final row in eventRows) {
            final event = Map<String, dynamic>.from(row as Map);
            final eventId = (event['id'] ?? '').toString();
            if (eventId.isNotEmpty) eventsById[eventId] = event;
          }
        } catch (_) {
          // Mantém apenas os eventos visíveis via convocação.
        }
      }

      if (!mounted) return;
      setState(() {
        _profile = profiles.isNotEmpty ? profiles.first : null;
        _convocations = convocations;
        _checkins = checkins;
        _eventsById = eventsById;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Erro ao carregar estatísticas: $e';
        _loading = false;
      });
    }
  }

  void _goBackToDashboard() {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
      return;
    }

    Navigator.of(context).pushNamedAndRemoveUntil(
      '/athlete-dashboard',
      (route) => false,
    );
  }

  void _openDetail(String mode) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AthleteStatisticsDetailPage(initialStatsMode: mode),
      ),
    );
  }

  DateTime? _parseDate(dynamic value) {
    final raw = (value ?? '').toString().trim();
    if (raw.isEmpty) return null;

    final iso = DateTime.tryParse(raw);
    if (iso != null) return iso.toLocal();

    final parts = raw.split('/');
    if (parts.length == 3) {
      final day = int.tryParse(parts[0]);
      final month = int.tryParse(parts[1]);
      final year = int.tryParse(parts[2]);
      if (day != null && month != null && year != null) {
        return DateTime(year, month, day);
      }
    }

    return null;
  }

  DateTime? _eventDateTime(Map<String, dynamic> event) {
    final eventDate = (event['event_date'] ?? '').toString().trim();
    final eventTime = (event['event_time'] ?? '').toString().trim();
    if (eventDate.isEmpty) return null;

    try {
      if (eventDate.contains('/')) {
        final dateParts = eventDate.split('/');
        final timeParts = eventTime.isEmpty ? ['0', '0'] : eventTime.split(':');
        if (dateParts.length == 3 && timeParts.length >= 2) {
          return DateTime(
            int.parse(dateParts[2]),
            int.parse(dateParts[1]),
            int.parse(dateParts[0]),
            int.parse(timeParts[0]),
            int.parse(timeParts[1]),
          );
        }
      }

      final iso = DateTime.tryParse(eventDate);
      if (iso == null) return null;
      if (eventTime.isEmpty) return iso.toLocal();

      final timeParts = eventTime.split(':');
      if (timeParts.length < 2) return iso.toLocal();

      return DateTime(
        iso.year,
        iso.month,
        iso.day,
        int.parse(timeParts[0]),
        int.parse(timeParts[1]),
      );
    } catch (_) {
      return null;
    }
  }

  String _normalizeEventType(dynamic value) {
    final raw = (value ?? '').toString().trim().toLowerCase();
    if (raw.contains('treino')) return 'treino';
    if (raw.contains('campeonato')) return 'campeonato';
    if (raw.contains('liga')) return 'liga';
    return raw;
  }

  bool _isOnOrAfterStatsRuleStart(DateTime? date) {
    if (date == null) return false;
    final normalized = DateTime(date.year, date.month, date.day);
    return !normalized.isBefore(_statsRuleStartDate);
  }

  bool _isTrainingCheckinDone(Map<String, dynamic> row) {
    final raw = (row['check_in_status'] ?? '').toString().trim().toLowerCase();

    if (raw == 'cancelado' ||
        raw == 'canceled' ||
        raw == 'cancelled' ||
        raw == 'erro' ||
        raw == 'error' ||
        raw == 'failed' ||
        raw == 'falhou') {
      return false;
    }

    if (raw.isEmpty) return true;

    return raw == 'realizado' ||
        raw == 'realizado com sucesso' ||
        raw == 'checked_in' ||
        raw == 'checkin_realizado' ||
        raw == 'check-in realizado' ||
        raw == 'presente' ||
        raw == 'presence' ||
        raw == 'ok' ||
        raw == 'success' ||
        raw == 'completed' ||
        raw == 'done' ||
        raw == 'manual' ||
        raw == 'late' ||
        raw == 'atrasado' ||
        raw == 'checkin_atrasado';
  }

  bool _isPlayedChampionshipCheckin(Map<String, dynamic> row) {
    final eventId = (row['event_id'] ?? '').toString().trim();
    if (eventId.isEmpty) return false;

    final raw = (row['check_in_status'] ?? '').toString().trim().toLowerCase();

    if (raw == 'pending' ||
        raw == 'pendente' ||
        raw == 'cancelado' ||
        raw == 'canceled' ||
        raw == 'cancelled' ||
        raw == 'erro' ||
        raw == 'error' ||
        raw == 'failed' ||
        raw == 'falhou') {
      return false;
    }

    final statusDone = raw == 'realizado' ||
        raw == 'realizado com sucesso' ||
        raw == 'checked_in' ||
        raw == 'checkin_realizado' ||
        raw == 'check-in realizado' ||
        raw == 'presente' ||
        raw == 'presence' ||
        raw == 'ok' ||
        raw == 'success' ||
        raw == 'completed' ||
        raw == 'done' ||
        raw == 'manual' ||
        raw == 'late' ||
        raw == 'atrasado' ||
        raw == 'checkin_atrasado';

    final checkedInAt = (row['checked_in_at'] ?? '').toString().trim();
    final hasCheckedInAt =
        checkedInAt.isNotEmpty && checkedInAt.toLowerCase() != 'null';
    final hasLocation = row['check_in_latitude'] != null ||
        row['check_in_longitude'] != null ||
        row['latitude'] != null ||
        row['longitude'] != null;

    return statusDone || hasCheckedInAt || hasLocation;
  }

  bool _isExplicitAbsenceStatus(dynamic value) {
    final raw = (value ?? '').toString().trim().toLowerCase();

    return raw == 'ausente' ||
        raw == 'absence' ||
        raw == 'absent' ||
        raw == 'faltou' ||
        raw == 'falta' ||
        raw == 'no_show' ||
        raw == 'nao_compareceu' ||
        raw == 'não_compareceu' ||
        raw == 'nao compareceu' ||
        raw == 'não compareceu';
  }

  Set<String> _explicitTrainingAbsenceEventIds() {
    return _checkins
        .where((row) => _isExplicitAbsenceStatus(row['check_in_status']))
        .map((row) => (row['event_id'] ?? '').toString())
        .where((id) => id.isNotEmpty)
        .toSet();
  }

  Set<String> _doneTrainingEventIds() {
    return _checkins
        .where(_isTrainingCheckinDone)
        .map((row) => (row['event_id'] ?? '').toString())
        .where((id) => id.isNotEmpty)
        .toSet();
  }

  Set<String> _playedChampionshipEventIds() {
    return _checkins
        .where(_isPlayedChampionshipCheckin)
        .map((row) => (row['event_id'] ?? '').toString())
        .where((id) => id.isNotEmpty)
        .toSet();
  }

  List<_MonthlyPresenceAbsence> _annualTrainingPresence() {
    final year = DateTime.now().year;
    final doneEventIds = _doneTrainingEventIds();
    final explicitAbsenceEventIds = _explicitTrainingAbsenceEventIds();

    final monthlyPresenceEventIds = <int, Set<String>>{
      for (int month = 1; month <= 12; month++) month: <String>{},
    };
    final monthlyAbsentEventIds = <int, Set<String>>{
      for (int month = 1; month <= 12; month++) month: <String>{},
    };

    for (final convocation in _convocations) {
      final eventId = (convocation['event_id'] ?? '').toString();
      if (eventId.isEmpty) continue;

      final event = _eventsById[eventId];
      if (event == null) continue;
      if (_normalizeEventType(event['event_type']) != 'treino') continue;

      final eventDate = _eventDateTime(event);
      if (eventDate == null || eventDate.year != year) continue;
      if (!_isOnOrAfterStatsRuleStart(eventDate)) continue;

      if (doneEventIds.contains(eventId)) {
        monthlyPresenceEventIds[eventDate.month]!.add(eventId);
        monthlyAbsentEventIds[eventDate.month]!.remove(eventId);
        continue;
      }

      // Não inferir falta automaticamente por evento vencido/pendente.
      // Falta anual só aparece se houver registro explícito de ausência.
      if (explicitAbsenceEventIds.contains(eventId)) {
        monthlyAbsentEventIds[eventDate.month]!.add(eventId);
      }
    }

    return List.generate(12, (index) {
      final month = index + 1;
      return _MonthlyPresenceAbsence(
        month: month,
        presences: monthlyPresenceEventIds[month]!.length,
        absences: monthlyAbsentEventIds[month]!.length,
      );
    });
  }

  List<_MonthlyPresenceAbsence> _annualChampionshipPresence() {
    final year = DateTime.now().year;
    final playedEventIds = _playedChampionshipEventIds();
    final monthlyPresenceEventIds = <int, Set<String>>{
      for (int month = 1; month <= 12; month++) month: <String>{},
    };

    for (final eventId in playedEventIds) {
      final event = _eventsById[eventId];
      if (event == null) continue;

      final eventType = _normalizeEventType(event['event_type']);
      if (eventType != 'campeonato' && eventType != 'liga') continue;

      final relatedCheckin = _checkins.firstWhere(
        (row) => (row['event_id'] ?? '').toString() == eventId,
        orElse: () => const <String, dynamic>{},
      );

      final eventDate =
          _eventDateTime(event) ?? _parseDate(relatedCheckin['created_at']);
      if (eventDate == null || eventDate.year != year) continue;
      if (!_isOnOrAfterStatsRuleStart(eventDate)) continue;

      monthlyPresenceEventIds[eventDate.month]!.add(eventId);
    }

    return List.generate(12, (index) {
      final month = index + 1;
      return _MonthlyPresenceAbsence(
        month: month,
        presences: monthlyPresenceEventIds[month]!.length,
        absences: 0,
      );
    });
  }

  Widget _background() {
    return Stack(
      children: [
        Positioned.fill(
          child: Image.asset(
            'assets/images/monte_olimpo_v2.png',
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) {
              return Container(color: const Color(0xFF102845));
            },
          ),
        ),
        Positioned.fill(
          child: Container(color: Colors.black.withOpacity(0.38)),
        ),
        Positioned.fill(
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  olympusBlue.withOpacity(0.52),
                  Colors.black.withOpacity(0.18),
                  Colors.black.withOpacity(0.62),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _header() {
    final fullName = (_profile?['full_name'] ??
            _supabase.auth.currentUser?.userMetadata?['full_name'] ??
            'Atleta')
        .toString();
    final avatarUrl = (_profile?['avatar_url'] ?? '').toString().trim();

    return Container(
      margin: EdgeInsets.fromLTRB(
        _StatsResponsive.isDesktop(context)
            ? 48
            : (_StatsResponsive.isTablet(context) ? 28 : 16),
        _StatsResponsive.space(context, 14),
        _StatsResponsive.isDesktop(context)
            ? 48
            : (_StatsResponsive.isTablet(context) ? 28 : 16),
        _StatsResponsive.space(context, 12),
      ),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        color: const Color(0xFF123861).withOpacity(0.92),
        border: Border.all(color: Colors.white.withOpacity(0.16)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.18),
            blurRadius: 16,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: Row(
        children: [
          Hero(
            tag: AthleteStatisticsPage.heroTag,
            child: CircleAvatar(
              radius: 31,
              backgroundColor: olympusGold,
              backgroundImage:
                  avatarUrl.isNotEmpty ? NetworkImage(avatarUrl) : null,
              child: avatarUrl.isEmpty
                  ? Text(
                      fullName.isNotEmpty ? fullName[0].toUpperCase() : '?',
                      style: const TextStyle(
                        color: olympusBlue,
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                      ),
                    )
                  : null,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  fullName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: _StatsResponsive.font(context, 20),
                    fontWeight: FontWeight.w900,
                    height: 1.08,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  'Resumo de presença e desempenho',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.78),
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _premiumSectionButton({
    required String label,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Container(
      width: double.infinity,
      margin: EdgeInsets.fromLTRB(
        _StatsResponsive.isDesktop(context)
            ? 48
            : (_StatsResponsive.isTablet(context) ? 28 : 16),
        0,
        _StatsResponsive.isDesktop(context)
            ? 48
            : (_StatsResponsive.isTablet(context) ? 28 : 16),
        _StatsResponsive.space(context, 10),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.94),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: color.withOpacity(0.28)),
            ),
            child: Row(
              children: [
                Icon(icon, color: color, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: olympusBlue,
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                Icon(
                  Icons.arrow_forward_ios_rounded,
                  color: color,
                  size: 14,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _sectionTitlePremium({
    required String eyebrow,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      width: double.infinity,
      margin: EdgeInsets.fromLTRB(
        _StatsResponsive.isDesktop(context)
            ? 48
            : (_StatsResponsive.isTablet(context) ? 28 : 16),
        _StatsResponsive.space(context, 4),
        _StatsResponsive.isDesktop(context)
            ? 48
            : (_StatsResponsive.isTablet(context) ? 28 : 16),
        _StatsResponsive.space(context, 8),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: color.withOpacity(0.16),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: color.withOpacity(0.24)),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          Text(
            eyebrow,
            style: TextStyle(
              color: Colors.white.withOpacity(0.64),
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  String _fullMonthLabel(int month) {
    const labels = [
      '',
      'Janeiro',
      'Fevereiro',
      'Março',
      'Abril',
      'Maio',
      'Junho',
      'Julho',
      'Agosto',
      'Setembro',
      'Outubro',
      'Novembro',
      'Dezembro',
    ];
    if (month < 1 || month > 12) return '';
    return labels[month];
  }

  Widget _annualChartCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required List<_MonthlyPresenceAbsence> data,
    required int? selectedMonth,
    required ValueChanged<int> onMonthSelected,
    required Alignment athleteImageAlignment,
    bool showAbsences = true,
  }) {
    final totalPresences =
        data.fold<int>(0, (sum, item) => sum + item.presences);
    final totalAbsences = data.fold<int>(0, (sum, item) => sum + item.absences);
    final hasData = totalPresences > 0 || totalAbsences > 0;
    final avatarUrl = (_profile?['avatar_url'] ?? '').toString().trim();

    final selectedData = selectedMonth == null
        ? null
        : data.firstWhere(
            (item) => item.month == selectedMonth,
            orElse: () => _MonthlyPresenceAbsence(
              month: selectedMonth,
              presences: 0,
              absences: 0,
            ),
          );

    final horizontalMargin = _StatsResponsive.isDesktop(context)
        ? 48.0
        : (_StatsResponsive.isTablet(context) ? 28.0 : 16.0);

    return Container(
      width: double.infinity,
      margin: EdgeInsets.fromLTRB(
        horizontalMargin,
        0,
        horizontalMargin,
        _StatsResponsive.space(context, 12),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(26),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(26),
              color: const Color(0xFF0D223B).withOpacity(0.86),
              border:
                  Border.all(color: Colors.white.withOpacity(0.16), width: 1),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.16),
                  blurRadius: 16,
                  offset: const Offset(0, 7),
                ),
              ],
            ),
            child: Stack(
              children: [
                if (avatarUrl.isNotEmpty)
                  Positioned.fill(
                    child: Image.network(
                      avatarUrl,
                      fit: BoxFit.cover,
                      alignment: athleteImageAlignment,
                      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                    ),
                  ),
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          const Color(0xFF06172B).withOpacity(0.88),
                          olympusBlue.withOpacity(0.68),
                          const Color(0xFF071A30).withOpacity(0.90),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 2.6, sigmaY: 2.6),
                    child: Container(color: Colors.transparent),
                  ),
                ),
                Positioned(
                  top: -38,
                  right: athleteImageAlignment == Alignment.centerRight
                      ? null
                      : -30,
                  left: athleteImageAlignment == Alignment.centerRight
                      ? -30
                      : null,
                  child: Container(
                    width: 128,
                    height: 128,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withOpacity(0.025),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
                              gradient: LinearGradient(
                                colors: [
                                  olympusGold.withOpacity(0.95),
                                  const Color(0xFFF8E08E),
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: olympusGold.withOpacity(0.28),
                                  blurRadius: 14,
                                  spreadRadius: 1,
                                ),
                              ],
                            ),
                            child: Icon(icon, color: olympusBlue, size: 24),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  subtitle,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.76),
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final narrow = constraints.maxWidth < 390;
                          final cards = <Widget>[
                            _summaryPill(
                              label: 'Presencas',
                              value: totalPresences,
                              color: olympusSuccess,
                              icon: Icons.check_circle_rounded,
                            ),
                            if (showAbsences)
                              _summaryPill(
                                label: 'Faltas',
                                value: totalAbsences,
                                color: olympusDanger,
                                icon: Icons.cancel_rounded,
                              ),
                          ];

                          if (cards.length == 1) {
                            return SizedBox(
                              width: double.infinity,
                              child: cards.first,
                            );
                          }

                          if (narrow) {
                            return Column(
                              children: [
                                SizedBox(
                                    width: double.infinity, child: cards[0]),
                                const SizedBox(height: 10),
                                SizedBox(
                                    width: double.infinity, child: cards[1]),
                              ],
                            );
                          }

                          return Row(
                            children: [
                              Expanded(child: cards[0]),
                              const SizedBox(width: 10),
                              Expanded(child: cards[1]),
                            ],
                          );
                        },
                      ),
                      if (selectedData != null) ...[
                        const SizedBox(height: 12),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.13),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: olympusGold.withOpacity(0.34),
                            ),
                          ),
                          child: Text(
                            showAbsences
                                ? '${_fullMonthLabel(selectedData.month)}: ${selectedData.presences} presenca(s) / ${selectedData.absences} falta(s)'
                                : '${_fullMonthLabel(selectedData.month)}: ${selectedData.presences} presenca(s)',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 14),
                      Container(
                        height: _StatsResponsive.annualChartHeight(context),
                        width: double.infinity,
                        padding: const EdgeInsets.fromLTRB(10, 12, 10, 8),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(20),
                          color: Colors.white.withOpacity(0.08),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.12),
                          ),
                        ),
                        child: hasData
                            ? LayoutBuilder(
                                builder: (context, constraints) {
                                  return GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onTapDown: (details) {
                                      final localX = details.localPosition.dx;
                                      final left = constraints.maxWidth < 360
                                          ? 30.0
                                          : 34.0;
                                      const right = 12.0;
                                      final chartWidth =
                                          constraints.maxWidth - left - right;
                                      if (chartWidth <= 0) return;

                                      final normalized =
                                          ((localX - left) / chartWidth)
                                              .clamp(0.0, 1.0);
                                      final month =
                                          (normalized * 11).round() + 1;
                                      onMonthSelected(month.clamp(1, 12));
                                    },
                                    child: CustomPaint(
                                      painter: _AnnualPresenceAbsencePainter(
                                        data: data,
                                        presenceColor: olympusSuccess,
                                        absenceColor: olympusDanger,
                                        gridColor:
                                            Colors.white.withOpacity(0.16),
                                        labelColor:
                                            Colors.white.withOpacity(0.74),
                                        selectedMonth: selectedMonth,
                                        selectedColor: olympusGold,
                                        showAbsences: showAbsences,
                                      ),
                                      child: const SizedBox.expand(),
                                    ),
                                  );
                                },
                              )
                            : Center(
                                child: Text(
                                  'Ainda nao ha dados suficientes para este grafico.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.76),
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    height: 1.35,
                                  ),
                                ),
                              ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          _legendDot(label: 'Presencas', color: olympusSuccess),
                          if (showAbsences) ...[
                            const SizedBox(width: 14),
                            _legendDot(label: 'Faltas', color: olympusDanger),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _summaryPill({
    required String label,
    required int value,
    required Color color,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: color.withOpacity(0.13),
        border: Border.all(color: color.withOpacity(0.34)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white.withOpacity(0.76),
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Text(
            value.toString(),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _legendDot({
    required String label,
    required Color color,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: color.withOpacity(0.55),
                blurRadius: 8,
              ),
            ],
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withOpacity(0.78),
            fontSize: 12,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: olympusBg,
      appBar: AppBar(
        title: const Text('Estatísticas do Atleta'),
        backgroundColor: olympusBlue,
        foregroundColor: Colors.white,
        leading: IconButton(
          tooltip: 'Voltar para o Dashboard',
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: _goBackToDashboard,
        ),
        actions: [
          IconButton(
            tooltip: 'Atualizar',
            onPressed: _loadData,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragEnd: (details) {
          final velocity = details.primaryVelocity ?? 0;
          if (velocity > 320) _goBackToDashboard();
        },
        child: Stack(
          children: [
            Positioned.fill(child: _background()),
            if (_loading)
              const Center(
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            else if (_error != null)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(22),
                  child: Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              )
            else
              RefreshIndicator(
                onRefresh: _loadData,
                child: ListView(
                  physics: const BouncingScrollPhysics(
                    parent: AlwaysScrollableScrollPhysics(),
                  ),
                  padding: const EdgeInsets.only(bottom: 28),
                  children: [
                    _header(),
                    _sectionTitlePremium(
                      eyebrow: 'Visão anual',
                      title: 'Treinos',
                      subtitle: 'Presença e faltas consolidadas no ano',
                      icon: Icons.fitness_center_rounded,
                      color: olympusLightBlue,
                    ),
                    _premiumSectionButton(
                      label: 'Ver detalhes de treinos',
                      subtitle: '',
                      icon: Icons.insights_rounded,
                      color: olympusLightBlue,
                      onTap: () => _openDetail('treino'),
                    ),
                    _annualChartCard(
                      title: 'Presença anual de treinos',
                      subtitle: 'Consolidado de treinos convocados',
                      icon: Icons.show_chart_rounded,
                      data: _annualTrainingPresence(),
                      selectedMonth: _selectedTrainingMonth,
                      athleteImageAlignment: Alignment.centerLeft,
                      onMonthSelected: (month) {
                        setState(() => _selectedTrainingMonth = month);
                      },
                    ),
                    _sectionTitlePremium(
                      eyebrow: 'Competições',
                      title: 'Campeonatos e ligas',
                      subtitle: 'Participações confirmadas por check-in',
                      icon: Icons.emoji_events_rounded,
                      color: olympusGold,
                    ),
                    _premiumSectionButton(
                      label: 'Ver detalhes de campeonatos',
                      subtitle: '',
                      icon: Icons.workspace_premium_rounded,
                      color: olympusGold,
                      onTap: () => _openDetail('campeonato'),
                    ),
                    _annualChartCard(
                      title: 'Presenças de campeonatos',
                      subtitle: 'Consolidado de todos os campeonatos e ligas',
                      icon: Icons.emoji_events_rounded,
                      data: _annualChampionshipPresence(),
                      selectedMonth: _selectedChampionshipMonth,
                      athleteImageAlignment: Alignment.centerRight,
                      onMonthSelected: (month) {
                        setState(() => _selectedChampionshipMonth = month);
                      },
                      showAbsences: false,
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _StatsResponsive {
  static double width(BuildContext context) =>
      MediaQuery.of(context).size.width;
  static double height(BuildContext context) =>
      MediaQuery.of(context).size.height;

  static bool isSmall(BuildContext context) => width(context) < 360;
  static bool isMobile(BuildContext context) => width(context) < 600;
  static bool isTablet(BuildContext context) =>
      width(context) >= 600 && width(context) < 1024;
  static bool isDesktop(BuildContext context) => width(context) >= 1024;

  static double font(BuildContext context, double base) {
    final w = width(context);
    if (w < 360) return base * 0.88;
    if (w < 600) return base;
    if (w < 1024) return base * 1.08;
    return base * 1.16;
  }

  static double space(BuildContext context, double base) {
    if (isSmall(context)) return base * 0.78;
    if (isTablet(context)) return base * 1.08;
    if (isDesktop(context)) return base * 1.14;
    return base;
  }

  static EdgeInsets pageMargin(BuildContext context) {
    final w = width(context);
    if (w >= 1024) return const EdgeInsets.symmetric(horizontal: 48);
    if (w >= 720) return const EdgeInsets.symmetric(horizontal: 28);
    return EdgeInsets.zero;
  }

  static int metricsCrossAxisCount(
      BuildContext context, double availableWidth) {
    final width = availableWidth.isFinite
        ? availableWidth
        : _StatsResponsive.width(context);
    if (width < 360) return 1;
    if (width < 560) return 2;
    if (width < 920) return 3;
    return 4;
  }

  static double metricsAspectRatio(
      BuildContext context, double availableWidth) {
    final width = availableWidth.isFinite
        ? availableWidth
        : _StatsResponsive.width(context);
    if (width < 360) return 2.35;
    if (width < 430) return 1.12;
    if (width < 560) return 1.22;
    if (width < 920) return 1.26;
    return 1.34;
  }

  static double annualChartHeight(BuildContext context) {
    final h = height(context);
    final w = width(context);
    if (w < 360) return (h * 0.30).clamp(220.0, 280.0);
    if (w < 600) return (h * 0.29).clamp(228.0, 300.0);
    if (w < 1024) return (h * 0.32).clamp(260.0, 340.0);
    return (h * 0.34).clamp(290.0, 380.0);
  }
}

class AthleteStatisticsDetailPage extends StatefulWidget {
  const AthleteStatisticsDetailPage({
    super.key,
    this.initialStatsMode = 'treino',
  });

  final String initialStatsMode;

  static const String heroTag = 'athlete-statistics-hero';

  static Route<void> route() {
    return PageRouteBuilder<void>(
      transitionDuration: const Duration(milliseconds: 420),
      reverseTransitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (context, animation, secondaryAnimation) {
        return const AthleteStatisticsDetailPage();
      },
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        final curvedAnimation = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );

        final offsetAnimation = Tween<Offset>(
          begin: const Offset(0.035, 0.02),
          end: Offset.zero,
        ).animate(curvedAnimation);

        return FadeTransition(
          opacity: curvedAnimation,
          child: SlideTransition(
            position: offsetAnimation,
            child: child,
          ),
        );
      },
    );
  }

  @override
  State<AthleteStatisticsDetailPage> createState() =>
      _AthleteStatisticsDetailPageState();
}

class _AthleteStatisticsDetailPageState
    extends State<AthleteStatisticsDetailPage> {
  final SupabaseClient _supabase = Supabase.instance.client;

  static const Color olympusBlue = Color(0xFF1E3A5F);
  static const Color olympusGold = Color(0xFFD4AF37);
  static const Color olympusLightBlue = Color(0xFF2C5F8D);
  static const Color olympusBg = Color(0xFFF4F7FB);
  static const Color olympusSuccess = Color(0xFF16A34A);
  static const Color olympusWarning = Color(0xFFF59E0B);
  static const Color olympusDanger = Color(0xFFDC2626);
  static const Color olympusPurple = Color(0xFF7C3AED);
  static const Color olympusMuted = Color(0xFF53657B);
  static const Color olympusBorder = Color(0xFFE4EDF5);
  static const String _eventsEmbedFk = 'convocations_event_id_fkey';

  bool _loading = true;
  String? _error;

  Map<String, dynamic>? _profile;
  List<Map<String, dynamic>> _evaluations = [];
  List<Map<String, dynamic>> _messages = [];
  List<Map<String, dynamic>> _checkins = [];
  List<Map<String, dynamic>> _convocations = [];
  List<Map<String, dynamic>> _trainingPlanBlocks = [];
  List<Map<String, dynamic>> _matchScouts = [];
  List<Map<String, dynamic>> _matchScoutActionDetails = [];

  String _period = 'mes';
  late String _statsMode;
  String? _selectedChampionshipName;
  int? _selectedAnnualMonth;
  String? _selectedChampionshipGameId;

  final ScrollController _scrollController = ScrollController();
  double _scrollOffset = 0;

  @override
  void initState() {
    super.initState();
    _statsMode =
        widget.initialStatsMode == 'campeonato' ? 'campeonato' : 'treino';
    _scrollController.addListener(_handleScroll);
    _loadData();
  }

  void _handleScroll() {
    if (!_scrollController.hasClients) return;

    final nextOffset = _scrollController.offset;
    if ((nextOffset - _scrollOffset).abs() < 1.5) return;

    if (!mounted) return;
    setState(() {
      _scrollOffset = nextOffset;
    });
  }

  @override
  void dispose() {
    _scrollController.removeListener(_handleScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _goBackToDashboard() {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
      return;
    }

    Navigator.of(context).pushNamedAndRemoveUntil(
      '/athlete-dashboard',
      (route) => false,
    );
  }

  static final DateTime _statsRuleStartDate = DateTime(2026, 5, 1);

  DateTime? _periodStart() {
    final now = DateTime.now();

    DateTime? start;
    switch (_period) {
      case 'semana':
        start = DateTime(now.year, now.month, now.day)
            .subtract(const Duration(days: 7));
        break;
      case 'mes':
        start = DateTime(now.year, now.month, 1);
        break;
      case 'geral':
        start = null;
        break;
      default:
        start = DateTime(now.year, now.month, 1);
    }

    if (start == null || start.isBefore(_statsRuleStartDate)) {
      return _statsRuleStartDate;
    }

    return start;
  }

  bool _isOnOrAfterStatsRuleStart(DateTime? date) {
    if (date == null) return false;
    final normalized = DateTime(date.year, date.month, date.day);
    return !normalized.isBefore(_statsRuleStartDate);
  }

  String _periodRuleLabel() {
    final start = _periodStart();
    if (start == null) return 'Desde 01/05/2026';

    return 'Desde ${start.day.toString().padLeft(2, '0')}/${start.month.toString().padLeft(2, '0')}/${start.year}';
  }

  bool _isPendingTrainingStillActionable(Map<String, dynamic> row) {
    final eventDateTime = _eventDateTime(row);
    if (eventDateTime == null) return false;

    final now = DateTime.now();
    if (!eventDateTime.isAfter(now)) return false;

    final type = _eventTypeForRow(row);
    int horasLimite;

    switch (type) {
      case 'treino':
        horasLimite = 0;
        break;
      case 'amistoso':
        horasLimite = 12;
        break;
      case 'campeonato':
      case 'liga':
        horasLimite = 48;
        break;
      default:
        horasLimite = 3;
    }

    return eventDateTime.difference(now).inMinutes >= (horasLimite * 60);
  }

  String _periodLabel() {
    switch (_period) {
      case 'semana':
        return 'Últimos 7 dias';
      case 'mes':
        return 'Mês atual';
      case 'geral':
        return 'Geral';
      default:
        return 'Mês atual';
    }
  }

  DateTime? _parseDate(dynamic value) {
    final raw = (value ?? '').toString().trim();
    if (raw.isEmpty) return null;

    final iso = DateTime.tryParse(raw);
    if (iso != null) return iso.toLocal();

    final parts = raw.split('/');
    if (parts.length == 3) {
      final day = int.tryParse(parts[0]);
      final month = int.tryParse(parts[1]);
      final year = int.tryParse(parts[2]);

      if (day != null && month != null && year != null) {
        return DateTime(year, month, day);
      }
    }

    return null;
  }

  String _normalizeGender(dynamic value) {
    final raw = (value ?? '').toString().trim().toLowerCase();

    if (raw == 'f' ||
        raw == 'female' ||
        raw == 'feminino' ||
        raw.contains('feminino')) {
      return 'feminino';
    }

    if (raw == 'm' ||
        raw == 'male' ||
        raw == 'masculino' ||
        raw.contains('masculino')) {
      return 'masculino';
    }

    return raw;
  }

  String get _athleteGender {
    return _normalizeGender(_profile?['gender']);
  }

  bool _eventMatchesAthleteGender(Map<String, dynamic> row) {
    final athleteGender = _athleteGender;
    if (athleteGender.isEmpty) return true;

    final event = row['events'];
    if (event is Map) {
      final eventGender = _normalizeGender(event['gender']);
      if (eventGender.isEmpty) return true;
      return eventGender == athleteGender;
    }

    final directGender = _normalizeGender(row['gender']);
    if (directGender.isEmpty) return true;
    return directGender == athleteGender;
  }

  bool _isTrainingEvent(Map<String, dynamic> row) {
    final event = row['events'];

    if (event is Map) {
      final type = (event['event_type'] ?? '').toString().toLowerCase().trim();
      return type == 'treino';
    }

    final directType =
        (row['event_type'] ?? '').toString().toLowerCase().trim();
    if (directType.isEmpty) return true;
    return directType == 'treino';
  }

  String _normalizarTipoEvento(dynamic value) {
    final raw = (value ?? '').toString().trim().toLowerCase();
    if (raw.contains('treino')) return 'treino';
    if (raw.contains('campeonato')) return 'campeonato';
    if (raw.contains('liga')) return 'liga';
    return raw;
  }

  String _eventTypeForRow(Map<String, dynamic> row) {
    final event = row['events'];
    if (event is Map) return _normalizarTipoEvento(event['event_type']);
    return _normalizarTipoEvento(row['event_type']);
  }

  String _championshipNameForRow(Map<String, dynamic> row) {
    final event = row['events'];
    final value =
        event is Map ? event['championship_name'] : row['championship_name'];
    final raw = (value ?? '').toString().trim();
    if (raw.isNotEmpty) return raw;

    final eventName = event is Map ? event['event_name'] : row['event_name'];
    return (eventName ?? 'Campeonato sem nome').toString().trim();
  }

  List<String> get _championshipNames {
    final names = <String>{};
    final doneEventIds = _playedChampionshipCheckinEventIds;

    for (final row in _convocations) {
      final type = _eventTypeForRow(row);
      if (type != 'campeonato' && type != 'liga') continue;
      if (!_eventMatchesAthleteGender(row)) continue;

      // Campeonato/liga aparece para o atleta somente quando ele realmente
      // jogou, ou seja, quando existe check-in realizado nesse evento.
      final eventId = (row['event_id'] ?? '').toString();
      if (eventId.isEmpty || !doneEventIds.contains(eventId)) continue;

      final name = _championshipNameForRow(row);
      if (name.trim().isNotEmpty) names.add(name.trim());
    }

    final list = names.toList()..sort((a, b) => a.compareTo(b));
    return list;
  }

  bool _isSelectedStatsEvent(Map<String, dynamic> row, {DateTime? start}) {
    final type = _eventTypeForRow(row);

    if (_statsMode == 'treino') {
      if (type != 'treino') return false;
    } else {
      if (type != 'campeonato' && type != 'liga') return false;

      final names = _championshipNames;
      final selectedName = _selectedChampionshipName != null &&
              names.contains(_selectedChampionshipName)
          ? _selectedChampionshipName
          : (names.isNotEmpty ? names.first : null);
      if (selectedName == null || selectedName.trim().isEmpty) return false;
      if (_championshipNameForRow(row) != selectedName) return false;
    }

    if (!_eventMatchesAthleteGender(row)) return false;
    if (!_isInsideTrainingPeriod(row, start)) return false;
    return true;
  }

  Set<String> _selectedStatsEventIds({DateTime? start}) {
    return _convocations
        .where((row) => _isSelectedStatsEvent(row, start: start))
        .map((row) => (row['event_id'] ?? '').toString())
        .where((id) => id.isNotEmpty)
        .toSet();
  }

  String get _selectedStatsLabel {
    if (_statsMode == 'treino') return 'Treinos';
    final names = _championshipNames;
    final selectedName = _selectedChampionshipName != null &&
            names.contains(_selectedChampionshipName)
        ? _selectedChampionshipName
        : (names.isNotEmpty ? names.first : null);
    if (selectedName == null || selectedName.trim().isEmpty) {
      return 'Campeonatos';
    }
    return selectedName;
  }

  void _showItemExplanation({
    required String title,
    required String explanation,
  }) {
    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.55),
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Row(
          children: [
            const Icon(Icons.info_outline, color: olympusBlue),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  color: olympusBlue,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
        content: Text(
          explanation,
          style: const TextStyle(
            color: olympusMuted,
            fontWeight: FontWeight.w600,
            height: 1.35,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'Entendi',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoButton({
    required String title,
    required String explanation,
    Color color = olympusGold,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: () => _showItemExplanation(
        title: title,
        explanation: explanation,
      ),
      child: Container(
        width: 20,
        height: 20,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color.withOpacity(0.16),
          border: Border.all(color: color.withOpacity(0.55)),
        ),
        child: Text(
          '!',
          style: TextStyle(
            color: color,
            fontSize: 12,
            height: 1,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }

  DateTime? _eventDateTime(Map<String, dynamic> row) {
    final event = row['events'];

    if (event is Map) {
      final eventDate = (event['event_date'] ?? '').toString().trim();
      final eventTime = (event['event_time'] ?? '').toString().trim();

      if (eventDate.isNotEmpty) {
        try {
          if (eventDate.contains('/')) {
            final d = eventDate.split('/');
            final t = eventTime.isEmpty ? ['0', '0'] : eventTime.split(':');

            if (d.length == 3 && t.length >= 2) {
              return DateTime(
                int.parse(d[2]),
                int.parse(d[1]),
                int.parse(d[0]),
                int.parse(t[0]),
                int.parse(t[1]),
              );
            }
          }

          final iso = DateTime.tryParse(eventDate);
          if (iso != null) {
            if (eventTime.isEmpty) return iso.toLocal();

            final t = eventTime.split(':');
            if (t.length >= 2) {
              return DateTime(
                iso.year,
                iso.month,
                iso.day,
                int.parse(t[0]),
                int.parse(t[1]),
              );
            }

            return iso.toLocal();
          }
        } catch (_) {
          return _parseDate(row['created_at']);
        }
      }
    }

    return _parseDate(row['created_at']);
  }

  bool _isInsideTrainingPeriod(Map<String, dynamic> row, DateTime? start) {
    final eventDate = _eventDateTime(row);
    if (!_isOnOrAfterStatsRuleStart(eventDate)) return false;
    if (start == null) return true;
    if (eventDate == null) return false;
    return !eventDate.isBefore(start);
  }

  bool _isInsidePeriod(dynamic value, DateTime? start) {
    final parsed = _parseDate(value);
    if (parsed == null) return false;
    if (start == null) return true;
    return !parsed.isBefore(start);
  }

  bool _isCheckinDone(dynamic value) {
    final raw = (value ?? '').toString().trim().toLowerCase();

    // A tabela checkins representa uma presença registrada.
    // Check-ins antigos, manuais ou atrasados podem estar sem status ou com
    // variações de texto. Só bloqueamos status claramente inválidos.
    if (raw.isEmpty) return true;

    if (raw == 'cancelado' ||
        raw == 'canceled' ||
        raw == 'cancelled' ||
        raw == 'erro' ||
        raw == 'error' ||
        raw == 'failed' ||
        raw == 'falhou') {
      return false;
    }

    return raw == 'realizado' ||
        raw == 'realizado com sucesso' ||
        raw == 'checked_in' ||
        raw == 'checkin_realizado' ||
        raw == 'check-in realizado' ||
        raw == 'presente' ||
        raw == 'presence' ||
        raw == 'ok' ||
        raw == 'success' ||
        raw == 'completed' ||
        raw == 'done' ||
        raw == 'manual' ||
        raw == 'late' ||
        raw == 'atrasado' ||
        raw == 'checkin_atrasado';
  }

  String _normalizeFundamento(dynamic value) {
    final raw = (value ?? '').toString().trim().toLowerCase();

    if (raw.contains('saque')) return 'Saque';
    if (raw.contains('recep')) return 'Recepção';
    if (raw.contains('ataque')) return 'Ataque';
    if (raw.contains('defesa')) return 'Defesa';
    if (raw.contains('bloqueio')) return 'Bloqueio';
    if (raw.contains('fis') ||
        raw.contains('fís') ||
        raw.contains('condicionamento')) {
      return 'Físico';
    }
    if (raw.contains('posicionamento') || raw.contains('tático')) {
      return 'Tático';
    }

    if (raw.isEmpty) return 'Sem fundamento';
    return '${raw[0].toUpperCase()}${raw.substring(1)}';
  }

  Future<List<Map<String, dynamic>>> _safeSelect(
    String table,
    String columns, {
    String? userId,
    String? recipientId,
  }) async {
    try {
      var query = _supabase.from(table).select(columns);

      if (userId != null) {
        query = query.eq('user_id', userId);
      }

      if (recipientId != null) {
        query = query.eq('recipient_id', recipientId);
      }

      final rows = await query;
      return List<Map<String, dynamic>>.from(rows as List);
    } catch (_) {
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> _loadMessages(String userId) async {
    final sources = <List<Map<String, dynamic>>>[];

    sources.add(await _safeSelect(
      'app_messages',
      'id, recipient_id, user_id, title, body, message, message_type, type, created_at',
      recipientId: userId,
    ));

    sources.add(await _safeSelect(
      'app_messages',
      'id, recipient_id, user_id, title, body, message, message_type, type, created_at',
      userId: userId,
    ));

    sources.add(await _safeSelect(
      'user_messages',
      'id, recipient_id, user_id, subject, title, content, body, created_at',
      recipientId: userId,
    ));

    sources.add(await _safeSelect(
      'user_messages',
      'id, recipient_id, user_id, subject, title, content, body, created_at',
      userId: userId,
    ));

    final map = <String, Map<String, dynamic>>{};

    for (final list in sources) {
      for (final row in list) {
        final id = (row['id'] ?? '').toString();
        if (id.isEmpty) continue;

        map[id] = row;
      }
    }

    final messages = map.values.toList()
      ..sort((a, b) {
        final ad = _parseDate(a['created_at']) ?? DateTime(1900);
        final bd = _parseDate(b['created_at']) ?? DateTime(1900);
        return bd.compareTo(ad);
      });

    return messages;
  }

  Future<List<Map<String, dynamic>>> _loadTrainingPlanBlocks() async {
    try {
      final rows = await _supabase.rpc(
        'get_checked_in_training_plan_blocks_for_athlete',
      );

      final list = List<Map<String, dynamic>>.from(rows as List);

      return list.map((row) {
        return {
          ...row,
          'events': {
            'id': row['event_id'],
            'event_type': row['event_type'],
            'gender': row['gender'],
            'event_date': row['event_date'],
            'event_time': row['event_time'],
          },
        };
      }).toList();
    } catch (e) {
      debugPrint('Erro ao carregar blocos de planejamento para atleta: $e');
      return [];
    }
  }

  String _normalizarHorario(dynamic value) {
    final raw = (value ?? '').toString().trim();
    if (raw.isEmpty) return '';

    final parts = raw.split(':');
    if (parts.length >= 2) {
      final h = int.tryParse(parts[0]);
      final m = int.tryParse(parts[1]);

      if (h != null && m != null) {
        return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
      }
    }

    return raw;
  }

  int _minutesFromTimeRange(dynamic startValue, dynamic endValue) {
    final start = _normalizarHorario(startValue);
    final end = _normalizarHorario(endValue);

    final startParts = start.split(':');
    final endParts = end.split(':');

    if (startParts.length != 2 || endParts.length != 2) return 0;

    final startHour = int.tryParse(startParts[0]);
    final startMinute = int.tryParse(startParts[1]);
    final endHour = int.tryParse(endParts[0]);
    final endMinute = int.tryParse(endParts[1]);

    if (startHour == null ||
        startMinute == null ||
        endHour == null ||
        endMinute == null) {
      return 0;
    }

    final startTotal = startHour * 60 + startMinute;
    final endTotal = endHour * 60 + endMinute;

    return math.max(0, endTotal - startTotal);
  }

  int _durationMinutesFromPlanBlock(Map<String, dynamic> row) {
    final duration = row['duration_minutes'];

    if (duration is int) return math.max(0, duration);
    if (duration is num) return math.max(0, duration.round());

    return _minutesFromTimeRange(row['start_time'], row['end_time']);
  }

  String _formatTrainingMinutes(int minutes) {
    final h = minutes ~/ 60;
    final m = minutes % 60;

    if (h <= 0) return '${m}min';
    if (m == 0) return '${h}h';
    return '${h}h ${m}min';
  }

  Color _trainingCategoryColor(String category) {
    switch (category) {
      case 'Fundamentos':
        return olympusSuccess;
      case 'Tático':
        return olympusPurple;
      case 'Físico':
        return olympusWarning;
      default:
        return olympusLightBlue;
    }
  }

  IconData _trainingCategoryIcon(String category) {
    switch (category) {
      case 'Fundamentos':
        return Icons.sports_volleyball_rounded;
      case 'Tático':
        return Icons.account_tree_rounded;
      case 'Físico':
        return Icons.fitness_center_rounded;
      default:
        return Icons.insights_rounded;
    }
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final user = _supabase.auth.currentUser;
      if (user == null) {
        throw Exception('Usuário não autenticado.');
      }

      final profileRows = await _supabase
          .from('profiles')
          .select('id, full_name, avatar_url, gender, user_type')
          .eq('id', user.id)
          .limit(1);

      final profiles = List<Map<String, dynamic>>.from(profileRows as List);

      final evaluationsRows = await _safeSelect(
        'training_evaluations',
        'id, event_id, coach_id, athlete_id, tipo, slot, motivo, fundamento, observacao, created_at, score',
      );

      final evaluations = evaluationsRows.where((row) {
        return (row['athlete_id'] ?? '').toString() == user.id;
      }).toList()
        ..sort((a, b) {
          final ad = _parseDate(a['created_at']) ?? DateTime(1900);
          final bd = _parseDate(b['created_at']) ?? DateTime(1900);
          return bd.compareTo(ad);
        });

      final checkins = await _safeSelect(
        'checkins',
        'id, user_id, event_id, check_in_status, created_at, checked_in_at, check_in_latitude, check_in_longitude',
        userId: user.id,
      );

      final convocations = await _safeSelect(
        'convocations',
        'id, user_id, event_id, status, justification, created_at, events!$_eventsEmbedFk (id, event_name, event_type, gender, event_date, event_time, championship_name)',
        userId: user.id,
      );

      final messages = await _loadMessages(user.id);
      final trainingPlanBlocks = await _loadTrainingPlanBlocks();

      final matchScouts = await _safeSelect(
        'match_scouts',
        'id, event_id, coach_id, athlete_id, set_number, '
            'saque_ponto, saque_erro, '
            'recepcao_boa, recepcao_erro, '
            'levantamento_bom, levantamento_erro, '
            'ataque_ponto, ataque_erro, '
            'bloqueio_ponto, bloqueio_erro, '
            'defesa_boa, defesa_erro, '
            'observacao, created_at, updated_at',
      );

      final matchScoutActionDetails = await _safeSelect(
        'match_scout_action_details',
        'id, event_id, coach_id, athlete_id, set_number, foundation, '
            'action_result, action_subtype, action_description, '
            'action_quality, action_impact, weight, created_at',
      );

      final athleteMatchScouts = matchScouts.where((row) {
        return (row['athlete_id'] ?? '').toString() == user.id;
      }).toList();

      final athleteMatchScoutActionDetails =
          matchScoutActionDetails.where((row) {
        return (row['athlete_id'] ?? '').toString() == user.id;
      }).toList();

      if (!mounted) return;
      setState(() {
        _profile = profiles.isNotEmpty ? profiles.first : null;
        _evaluations = evaluations;
        _checkins = checkins;
        _convocations = convocations;
        _trainingPlanBlocks = trainingPlanBlocks;
        _matchScouts = athleteMatchScouts;
        _matchScoutActionDetails = athleteMatchScoutActionDetails;
        _messages = messages;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Erro ao carregar estatísticas: $e';
        _loading = false;
      });
    }
  }

  List<Map<String, dynamic>> get _periodEvaluations {
    final start = _periodStart();
    final selectedEventIds = _selectedStatsEventIds(start: start);

    return _evaluations.where((row) {
      if (!_isInsidePeriod(row['created_at'], start)) return false;
      final eventId = (row['event_id'] ?? '').toString();
      if (eventId.isEmpty) return false;
      return selectedEventIds.contains(eventId);
    }).toList();
  }

  List<Map<String, dynamic>> get _periodMatchScouts {
    if (!_isChampionshipStatsMode) return const [];

    final start = _periodStart();

    return _matchScouts.where((row) {
      final eventId = (row['event_id'] ?? '').toString();
      if (eventId.isEmpty) return false;

      final dateSource = row['updated_at'] ?? row['created_at'];
      if (!_isInsidePeriod(dateSource, start)) return false;

      return _matchScoutBelongsToSelectedChampionship(row);
    }).toList();
  }

  List<Map<String, dynamic>> get _periodMatchScoutActionDetails {
    if (!_isChampionshipStatsMode) return const [];

    final selectedEventIds = _periodMatchScouts
        .map((row) => (row['event_id'] ?? '').toString())
        .where((id) => id.isNotEmpty)
        .toSet();

    if (selectedEventIds.isEmpty) return const [];

    final start = _periodStart();

    return _matchScoutActionDetails.where((row) {
      final eventId = (row['event_id'] ?? '').toString();
      if (eventId.isEmpty || !selectedEventIds.contains(eventId)) return false;

      final createdAt = row['created_at'];
      if (createdAt != null && !_isInsidePeriod(createdAt, start)) return false;

      return true;
    }).toList();
  }

  List<Map<String, dynamic>> get _selectedChampionshipGameActionDetails {
    final selectedId = _effectiveChampionshipGameId;
    if (selectedId == null || selectedId.isEmpty) return const [];

    return _periodMatchScoutActionDetails.where((row) {
      return (row['event_id'] ?? '').toString() == selectedId;
    }).toList();
  }

  Map<String, int> _detailsCountBySubtype({
    required List<Map<String, dynamic>> rows,
    required String result,
  }) {
    final map = <String, int>{};

    for (final row in rows) {
      final rowResult = (row['action_result'] ?? '').toString();
      if (rowResult != result) continue;

      final foundation = (row['foundation'] ?? '').toString().trim();
      final subtype = (row['action_subtype'] ?? '').toString().trim();

      final label = [
        if (foundation.isNotEmpty) foundation,
        if (subtype.isNotEmpty) subtype,
      ].join(' • ');

      if (label.trim().isEmpty) continue;
      map[label] = (map[label] ?? 0) + 1;
    }

    return map;
  }

  int _detailsWeightSum(List<Map<String, dynamic>> rows) {
    return rows.fold<int>(0, (sum, row) {
      final value = row['weight'];
      if (value is int) return sum + value;
      if (value is num) return sum + value.toInt();
      return sum + (int.tryParse((value ?? '0').toString()) ?? 0);
    });
  }

  int _scoutInt(Map<String, dynamic> row, String field) {
    final value = row[field];
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse((value ?? '0').toString()) ?? 0;
  }

  int get _championshipPositiveActions {
    return _periodMatchScouts.fold<int>(0, (sum, row) {
      return sum +
          _scoutInt(row, 'saque_ponto') +
          _scoutInt(row, 'recepcao_boa') +
          _scoutInt(row, 'levantamento_bom') +
          _scoutInt(row, 'ataque_ponto') +
          _scoutInt(row, 'bloqueio_ponto') +
          _scoutInt(row, 'defesa_boa');
    });
  }

  int get _championshipErrors {
    return _periodMatchScouts.fold<int>(0, (sum, row) {
      return sum +
          _scoutInt(row, 'saque_erro') +
          _scoutInt(row, 'recepcao_erro') +
          _scoutInt(row, 'levantamento_erro') +
          _scoutInt(row, 'ataque_erro') +
          _scoutInt(row, 'bloqueio_erro') +
          _scoutInt(row, 'defesa_erro');
    });
  }

  int get _championshipAutomaticScore {
    final positivos = _championshipPositiveActions;
    final erros = _championshipErrors;
    final total = positivos + erros;

    if (total == 0) return 0;

    final base = ((positivos / total) * 10).round();
    final bonusVolume = positivos >= 10 ? 1 : 0;
    final penalidadeErro = erros >= 8 ? 1 : 0;

    return (base + bonusVolume - penalidadeErro).clamp(0, 10);
  }

  int get _championshipEfficiencyPercent {
    final positivos = _championshipPositiveActions;
    final erros = _championshipErrors;
    final total = positivos + erros;

    if (total == 0) return 0;

    return ((positivos / total) * 100).round().clamp(0, 100);
  }

  int get _championshipEvaluatedSetsCount {
    final sets = <String>{};

    for (final row in _periodMatchScouts) {
      final eventId = (row['event_id'] ?? '').toString();
      final setNumber = (row['set_number'] as num?)?.toInt() ??
          int.tryParse((row['set_number'] ?? '1').toString()) ??
          1;

      final total = _scoutInt(row, 'saque_ponto') +
          _scoutInt(row, 'saque_erro') +
          _scoutInt(row, 'recepcao_boa') +
          _scoutInt(row, 'recepcao_erro') +
          _scoutInt(row, 'levantamento_bom') +
          _scoutInt(row, 'levantamento_erro') +
          _scoutInt(row, 'ataque_ponto') +
          _scoutInt(row, 'ataque_erro') +
          _scoutInt(row, 'bloqueio_ponto') +
          _scoutInt(row, 'bloqueio_erro') +
          _scoutInt(row, 'defesa_boa') +
          _scoutInt(row, 'defesa_erro');

      if (eventId.isNotEmpty && total > 0) {
        sets.add('$eventId:$setNumber');
      }
    }

    return sets.length;
  }

  int get _championshipEvaluatedMatchesCount {
    final events = <String>{};

    for (final row in _periodMatchScouts) {
      final eventId = (row['event_id'] ?? '').toString();
      final total = _scoutInt(row, 'saque_ponto') +
          _scoutInt(row, 'saque_erro') +
          _scoutInt(row, 'recepcao_boa') +
          _scoutInt(row, 'recepcao_erro') +
          _scoutInt(row, 'levantamento_bom') +
          _scoutInt(row, 'levantamento_erro') +
          _scoutInt(row, 'ataque_ponto') +
          _scoutInt(row, 'ataque_erro') +
          _scoutInt(row, 'bloqueio_ponto') +
          _scoutInt(row, 'bloqueio_erro') +
          _scoutInt(row, 'defesa_boa') +
          _scoutInt(row, 'defesa_erro');

      if (eventId.isNotEmpty && total > 0) {
        events.add(eventId);
      }
    }

    return events.length;
  }

  String get _championshipStrongestFundament {
    final entries = _championshipPositiveByFundament.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return entries.isEmpty ? 'Sem dados' : entries.first.key;
  }

  String get _championshipCriticalFundament {
    final entries = _championshipErrorsByFundament.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return entries.isEmpty ? 'Sem erros' : entries.first.key;
  }

  String get _championshipPerformanceLabel {
    final score = _championshipAutomaticScore;

    if (score >= 9) return 'Excelente';
    if (score >= 7) return 'Forte';
    if (score >= 5) return 'Regular';
    if (score > 0) return 'Atenção';
    return 'Sem scout';
  }

  Map<String, int> get _championshipPositiveByFundament {
    final map = <String, int>{
      'Saque': 0,
      'Recepção': 0,
      'Levantamento': 0,
      'Ataque': 0,
      'Bloqueio': 0,
      'Defesa': 0,
    };

    for (final row in _periodMatchScouts) {
      map['Saque'] = map['Saque']! + _scoutInt(row, 'saque_ponto');
      map['Recepção'] = map['Recepção']! + _scoutInt(row, 'recepcao_boa');
      map['Levantamento'] =
          map['Levantamento']! + _scoutInt(row, 'levantamento_bom');
      map['Ataque'] = map['Ataque']! + _scoutInt(row, 'ataque_ponto');
      map['Bloqueio'] = map['Bloqueio']! + _scoutInt(row, 'bloqueio_ponto');
      map['Defesa'] = map['Defesa']! + _scoutInt(row, 'defesa_boa');
    }

    map.removeWhere((_, value) => value <= 0);
    return map;
  }

  Map<String, int> get _championshipErrorsByFundament {
    final map = <String, int>{
      'Saque': 0,
      'Recepção': 0,
      'Levantamento': 0,
      'Ataque': 0,
      'Bloqueio': 0,
      'Defesa': 0,
    };

    for (final row in _periodMatchScouts) {
      map['Saque'] = map['Saque']! + _scoutInt(row, 'saque_erro');
      map['Recepção'] = map['Recepção']! + _scoutInt(row, 'recepcao_erro');
      map['Levantamento'] =
          map['Levantamento']! + _scoutInt(row, 'levantamento_erro');
      map['Ataque'] = map['Ataque']! + _scoutInt(row, 'ataque_erro');
      map['Bloqueio'] = map['Bloqueio']! + _scoutInt(row, 'bloqueio_erro');
      map['Defesa'] = map['Defesa']! + _scoutInt(row, 'defesa_erro');
    }

    map.removeWhere((_, value) => value <= 0);
    return map;
  }

  List<String> get _championshipScoutInsights {
    final items = <String>[];
    final positivos = _championshipPositiveActions;
    final erros = _championshipErrors;
    final total = positivos + erros;

    if (_periodMatchScouts.isEmpty || total == 0) {
      items.add('Ainda não há scout por fundamento para este campeonato.');
      return items;
    }

    final aproveitamento = ((positivos / total) * 100).round();
    items.add(
      'Seu aproveitamento no scout do campeonato está em $aproveitamento%.',
    );

    final fortes = _championshipPositiveByFundament.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    if (fortes.isNotEmpty) {
      items.add('${fortes.first.key} foi seu fundamento mais forte no jogo.');
    }

    final errosFundamento = _championshipErrorsByFundament.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    if (errosFundamento.isNotEmpty) {
      items.add(
        '${errosFundamento.first.key} é o principal ponto para ajustar.',
      );
    }

    if (_championshipAutomaticScore >= 8) {
      items.add('Sua nota automática indica alto desempenho no campeonato.');
    } else if (_championshipAutomaticScore > 0 &&
        _championshipAutomaticScore < 6) {
      items.add('Sua nota automática indica atenção para o próximo jogo.');
    }

    return items.take(5).toList();
  }

  List<Map<String, dynamic>> get _periodMessages {
    final start = _periodStart();
    return _messages
        .where((row) => _isInsidePeriod(row['created_at'], start))
        .toList();
  }

  int get _destaques {
    return _periodEvaluations.where((row) {
      return (row['tipo'] ?? '').toString().toLowerCase() == 'destaque';
    }).length;
  }

  int get _atencoes {
    return _periodEvaluations.where((row) {
      final tipo = (row['tipo'] ?? '').toString().toLowerCase();
      return tipo == 'atencao' || tipo == 'atenção';
    }).length;
  }

  int get _completas {
    return _periodEvaluations.where((row) {
      return (row['tipo'] ?? '').toString().toLowerCase() == 'completa';
    }).length;
  }

  int get _score {
    if (_isChampionshipStatsMode && _periodMatchScouts.isNotEmpty) {
      return _championshipAutomaticScore;
    }

    int total = 0;

    for (final row in _periodEvaluations) {
      final tipo = (row['tipo'] ?? '').toString().toLowerCase();

      if (tipo == 'destaque') {
        total += 2;
      } else if (tipo == 'atencao' || tipo == 'atenção') {
        total -= 1;
      } else if (tipo == 'completa') {
        final score = row['score'];
        if (score is num) total += score.round();
      } else {
        final score = row['score'];
        if (score is num) total += score.round();
      }
    }

    return total;
  }

  double get _presenceRate {
    final base = _trainingBaseCount;
    if (base == 0) return 0;
    return (_trainingPresenceCount / base).clamp(0, 1);
  }

  double get _absenceRate {
    final base = _trainingBaseCount;
    if (base == 0) return 0;
    return (_trainingAcceptedAbsentCount / base).clamp(0, 1);
  }

  String _formatPercentValue(double value) {
    final percent = value * 100;
    if (percent == percent.roundToDouble()) {
      return '${percent.round()}%';
    }

    return '${percent.toStringAsFixed(1)}%';
  }

  double get _presenceGoal => 0.80;

  Color _getPresenceBlinkColor(double rate) {
    final percent = (rate * 100).round();

    if (percent >= 100) return olympusSuccess;
    if (percent >= 76) return olympusWarning;
    return olympusDanger;
  }

  Color _getAbsenceBlinkColor(double rate) {
    if (rate <= 0) return olympusMuted;
    return olympusDanger;
  }

  String get _presenceStatus {
    if (_trainingBaseCount == 0) return 'Sem treinos';
    if (_presenceRate >= 0.95) return 'Elite';
    if (_presenceRate >= _presenceGoal) return 'Boa';
    if (_presenceRate >= 0.60) return 'Atenção';
    return 'Crítico';
  }

  Color get _presenceStatusColor {
    if (_trainingBaseCount == 0) return olympusMuted;
    if (_presenceRate >= 0.95) return olympusSuccess;
    if (_presenceRate >= _presenceGoal) return olympusLightBlue;
    if (_presenceRate >= 0.60) return olympusWarning;
    return olympusDanger;
  }

  Widget _presenceFailureValueWidget() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _BlinkingMetricValue(
          text: _formatPercentValue(_presenceRate),
          color: _getPresenceBlinkColor(_presenceRate),
        ),
        const SizedBox(width: 6),
        Text(
          '/',
          style: TextStyle(
            color: olympusMuted,
            fontSize: _StatsResponsive.font(context, 22),
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(width: 6),
        _BlinkingMetricValue(
          text: _formatPercentValue(_absenceRate),
          color: _getAbsenceBlinkColor(_absenceRate),
        ),
      ],
    );
  }

  Widget _presenceStatusPill() {
    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: _presenceStatusColor.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: _presenceStatusColor.withOpacity(0.28)),
      ),
      child: Text(
        'Status: $_presenceStatus',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: _presenceStatusColor,
          fontSize: 11,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  Set<String> get _convokedTrainingEventIds {
    final start = _periodStart();
    return _selectedStatsEventIds(start: start);
  }

  Set<String> get _doneCheckinEventIds {
    return _checkins
        .where((row) {
          if (!_isCheckinDone(row['check_in_status'])) return false;
          final eventId = (row['event_id'] ?? '').toString();
          return eventId.isNotEmpty;
        })
        .map((row) => (row['event_id'] ?? '').toString())
        .where((id) => id.isNotEmpty)
        .toSet();
  }

  bool _isExplicitAbsenceCheckinStatus(dynamic value) {
    final raw = (value ?? '').toString().trim().toLowerCase();

    return raw == 'ausente' ||
        raw == 'absence' ||
        raw == 'absent' ||
        raw == 'faltou' ||
        raw == 'falta' ||
        raw == 'no_show' ||
        raw == 'nao_compareceu' ||
        raw == 'não_compareceu' ||
        raw == 'nao compareceu' ||
        raw == 'não compareceu';
  }

  Set<String> get _explicitAbsenceEventIds {
    return _checkins
        .where((row) => _isExplicitAbsenceCheckinStatus(row['check_in_status']))
        .map((row) => (row['event_id'] ?? '').toString())
        .where((id) => id.isNotEmpty)
        .toSet();
  }

  bool _isPlayedChampionshipCheckin(Map<String, dynamic> row) {
    final eventId = (row['event_id'] ?? '').toString().trim();
    if (eventId.isEmpty) return false;

    final rawStatus =
        (row['check_in_status'] ?? '').toString().trim().toLowerCase();

    // Em campeonato/liga, "jogo jogado" precisa ser check-in real.
    // Não aceitamos linha vazia/pending apenas por existir na tabela checkins,
    // porque algumas linhas são criadas como pendentes antes do atleta jogar.
    if (rawStatus == 'pending' ||
        rawStatus == 'pendente' ||
        rawStatus == 'cancelado' ||
        rawStatus == 'canceled' ||
        rawStatus == 'cancelled' ||
        rawStatus == 'erro' ||
        rawStatus == 'error' ||
        rawStatus == 'failed' ||
        rawStatus == 'falhou') {
      return false;
    }

    final statusDone = rawStatus == 'realizado' ||
        rawStatus == 'realizado com sucesso' ||
        rawStatus == 'checked_in' ||
        rawStatus == 'checkin_realizado' ||
        rawStatus == 'check-in realizado' ||
        rawStatus == 'presente' ||
        rawStatus == 'presence' ||
        rawStatus == 'ok' ||
        rawStatus == 'success' ||
        rawStatus == 'completed' ||
        rawStatus == 'done' ||
        rawStatus == 'manual' ||
        rawStatus == 'late' ||
        rawStatus == 'atrasado' ||
        rawStatus == 'checkin_atrasado';

    final checkedInAt = (row['checked_in_at'] ?? '').toString().trim();
    final hasCheckedInAt =
        checkedInAt.isNotEmpty && checkedInAt.toLowerCase() != 'null';

    final hasCheckInLocation =
        row['check_in_latitude'] != null || row['check_in_longitude'] != null;

    return statusDone || hasCheckedInAt || hasCheckInLocation;
  }

  Set<String> get _playedChampionshipCheckinEventIds {
    return _checkins
        .where(_isPlayedChampionshipCheckin)
        .map((row) => (row['event_id'] ?? '').toString())
        .where((id) => id.isNotEmpty)
        .toSet();
  }

  Map<String, dynamic>? _convocationForEventId(String eventId) {
    if (eventId.isEmpty) return null;

    for (final row in _convocations) {
      if ((row['event_id'] ?? '').toString() == eventId) {
        return row;
      }
    }

    return null;
  }

  bool _isCheckinInsideConvokedTrainingPeriod(
    Map<String, dynamic> checkin,
    DateTime? start,
  ) {
    final eventId = (checkin['event_id'] ?? '').toString();
    final convocation = _convocationForEventId(eventId);

    if (convocation == null) return false;
    return _isSelectedStatsEvent(convocation, start: start);
  }

  bool get _isChampionshipStatsMode => _statsMode == 'campeonato';

  Set<String> get _playedSelectedEventIds {
    final start = _periodStart();
    final selectedEventIds = _selectedStatsEventIds(start: start);
    final doneEventIds = _playedChampionshipCheckinEventIds;

    // Em campeonatos/liga, a estatística é baseada em jogos jogados.
    // Ou seja: só entram na base os eventos da liga/campeonato selecionado
    // em que o atleta realmente teve check-in realizado.
    return selectedEventIds.intersection(doneEventIds);
  }

  int get _trainingBaseCount {
    if (_isChampionshipStatsMode) {
      return _playedSelectedEventIds.length;
    }

    // A base do percentual NÃO pode incluir treino futuro/pendente.
    // Conta somente o que já foi consolidado:
    // - presença: check-in realizado;
    // - falta: treino aceito/convocado sem check-in após fechar a janela.
    return _trainingPresenceCount + _trainingAcceptedAbsentCount;
  }

  int get _trainingPresenceCount {
    if (_isChampionshipStatsMode) {
      return _playedSelectedEventIds.length;
    }

    final convokedEventIds = _convokedTrainingEventIds;
    if (convokedEventIds.isEmpty) return 0;

    final doneEventIds = _doneCheckinEventIds;

    // A base de treino continua sendo eventos convocados, mas qualquer
    // check-in válido para o mesmo event_id conta como presença, inclusive
    // manual/atrasado.
    return convokedEventIds.intersection(doneEventIds).length;
  }

  int get _trainingPendingCount {
    if (_isChampionshipStatsMode) {
      return 0;
    }

    final start = _periodStart();
    final doneEventIds = _doneCheckinEventIds;

    return _convocations
        .where((row) {
          if (!_isSelectedStatsEvent(row, start: start)) return false;

          final status = (row['status'] ?? '').toString().toLowerCase().trim();
          if (status != 'pending') return false;

          final eventId = (row['event_id'] ?? '').toString();
          if (eventId.isEmpty || doneEventIds.contains(eventId)) return false;

          return _isPendingTrainingStillActionable(row);
        })
        .map((row) => (row['event_id'] ?? '').toString())
        .where((id) => id.isNotEmpty)
        .toSet()
        .length;
  }

  int get _trainingAcceptedAbsentCount {
    if (_isChampionshipStatsMode) {
      return 0;
    }

    final start = _periodStart();
    final explicitAbsences = _explicitAbsenceEventIds;
    final doneEventIds = _doneCheckinEventIds;

    return _convocations
        .where((row) {
          if (!_isSelectedStatsEvent(row, start: start)) return false;

          final eventId = (row['event_id'] ?? '').toString();
          if (eventId.isEmpty || doneEventIds.contains(eventId)) return false;

          return explicitAbsences.contains(eventId);
        })
        .map((row) => (row['event_id'] ?? '').toString())
        .where((id) => id.isNotEmpty)
        .toSet()
        .length;
  }

  List<_MonthlyPresenceAbsence> get _annualPresenceAbsenceByMonth {
    final now = DateTime.now();
    final year = now.year;

    final monthlyPresenceEventIds = <int, Set<String>>{
      for (int month = 1; month <= 12; month++) month: <String>{},
    };
    final monthlyAbsentEventIds = <int, Set<String>>{
      for (int month = 1; month <= 12; month++) month: <String>{},
    };

    final selectedEventDates = <String, DateTime>{};

    for (final row in _convocations) {
      if (!_isSelectedStatsEvent(row)) continue;

      final eventDate = _eventDateTime(row);
      if (!_isOnOrAfterStatsRuleStart(eventDate)) continue;
      if (eventDate == null || eventDate.year != year) continue;

      final eventId = (row['event_id'] ?? '').toString();
      if (eventId.isEmpty) continue;

      selectedEventDates[eventId] = eventDate;
    }

    final doneEventIds = _isChampionshipStatsMode
        ? _playedChampionshipCheckinEventIds
        : _doneCheckinEventIds;

    if (_isChampionshipStatsMode) {
      for (final entry in selectedEventDates.entries) {
        final eventId = entry.key;
        final eventDate = entry.value;

        if (!doneEventIds.contains(eventId)) continue;

        monthlyPresenceEventIds[eventDate.month]!.add(eventId);
      }

      return List.generate(12, (index) {
        final month = index + 1;
        return _MonthlyPresenceAbsence(
          month: month,
          presences: monthlyPresenceEventIds[month]!.length,
          absences: monthlyAbsentEventIds[month]!.length,
        );
      });
    }

    final explicitAbsences = _explicitAbsenceEventIds;

    for (final entry in selectedEventDates.entries) {
      final eventId = entry.key;
      final eventDate = entry.value;
      final month = eventDate.month;

      if (doneEventIds.contains(eventId)) {
        monthlyPresenceEventIds[month]!.add(eventId);
        monthlyAbsentEventIds[month]!.remove(eventId);
        continue;
      }

      // Não transformar pendente/vencido em falta no gráfico anual.
      // Falta só entra quando existe um registro explícito de ausência.
      if (explicitAbsences.contains(eventId)) {
        monthlyAbsentEventIds[month]!.add(eventId);
      }
    }

    return List.generate(12, (index) {
      final month = index + 1;
      return _MonthlyPresenceAbsence(
        month: month,
        presences: monthlyPresenceEventIds[month]!.length,
        absences: monthlyAbsentEventIds[month]!.length,
      );
    });
  }

  int get _trainingRejectedCount {
    if (_isChampionshipStatsMode) {
      return 0;
    }

    final start = _periodStart();

    return _convocations
        .where((row) {
          final status = (row['status'] ?? '').toString().toLowerCase().trim();
          if (status != 'rejected' &&
              status != 'declined' &&
              status != 'refused') {
            return false;
          }
          if (!_isSelectedStatsEvent(row, start: start)) return false;
          return true;
        })
        .map((row) => (row['event_id'] ?? '').toString())
        .where((id) => id.isNotEmpty)
        .toSet()
        .length;
  }

  List<Map<String, dynamic>> get _checkedInTrainingPlanBlocksHistory {
    return _trainingPlanBlocks.where((row) {
      if (!_isTrainingEvent(row)) return false;
      if (!_eventMatchesAthleteGender(row)) return false;
      return _durationMinutesFromPlanBlock(row) > 0;
    }).toList();
  }

  Map<String, int> get _trainingMinutesByCategory {
    final map = <String, int>{
      'Fundamentos': 0,
      'Tático': 0,
      'Físico': 0,
    };

    for (final row in _checkedInTrainingPlanBlocksHistory) {
      final category = (row['category'] ?? '').toString().trim().isEmpty
          ? 'Outros'
          : (row['category'] ?? '').toString().trim();

      map[category] = (map[category] ?? 0) + _durationMinutesFromPlanBlock(row);
    }

    return map;
  }

  Map<String, int> get _trainingMinutesByType {
    final map = <String, int>{};

    for (final row in _checkedInTrainingPlanBlocksHistory) {
      final type = (row['type'] ?? '').toString().trim();
      if (type.isEmpty) continue;

      map[type] = (map[type] ?? 0) + _durationMinutesFromPlanBlock(row);
    }

    return map;
  }

  int get _totalTrainingPlanMinutes {
    return _trainingMinutesByCategory.values.fold<int>(
      0,
      (sum, minutes) => sum + minutes,
    );
  }

  String get _evolutionLabel {
    if (_periodEvaluations.isEmpty) return 'Sem histórico';

    if (_destaques > _atencoes) return 'Melhorando';
    if (_atencoes > _destaques) return 'Precisa de atenção';
    return 'Estável';
  }

  Map<String, int> get _attentionByFundament {
    final map = <String, int>{};

    for (final row in _periodEvaluations) {
      final tipo = (row['tipo'] ?? '').toString().toLowerCase();
      if (tipo != 'atencao' && tipo != 'atenção') continue;

      final fundamento = _normalizeFundamento(row['fundamento']);
      map[fundamento] = (map[fundamento] ?? 0) + 1;
    }

    return map;
  }

  Map<String, int> get _positiveByFundament {
    final map = <String, int>{};

    for (final row in _periodEvaluations) {
      final tipo = (row['tipo'] ?? '').toString().toLowerCase();
      if (tipo != 'destaque') continue;

      final fundamento = _normalizeFundamento(row['fundamento']);
      map[fundamento] = (map[fundamento] ?? 0) + 1;
    }

    return map;
  }

  List<_TrendPoint> get _trendPoints {
    final pointsByDay = <DateTime, int>{};

    for (final row in _periodEvaluations) {
      final date = _parseDate(row['created_at']);
      if (date == null) continue;

      final day = DateTime(date.year, date.month, date.day);
      final tipo = (row['tipo'] ?? '').toString().toLowerCase();

      int score = 0;
      if (tipo == 'destaque') {
        score = 2;
      } else if (tipo == 'atencao' || tipo == 'atenção') {
        score = -1;
      } else {
        final raw = row['score'];
        if (raw is num) score = raw.round();
      }

      pointsByDay[day] = (pointsByDay[day] ?? 0) + score;
    }

    final entries = pointsByDay.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    int total = 0;
    return entries.map((entry) {
      total += entry.value;
      return _TrendPoint(entry.key, total);
    }).toList();
  }

  List<String> get _insights {
    if (_isChampionshipStatsMode) {
      final items = _championshipScoutInsights.toList();

      if (_periodMessages.isNotEmpty) {
        items.add(
          'Você recebeu ${_periodMessages.length} mensagem(ns) do técnico neste período.',
        );
      }

      return items.take(5).toList();
    }

    final items = <String>[];

    if (_periodEvaluations.isEmpty) {
      items.add('Ainda não há avaliações neste período.');
    } else {
      if (_destaques >= 3) {
        items.add('Você acumulou $_destaques destaque(s) no período.');
      }

      if (_atencoes >= 3) {
        items.add(
            'Você tem $_atencoes ponto(s) de atenção. Priorize os fundamentos recorrentes.');
      }

      if (_score > 0) {
        items.add('Seu saldo de evolução está positivo no período.');
      } else if (_score < 0) {
        items.add(
            'Seu saldo está negativo. Foque nos pontos de atenção indicados pelo técnico.');
      }

      final attention = _attentionByFundament.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));

      if (attention.isNotEmpty) {
        items.add(
            '${attention.first.key} é o principal fundamento para evoluir agora.');
      }

      final positive = _positiveByFundament.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));

      if (positive.isNotEmpty) {
        items.add('${positive.first.key} aparece como seu fundamento forte.');
      }
    }

    if (_trainingBaseCount > 0 && _presenceRate < 0.75) {
      items.add('⚠️ Sua presença está abaixo do ideal. Compareça aos treinos.');
    } else if (_trainingBaseCount > 0 && _presenceRate >= 1) {
      items.add('🔥 Presença perfeita! Continue assim.');
    } else if (_trainingBaseCount > 0 && _presenceRate >= _presenceGoal) {
      items.add('Excelente presença no período.');
    }

    if (_periodMessages.isNotEmpty) {
      items.add(
          'Você recebeu ${_periodMessages.length} mensagem(ns) do técnico neste período.');
    }

    return items.take(5).toList();
  }

  String _formatDate(dynamic value) {
    final date = _parseDate(value);
    if (date == null) return 'Sem data';

    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }

  String _messageTitle(Map<String, dynamic> message) {
    return (message['title'] ??
            message['subject'] ??
            (message['message_type'] ?? 'Mensagem'))
        .toString();
  }

  String _messageBody(Map<String, dynamic> message) {
    return (message['body'] ??
            message['message'] ??
            message['content'] ??
            'Sem conteúdo')
        .toString();
  }

  Widget _background() {
    return Stack(
      children: [
        Positioned.fill(
          child: Image.asset(
            'assets/images/monte_olimpo_v2.png',
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) {
              return Container(color: const Color(0xFF102845));
            },
          ),
        ),
        Positioned.fill(
          child: Container(color: Colors.black.withOpacity(0.38)),
        ),
        Positioned.fill(
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  olympusBlue.withOpacity(0.52),
                  Colors.black.withOpacity(0.18),
                  Colors.black.withOpacity(0.62),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _glassCard({
    required List<Widget> children,
    EdgeInsetsGeometry? padding,
    EdgeInsetsGeometry? margin,
  }) {
    return Container(
      width: double.infinity,
      margin: margin ??
          EdgeInsets.fromLTRB(
            _StatsResponsive.isDesktop(context)
                ? 48
                : (_StatsResponsive.isTablet(context) ? 28 : 16),
            0,
            _StatsResponsive.isDesktop(context)
                ? 48
                : (_StatsResponsive.isTablet(context) ? 28 : 16),
            _StatsResponsive.space(context, 12),
          ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            padding: padding ?? const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.94),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: Colors.white.withOpacity(0.52)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.14),
                  blurRadius: 16,
                  offset: const Offset(0, 7),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: children,
            ),
          ),
        ),
      ),
    );
  }

  double get _athleteImageScrollProgress {
    return (_scrollOffset / 420).clamp(0.0, 1.0).toDouble();
  }

  Widget _athleteParallaxLayer({
    required Alignment alignment,
    required double opacity,
    required double parallaxFactor,
    required double scale,
    bool strongerBottomShade = false,
  }) {
    final avatarUrl = (_profile?['avatar_url'] ?? '').toString().trim();
    if (avatarUrl.isEmpty) return const SizedBox.shrink();

    final progress = _athleteImageScrollProgress;
    final dynamicBlur = 1.0 + (progress * 2.4);
    final yOffset = -_scrollOffset * parallaxFactor;

    return Positioned.fill(
      child: IgnorePointer(
        child: Stack(
          fit: StackFit.expand,
          children: [
            Transform.translate(
              offset: Offset(0, yOffset),
              child: Transform.scale(
                scale: scale + (progress * 0.045),
                child: Opacity(
                  opacity: opacity,
                  child: ImageFiltered(
                    imageFilter: ImageFilter.blur(
                      sigmaX: dynamicBlur,
                      sigmaY: dynamicBlur,
                    ),
                    child: Image.network(
                      avatarUrl,
                      fit: BoxFit.contain,
                      alignment: alignment,
                      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                    ),
                  ),
                ),
              ),
            ),
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: strongerBottomShade
                      ? [
                          const Color(0xFF06172B).withOpacity(0.40),
                          olympusBlue.withOpacity(0.18),
                          const Color(0xFF06172B).withOpacity(0.60),
                        ]
                      : [
                          const Color(0xFF06172B).withOpacity(0.58),
                          olympusBlue.withOpacity(0.12),
                          const Color(0xFF06172B).withOpacity(0.36),
                        ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      const Color(0xFF071A30).withOpacity(0.70),
                      const Color(0xFF123861).withOpacity(0.35),
                      const Color(0xFF2C5F8D).withOpacity(0.25),
                    ],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header() {
    final fullName = (_profile?['full_name'] ??
            _supabase.auth.currentUser?.userMetadata?['full_name'] ??
            'Atleta')
        .toString();
    final avatarUrl = (_profile?['avatar_url'] ?? '').toString();

    return Container(
      margin: EdgeInsets.fromLTRB(
        _StatsResponsive.isDesktop(context)
            ? 48
            : (_StatsResponsive.isTablet(context) ? 28 : 16),
        _StatsResponsive.space(context, 14),
        _StatsResponsive.isDesktop(context)
            ? 48
            : (_StatsResponsive.isTablet(context) ? 28 : 16),
        _StatsResponsive.space(context, 12),
      ),
      padding: EdgeInsets.all(_StatsResponsive.space(context, 16)),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          colors: [Color(0xFF0D223B), Color(0xFF123861), Color(0xFF235E94)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: Colors.white.withOpacity(0.18)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.24),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Hero(
                tag: AthleteStatisticsDetailPage.heroTag,
                flightShuttleBuilder: (
                  flightContext,
                  animation,
                  flightDirection,
                  fromHeroContext,
                  toHeroContext,
                ) {
                  return ScaleTransition(
                    scale: Tween<double>(begin: 0.96, end: 1.0).animate(
                      CurvedAnimation(
                        parent: animation,
                        curve: Curves.easeOutCubic,
                      ),
                    ),
                    child: toHeroContext.widget,
                  );
                },
                child: CircleAvatar(
                  radius: 31,
                  backgroundColor: olympusGold,
                  backgroundImage: avatarUrl.trim().isNotEmpty
                      ? NetworkImage(avatarUrl)
                      : null,
                  child: avatarUrl.trim().isEmpty
                      ? Text(
                          fullName.isNotEmpty ? fullName[0].toUpperCase() : '?',
                          style: const TextStyle(
                            color: olympusBlue,
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                          ),
                        )
                      : null,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      fullName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: _StatsResponsive.font(context, 20),
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      'Estatísticas do Atleta • ${_periodLabel()}',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.84),
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _periodChip('semana', 'Semana'),
              _periodChip('mes', 'Mês'),
              _periodChip('geral', 'Geral'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statsModeSelector() {
    Widget modeButton({
      required String mode,
      required String label,
      required IconData icon,
      required Color color,
    }) {
      final selected = _statsMode == mode;
      return Expanded(
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            setState(() {
              _statsMode = mode;
              if (mode == 'campeonato') {
                final names = _championshipNames;
                _selectedChampionshipName ??=
                    names.isNotEmpty ? names.first : null;
              }
              _selectedAnnualMonth = null;
            });
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
            decoration: BoxDecoration(
              color: selected
                  ? color.withOpacity(0.18)
                  : Colors.white.withOpacity(0.94),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: selected ? color : olympusBorder,
                width: selected ? 1.5 : 1,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: color, size: 18),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: selected ? color : olympusBlue,
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final championshipNames = _championshipNames;

    return _glassCard(
      padding: const EdgeInsets.all(14),
      children: [
        const Text(
          'Tipo de estatística',
          style: TextStyle(
            color: olympusBlue,
            fontSize: 16,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            modeButton(
              mode: 'treino',
              label: 'Treinos',
              icon: Icons.fitness_center_rounded,
              color: olympusLightBlue,
            ),
            const SizedBox(width: 10),
            modeButton(
              mode: 'campeonato',
              label: 'Campeonatos',
              icon: Icons.emoji_events_rounded,
              color: olympusGold,
            ),
          ],
        ),
        if (_statsMode == 'campeonato') ...[
          const SizedBox(height: 12),
          Text(
            championshipNames.isEmpty
                ? 'Nenhum campeonato/liga encontrado para este atleta.'
                : 'Escolha o campeonato ou liga',
            style: const TextStyle(
              color: olympusMuted,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          if (championshipNames.isNotEmpty)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: championshipNames.map((name) {
                final selected = ((_selectedChampionshipName != null &&
                            championshipNames
                                .contains(_selectedChampionshipName))
                        ? _selectedChampionshipName
                        : championshipNames.first) ==
                    name;
                return ChoiceChip(
                  label: Text(name),
                  selected: selected,
                  showCheckmark: false,
                  selectedColor: olympusGold,
                  backgroundColor: olympusBg,
                  labelStyle: TextStyle(
                    color: selected ? olympusBlue : olympusMuted,
                    fontWeight: FontWeight.w900,
                  ),
                  side: BorderSide(
                    color: selected ? olympusGold : olympusBorder,
                  ),
                  onSelected: (_) {
                    setState(() {
                      _selectedChampionshipName = name;
                      _selectedAnnualMonth = null;
                    });
                  },
                );
              }).toList(),
            ),
        ],
      ],
    );
  }

  void _selectPeriod(String value) {
    if (_period == value) return;

    setState(() {
      _period = value;
      _selectedAnnualMonth = null;
      _selectedChampionshipGameId = null;
    });
  }

  Widget _periodChip(String value, String label) {
    final selected = _period == value;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(11),
        onTap: () => _selectPeriod(value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          decoration: BoxDecoration(
            color: selected ? olympusGold : Colors.white.withOpacity(0.26),
            borderRadius: BorderRadius.circular(11),
            border: Border.all(
              color: selected ? olympusGold : Colors.white.withOpacity(0.34),
              width: selected ? 1.2 : 1,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: olympusGold.withOpacity(0.22),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ]
                : const [],
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? olympusBlue : Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ),
    );
  }

  String _fullMonthLabel(int month) {
    const labels = [
      '',
      'Janeiro',
      'Fevereiro',
      'Março',
      'Abril',
      'Maio',
      'Junho',
      'Julho',
      'Agosto',
      'Setembro',
      'Outubro',
      'Novembro',
      'Dezembro',
    ];
    if (month < 1 || month > 12) return '';
    return labels[month];
  }

  String get _scoreStatusLabel {
    if (_periodEvaluations.isEmpty) return 'Sem avaliações';
    if (_score >= 8) return 'Alto desempenho';
    if (_score >= 3) return 'Evoluindo';
    if (_score >= 0) return 'Estável';
    return 'Precisa reagir';
  }

  List<Map<String, dynamic>> get _scoreHistoryRows {
    final rows = _periodEvaluations.toList()
      ..sort((a, b) {
        final ad = _parseDate(a['created_at']) ?? DateTime(1900);
        final bd = _parseDate(b['created_at']) ?? DateTime(1900);
        return bd.compareTo(ad);
      });

    return rows;
  }

  int _scoreDeltaForEvaluation(Map<String, dynamic> row) {
    final tipo = (row['tipo'] ?? '').toString().toLowerCase();

    if (tipo == 'destaque') return 2;
    if (tipo == 'atencao' || tipo == 'atenção') return -1;

    final score = row['score'];
    if (score is num) return score.round();

    return 0;
  }

  Color _scoreDeltaColor(int delta) {
    if (delta > 0) return olympusSuccess;
    if (delta < 0) return olympusDanger;
    return olympusMuted;
  }

  String _scoreDeltaLabel(int delta) {
    if (delta > 0) return '+$delta';
    return delta.toString();
  }

  Widget _scoreMiniPill({
    required String label,
    required String value,
    required Color color,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 9),
      decoration: BoxDecoration(
        color: color.withOpacity(0.13),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: color.withOpacity(0.34),
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(height: 5),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w900,
              height: 1,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withOpacity(0.72),
              fontSize: 10,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _scoreHeroCard() {
    return Container(
      width: double.infinity,
      margin: EdgeInsets.fromLTRB(
        _StatsResponsive.isDesktop(context)
            ? 48
            : (_StatsResponsive.isTablet(context) ? 28 : 16),
        0,
        _StatsResponsive.isDesktop(context)
            ? 48
            : (_StatsResponsive.isTablet(context) ? 28 : 16),
        _StatsResponsive.space(context, 12),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            padding: EdgeInsets.fromLTRB(
              _StatsResponsive.space(context, 13),
              _StatsResponsive.space(context, 13),
              _StatsResponsive.space(context, 13),
              _StatsResponsive.space(context, 11),
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              gradient: const LinearGradient(
                colors: [
                  Color(0xFF071A30),
                  Color(0xFF123861),
                  Color(0xFF2C5F8D),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              border: Border.all(
                color: olympusGold,
                width: 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: olympusGold.withOpacity(0.20),
                  blurRadius: 26,
                  spreadRadius: 1,
                  offset: const Offset(0, 10),
                ),
                BoxShadow(
                  color: Colors.black.withOpacity(0.18),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Stack(
              children: [
                _athleteParallaxLayer(
                  alignment: Alignment.topCenter,
                  opacity: 0.34,
                  parallaxFactor: 0.075,
                  scale: 1.18,
                ),
                Positioned(
                  top: -36,
                  right: -34,
                  child: Container(
                    width: 130,
                    height: 130,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withOpacity(0.06),
                    ),
                  ),
                ),
                Positioned(
                  bottom: -38,
                  left: -34,
                  child: Container(
                    width: 116,
                    height: 116,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: olympusGold.withOpacity(0.08),
                    ),
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            gradient: const LinearGradient(
                              colors: [
                                Color(0xFFF8E08E),
                                Color(0xFFD4AF37),
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: olympusGold.withOpacity(0.40),
                                blurRadius: 10,
                                spreadRadius: 0.4,
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.scoreboard_rounded,
                            color: olympusBlue,
                            size: 21,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Score de $_selectedStatsLabel',
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.82),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                _scoreStatusLabel,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ],
                          ),
                        ),
                        TextButton.icon(
                          onPressed: _showScoreHistory,
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.white,
                            backgroundColor: Colors.white.withOpacity(0.10),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 8,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(999),
                              side: BorderSide(
                                color: Colors.white.withOpacity(0.18),
                              ),
                            ),
                          ),
                          icon: const Icon(Icons.history_rounded, size: 16),
                          label: const Text(
                            'Ver histórico',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '$_score',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: _StatsResponsive.font(context, 42),
                            fontWeight: FontWeight.w900,
                            height: 0.95,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 7),
                          child: Text(
                            'pontos',
                            style: TextStyle(
                              color: olympusGold.withOpacity(0.95),
                              fontSize: 15,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 9),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final isNarrow = constraints.maxWidth < 420;
                        final itemWidth = isNarrow
                            ? (constraints.maxWidth - 8) / 2
                            : (constraints.maxWidth - 16) / 3;
                        final cards = [
                          _scoreMiniPill(
                            label: _isChampionshipStatsMode
                                ? 'Ações'
                                : 'Destaques',
                            value: _isChampionshipStatsMode
                                ? _championshipPositiveActions.toString()
                                : _destaques.toString(),
                            color: olympusSuccess,
                            icon: Icons.star_rounded,
                          ),
                          _scoreMiniPill(
                            label:
                                _isChampionshipStatsMode ? 'Erros' : 'Atenções',
                            value: _isChampionshipStatsMode
                                ? _championshipErrors.toString()
                                : _atencoes.toString(),
                            color: olympusWarning,
                            icon: Icons.warning_amber_rounded,
                          ),
                          _scoreMiniPill(
                            label:
                                _isChampionshipStatsMode ? 'Sets' : 'Mensais',
                            value: _isChampionshipStatsMode
                                ? _periodMatchScouts
                                    .map((row) =>
                                        (row['set_number'] as num?)?.toInt() ??
                                        1)
                                    .toSet()
                                    .length
                                    .toString()
                                : _completas.toString(),
                            color: olympusLightBlue,
                            icon: Icons.assignment_turned_in_outlined,
                          ),
                        ];

                        return Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: cards
                              .map(
                                (card) => ConstrainedBox(
                                  constraints: BoxConstraints(
                                    minWidth: itemWidth.clamp(
                                        120.0, constraints.maxWidth),
                                    maxWidth: itemWidth.clamp(
                                        120.0, constraints.maxWidth),
                                    minHeight: 86,
                                  ),
                                  child: card,
                                ),
                              )
                              .toList(),
                        );
                      },
                    ),
                    const SizedBox(height: 9),
                    Container(
                      height: 1,
                      width: double.infinity,
                      color: Colors.white.withOpacity(0.14),
                    ),
                    const SizedBox(height: 9),
                    _annualPresenceAbsenceChart(),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _trainingPlanCategoryRow({
    required String category,
    required int minutes,
    required int total,
  }) {
    final color = _trainingCategoryColor(category);
    final percent = total <= 0 ? 0.0 : minutes / total;

    return Container(
      margin: const EdgeInsets.only(bottom: 9),
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: color.withOpacity(0.18)),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withOpacity(0.14),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              _trainingCategoryIcon(category),
              color: color,
              size: 20,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  category,
                  style: const TextStyle(
                    color: olympusBlue,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: percent.clamp(0, 1),
                    minHeight: 7,
                    backgroundColor: olympusBorder,
                    valueColor: AlwaysStoppedAnimation<Color>(color),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                _formatTrainingMinutes(minutes),
                style: TextStyle(
                  color: color,
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '${(percent * 100).round()}%',
                style: const TextStyle(
                  color: olympusMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _trainingPlanPieChartAthlete() {
    final categoryMinutes = _trainingMinutesByCategory;
    final typeRanking = _trainingMinutesByType.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final totalMinutes = _totalTrainingPlanMinutes;
    final hasData = totalMinutes > 0;

    return Container(
      width: double.infinity,
      margin: EdgeInsets.fromLTRB(
        _StatsResponsive.isDesktop(context)
            ? 48
            : (_StatsResponsive.isTablet(context) ? 28 : 16),
        0,
        _StatsResponsive.isDesktop(context)
            ? 48
            : (_StatsResponsive.isTablet(context) ? 28 : 16),
        _StatsResponsive.space(context, 12),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(26),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(26),
              gradient: const LinearGradient(
                colors: [
                  Color(0xFFFDFEFF),
                  Color(0xFFF5F9FE),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              border: Border.all(color: Colors.white.withOpacity(0.72)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.13),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
                BoxShadow(
                  color: olympusGold.withOpacity(0.12),
                  blurRadius: 22,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: Stack(
              children: [
                Positioned(
                  right: -28,
                  top: -30,
                  child: Container(
                    width: 110,
                    height: 110,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: olympusGold.withOpacity(0.08),
                    ),
                  ),
                ),
                Positioned(
                  left: -34,
                  bottom: -36,
                  child: Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: olympusLightBlue.withOpacity(0.07),
                    ),
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 46,
                          height: 46,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            gradient: const LinearGradient(
                              colors: [
                                Color(0xFFF8E08E),
                                Color(0xFFD4AF37),
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: olympusGold.withOpacity(0.26),
                                blurRadius: 14,
                                spreadRadius: 1,
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.pie_chart_rounded,
                            color: olympusBlue,
                            size: 25,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Tempo do Treino',
                                style: TextStyle(
                                  color: olympusBlue,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                'Histórico completo dos treinos com check-in',
                                style: TextStyle(
                                  color: olympusMuted.withOpacity(0.92),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                        _infoButton(
                          title: 'Tempo do Treino',
                          explanation:
                              'Mostra a soma do tempo planejado pelo técnico somente nos treinos em que você fez check-in. Esta visão usa o histórico completo e não depende do filtro de período.',
                          color: olympusGold,
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    if (!hasData)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(13),
                        decoration: BoxDecoration(
                          color: olympusBlue.withOpacity(0.06),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: olympusBlue.withOpacity(0.10),
                          ),
                        ),
                        child: const Text(
                          'Ainda não há planejamento salvo para treinos em que você fez check-in.',
                          style: TextStyle(
                            color: olympusMuted,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            height: 1.35,
                          ),
                        ),
                      )
                    else ...[
                      SizedBox(
                        height: 188,
                        width: double.infinity,
                        child: CustomPaint(
                          painter: _TrainingPlanPiePainter(
                            data: categoryMinutes,
                            colors: {
                              'Fundamentos': olympusSuccess,
                              'Tático': olympusPurple,
                              'Físico': olympusWarning,
                            },
                            totalMinutes: totalMinutes,
                            centerText: _formatTrainingMinutes(totalMinutes),
                            mutedColor: olympusMuted,
                            titleColor: olympusBlue,
                          ),
                          child: const SizedBox.expand(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      _trainingPlanCategoryRow(
                        category: 'Fundamentos',
                        minutes: categoryMinutes['Fundamentos'] ?? 0,
                        total: totalMinutes,
                      ),
                      _trainingPlanCategoryRow(
                        category: 'Tático',
                        minutes: categoryMinutes['Tático'] ?? 0,
                        total: totalMinutes,
                      ),
                      _trainingPlanCategoryRow(
                        category: 'Físico',
                        minutes: categoryMinutes['Físico'] ?? 0,
                        total: totalMinutes,
                      ),
                      if (typeRanking.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        const Text(
                          'Principais focos treinados',
                          style: TextStyle(
                            color: olympusBlue,
                            fontSize: 13,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 8),
                        ...typeRanking.take(4).map((entry) {
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    entry.key,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: olympusMuted,
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                                Text(
                                  _formatTrainingMinutes(entry.value),
                                  style: const TextStyle(
                                    color: olympusBlue,
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                      ],
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showScoreHistory() {
    final rows = _scoreHistoryRows;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return SafeArea(
          top: false,
          child: Container(
            height: MediaQuery.of(context).size.height * 0.86,
            decoration: const BoxDecoration(
              color: Color(0xFFF4F7FB),
              borderRadius: BorderRadius.vertical(
                top: Radius.circular(28),
              ),
            ),
            child: Column(
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 46,
                  height: 4,
                  decoration: BoxDecoration(
                    color: olympusBorder,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                Container(
                  margin: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(22),
                    gradient: const LinearGradient(
                      colors: [
                        Color(0xFF0D223B),
                        Color(0xFF123861),
                        Color(0xFF235E94),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: olympusBlue.withOpacity(0.22),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: olympusGold.withOpacity(0.18),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: olympusGold.withOpacity(0.44),
                          ),
                        ),
                        child: const Icon(
                          Icons.scoreboard_rounded,
                          color: olympusGold,
                          size: 26,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Histórico do Score',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 19,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Total do período: $_score ponto(s)',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.78),
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close_rounded),
                        color: Colors.white,
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: rows.isEmpty
                      ? const Center(
                          child: Padding(
                            padding: EdgeInsets.all(20),
                            child: Text(
                              'Nenhuma avaliação registrada neste período.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: olympusMuted,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
                          itemCount: rows.length,
                          itemBuilder: (context, index) {
                            final item = rows[index];
                            final tipo =
                                (item['tipo'] ?? 'Avaliação').toString();
                            final fundamento =
                                (item['fundamento'] ?? '').toString().trim();
                            final motivo =
                                (item['motivo'] ?? '').toString().trim();
                            final observacao =
                                (item['observacao'] ?? '').toString().trim();
                            final delta = _scoreDeltaForEvaluation(item);
                            final deltaColor = _scoreDeltaColor(delta);

                            return Container(
                              margin: const EdgeInsets.only(bottom: 10),
                              padding: const EdgeInsets.all(13),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(
                                  color: deltaColor.withOpacity(0.18),
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.05),
                                    blurRadius: 10,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    width: 46,
                                    height: 46,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: deltaColor.withOpacity(0.12),
                                      borderRadius: BorderRadius.circular(15),
                                      border: Border.all(
                                        color: deltaColor.withOpacity(0.24),
                                      ),
                                    ),
                                    child: Text(
                                      _scoreDeltaLabel(delta),
                                      style: TextStyle(
                                        color: deltaColor,
                                        fontSize: 15,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                tipo.toUpperCase(),
                                                style: const TextStyle(
                                                  color: olympusBlue,
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w900,
                                                ),
                                              ),
                                            ),
                                            Text(
                                              _formatDate(item['created_at']),
                                              style: const TextStyle(
                                                color: olympusMuted,
                                                fontSize: 11,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ],
                                        ),
                                        if (fundamento.isNotEmpty) ...[
                                          const SizedBox(height: 5),
                                          Text(
                                            fundamento,
                                            style: const TextStyle(
                                              color: olympusLightBlue,
                                              fontSize: 12.5,
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                        ],
                                        if (motivo.isNotEmpty) ...[
                                          const SizedBox(height: 5),
                                          Text(
                                            motivo,
                                            style: const TextStyle(
                                              color: olympusMuted,
                                              fontSize: 12,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ],
                                        if (observacao.isNotEmpty) ...[
                                          const SizedBox(height: 7),
                                          Text(
                                            observacao,
                                            style: const TextStyle(
                                              color: Color(0xFF6A7E94),
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                              height: 1.3,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _metricCard({
    required IconData icon,
    required String title,
    required String value,
    required Color color,
    required String explanation,
    Widget? valueWidget,
    Widget? bottomWidget,
    VoidCallback? onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          constraints: const BoxConstraints(minHeight: 116),
          padding: EdgeInsets.all(_StatsResponsive.isSmall(context) ? 10 : 12),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.96),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: olympusBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, color: color, size: 22),
                  const Spacer(),
                  _infoButton(
                    title: title,
                    explanation: explanation,
                    color: color,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: valueWidget ??
                    Text(
                      value,
                      style: TextStyle(
                        color: olympusBlue,
                        fontSize: _StatsResponsive.font(context, 23),
                        fontWeight: FontWeight.w900,
                      ),
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: olympusMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (bottomWidget != null) bottomWidget,
            ],
          ),
        ),
      ),
    );
  }

  Widget _metricsGrid() {
    final presenceValue =
        '${_formatPercentValue(_presenceRate)} / ${_formatPercentValue(_absenceRate)}';

    final middleTitle = _isChampionshipStatsMode ? 'Ações' : 'Destaques';
    final middleValue = _isChampionshipStatsMode
        ? _championshipPositiveActions.toString()
        : _destaques.toString();

    final rightTitle = _isChampionshipStatsMode ? 'Erros' : 'Atenções';
    final rightValue = _isChampionshipStatsMode
        ? _championshipErrors.toString()
        : _atencoes.toString();

    return Container(
      width: double.infinity,
      margin: EdgeInsets.fromLTRB(
        _StatsResponsive.isDesktop(context)
            ? 48
            : (_StatsResponsive.isTablet(context) ? 28 : 16),
        0,
        _StatsResponsive.isDesktop(context)
            ? 48
            : (_StatsResponsive.isTablet(context) ? 28 : 16),
        _StatsResponsive.space(context, 12),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.97),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withOpacity(0.55)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.10),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: _compactMetricItem(
              icon: Icons.fact_check_outlined,
              color: olympusPurple,
              value: presenceValue,
              label: 'Presença / Falta',
              badge: 'Status: $_presenceStatus',
            ),
          ),
          _compactMetricDivider(),
          Expanded(
            child: _compactMetricItem(
              icon: _isChampionshipStatsMode
                  ? Icons.trending_up_rounded
                  : Icons.star_rounded,
              color: olympusSuccess,
              value: middleValue,
              label: middleTitle,
            ),
          ),
          _compactMetricDivider(),
          Expanded(
            child: _compactMetricItem(
              icon: _isChampionshipStatsMode
                  ? Icons.error_outline_rounded
                  : Icons.warning_amber_rounded,
              color: _isChampionshipStatsMode ? olympusDanger : olympusWarning,
              value: rightValue,
              label: rightTitle,
            ),
          ),
        ],
      ),
    );
  }

  Widget _compactMetricDivider() {
    return Container(
      width: 1,
      height: 70,
      margin: const EdgeInsets.symmetric(horizontal: 6),
      color: olympusBorder,
    );
  }

  Widget _compactMetricItem({
    required IconData icon,
    required Color color,
    required String value,
    required String label,
    String? badge,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(height: 7),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            value,
            maxLines: 1,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: olympusBlue,
              fontSize: 21,
              fontWeight: FontWeight.w900,
              height: 1,
            ),
          ),
        ),
        const SizedBox(height: 5),
        Text(
          label,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: olympusMuted,
            fontSize: 10.5,
            fontWeight: FontWeight.w800,
            height: 1.12,
          ),
        ),
        if (badge != null) ...[
          const SizedBox(height: 7),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: _presenceStatusColor.withOpacity(0.10),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: _presenceStatusColor.withOpacity(0.25),
              ),
            ),
            child: Text(
              badge,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: _presenceStatusColor,
                fontSize: 9,
                fontWeight: FontWeight.w900,
                height: 1,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _sectionTitle(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: olympusGold, size: 22),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              color: olympusBlue,
              fontSize: 17,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ],
    );
  }

  Widget _presenceExplanationCard() {
    final genderLabel = _athleteGender.isEmpty
        ? 'não informado'
        : _athleteGender == 'feminino'
            ? 'Feminino'
            : _athleteGender == 'masculino'
                ? 'Masculino'
                : _athleteGender;

    return _glassCard(
      padding: const EdgeInsets.all(14),
      children: [
        Row(
          children: [
            const Icon(Icons.fact_check_outlined, color: olympusGold, size: 22),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'Como calculamos sua presença',
                style: TextStyle(
                  color: olympusBlue,
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            _infoButton(
              title: 'Presença',
              explanation:
                  'Presença = check-ins realizados ÷ eventos convocados, incluindo check-in atrasado/manual. Falta = eventos convocados sem check-in depois do prazo de 30 minutos, incluindo recusados. Esta tela considera somente treinos a partir de 01/05/2026. Quando o evento possui gênero, o cálculo considera apenas treinos do mesmo gênero cadastrado no perfil da atleta.',
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          'Base atual: ${_formatPercentValue(_presenceRate)} de presença e ${_formatPercentValue(_absenceRate)} de faltas sobre $_trainingBaseCount ${_isChampionshipStatsMode ? 'jogo(s) jogado(s)' : 'evento(s) convocado(s)'}. Presenças: $_trainingPresenceCount • Faltas: $_trainingAcceptedAbsentCount • Pendentes: $_trainingPendingCount • Recusados: $_trainingRejectedCount. Regra válida ${_periodRuleLabel()}. Gênero usado no filtro: $genderLabel.',
          style: const TextStyle(
            color: olympusMuted,
            fontSize: 13,
            fontWeight: FontWeight.w700,
            height: 1.35,
          ),
        ),
      ],
    );
  }

  String _shortMonthLabel(int month) {
    const labels = [
      '',
      'Jan',
      'Fev',
      'Mar',
      'Abr',
      'Mai',
      'Jun',
      'Jul',
      'Ago',
      'Set',
      'Out',
      'Nov',
      'Dez',
    ];
    return labels[month];
  }

  Widget _annualPresenceAbsenceChart() {
    final data = _annualPresenceAbsenceByMonth;
    final totalPresences =
        data.fold<int>(0, (sum, item) => sum + item.presences);
    final totalAbsences = data.fold<int>(0, (sum, item) => sum + item.absences);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                gradient: LinearGradient(
                  colors: [
                    olympusGold.withOpacity(0.95),
                    const Color(0xFFF8E08E),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: olympusGold.withOpacity(0.22),
                    blurRadius: 12,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: const Icon(
                Icons.show_chart_rounded,
                color: olympusBlue,
                size: 22,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Presença anual • $_selectedStatsLabel',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'Resumo anual consolidado',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.72),
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            _infoButton(
              title: 'Presença anual • $_selectedStatsLabel',
              explanation:
                  'Resumo anual com presenças e faltas por mês. Presença é check-in realizado, incluindo check-in atrasado/manual. Em campeonatos/liga, jogos não jogados não entram como falta.',
              color: olympusGold,
            ),
          ],
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final isNarrow = constraints.maxWidth < 390;
            final cards = [
              _annualSummaryPill(
                label: 'Presenças',
                value: totalPresences,
                color: olympusSuccess,
                icon: Icons.check_circle_rounded,
              ),
              _annualSummaryPill(
                label: 'Faltas',
                value: totalAbsences,
                color: olympusDanger,
                icon: Icons.cancel_rounded,
              ),
            ];

            if (isNarrow) {
              return Column(
                children: [
                  SizedBox(width: double.infinity, child: cards[0]),
                  const SizedBox(height: 10),
                  SizedBox(width: double.infinity, child: cards[1]),
                ],
              );
            }

            return Row(
              children: [
                Expanded(child: cards[0]),
                const SizedBox(width: 10),
                Expanded(child: cards[1]),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _annualSummaryPill({
    required String label,
    required int value,
    required Color color,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: color.withOpacity(0.13),
        border: Border.all(
          color: color.withOpacity(0.34),
        ),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white.withOpacity(0.76),
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Text(
            value.toString(),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _chartLegendDot({
    required String label,
    required Color color,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: color.withOpacity(0.55),
                blurRadius: 8,
              ),
            ],
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withOpacity(0.78),
            fontSize: 12,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }

  Widget _evolutionChart() {
    final points = _trendPoints;

    return _glassCard(
      children: [
        Row(
          children: [
            Expanded(
                child: _sectionTitle('Evolução', Icons.show_chart_rounded)),
            _infoButton(
              title: 'Evolução',
              explanation:
                  'O gráfico acumula o score das avaliações ao longo do período. Destaque soma +2, ponto de atenção subtrai -1 e avaliação completa usa o score salvo.',
            ),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 170,
          child: points.isEmpty
              ? const Center(
                  child: Text(
                    'Sem avaliações suficientes para gerar gráfico.',
                    style: TextStyle(
                      color: olympusMuted,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                )
              : CustomPaint(
                  painter: _AthleteTrendPainter(
                    points: points,
                    lineColor: olympusBlue,
                    fillColor: olympusGold.withOpacity(0.14),
                  ),
                  child: const SizedBox.expand(),
                ),
        ),
      ],
    );
  }

  Widget _fundamentsSection() {
    final positiveMap = _isChampionshipStatsMode
        ? _championshipPositiveByFundament
        : _positiveByFundament;
    final attentionMap = _isChampionshipStatsMode
        ? _championshipErrorsByFundament
        : _attentionByFundament;

    final positive = positiveMap.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final attention = attentionMap.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    Widget listBlock({
      required String title,
      required List<MapEntry<String, int>> entries,
      required Color color,
      required String empty,
    }) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: color,
              fontSize: 14,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          if (entries.isEmpty)
            Text(
              empty,
              style: const TextStyle(
                color: olympusMuted,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            )
          else
            ...entries.take(3).map((entry) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 7),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        entry.key,
                        style: const TextStyle(
                          color: olympusBlue,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.11),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '${entry.value}',
                        style: TextStyle(
                          color: color,
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      );
    }

    return _glassCard(
      children: [
        Row(
          children: [
            Expanded(
                child: _sectionTitle('Fundamentos', Icons.sports_volleyball)),
            _infoButton(
              title: 'Fundamentos',
              explanation: _isChampionshipStatsMode
                  ? 'Mostra os fundamentos do scout do campeonato. Fortes vêm das ações positivas; Para melhorar vem dos erros registrados pelo técnico.'
                  : 'Mostra os fundamentos que mais apareceram nas avaliações. Fortes vêm dos destaques; Para melhorar vem dos pontos de atenção.',
            ),
          ],
        ),
        const SizedBox(height: 14),
        listBlock(
          title: _isChampionshipStatsMode ? 'Ações positivas' : 'Fortes',
          entries: positive,
          color: olympusSuccess,
          empty: _isChampionshipStatsMode
              ? 'Nenhuma ação positiva registrada no scout.'
              : 'Nenhum fundamento em destaque no período.',
        ),
        const SizedBox(height: 16),
        listBlock(
          title: _isChampionshipStatsMode
              ? 'Erros por fundamento'
              : 'Para melhorar',
          entries: attention,
          color: olympusWarning,
          empty: _isChampionshipStatsMode
              ? 'Nenhum erro registrado no scout.'
              : 'Nenhum ponto de atenção no período.',
        ),
      ],
    );
  }

  Widget _insightsSection() {
    return _glassCard(
      children: [
        Row(
          children: [
            Expanded(
                child: _sectionTitle(
                    'Insights inteligentes', Icons.lightbulb_outline)),
            _infoButton(
              title: 'Insights inteligentes',
              explanation:
                  'São mensagens automáticas geradas com base nas avaliações, presença, mensagens e fundamentos recorrentes do período.',
            ),
          ],
        ),
        const SizedBox(height: 12),
        ..._insights.map((item) {
          return Container(
            margin: const EdgeInsets.only(bottom: 9),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: olympusBlue.withOpacity(0.06),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: olympusBlue.withOpacity(0.10)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.bolt_rounded, color: olympusGold, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    item,
                    style: const TextStyle(
                      color: olympusMuted,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      height: 1.3,
                    ),
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _messagesSection() {
    final messages = _periodMessages.take(8).toList();

    return _glassCard(
      children: [
        Row(
          children: [
            Expanded(
                child: _sectionTitle(
                    'Mensagens do técnico', Icons.mark_chat_unread_outlined)),
            _infoButton(
              title: 'Mensagens do técnico',
              explanation:
                  'Exibe feedbacks e mensagens enviadas pelo técnico para a atleta, quando salvos nas tabelas app_messages ou user_messages.',
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (messages.isEmpty)
          const Text(
            'Nenhuma mensagem recebida neste período.',
            style: TextStyle(
              color: olympusMuted,
              fontWeight: FontWeight.w700,
            ),
          )
        else
          ...messages.map((message) {
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: olympusGold.withOpacity(0.08),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: olympusGold.withOpacity(0.18)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.mail_outline_rounded,
                        color: olympusBlue,
                        size: 18,
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          _messageTitle(message),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: olympusBlue,
                            fontSize: 13,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      Text(
                        _formatDate(message['created_at']),
                        style: const TextStyle(
                          color: olympusMuted,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 7),
                  Text(
                    _messageBody(message),
                    style: const TextStyle(
                      color: Color(0xFF6A7E94),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            );
          }),
      ],
    );
  }

  Widget _historySection() {
    final evaluations = _periodEvaluations.take(10).toList();

    Color colorForType(String type) {
      final tipo = type.toLowerCase();
      if (tipo == 'destaque') return olympusSuccess;
      if (tipo == 'atencao' || tipo == 'atenção') return olympusWarning;
      if (tipo == 'completa') return olympusGold;
      return olympusBlue;
    }

    return _glassCard(
      children: [
        Row(
          children: [
            Expanded(
                child: _sectionTitle(
                    'Histórico de avaliações', Icons.history_rounded)),
            _infoButton(
              title: 'Histórico de avaliações',
              explanation:
                  'Lista as avaliações registradas no período, incluindo destaques, pontos de atenção e avaliações completas mensais.',
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (evaluations.isEmpty)
          const Text(
            'Nenhuma avaliação registrada neste período.',
            style: TextStyle(
              color: olympusMuted,
              fontWeight: FontWeight.w700,
            ),
          )
        else
          ...evaluations.map((evaluation) {
            final tipo = (evaluation['tipo'] ?? 'avaliação').toString();
            final color = colorForType(tipo);

            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withOpacity(0.07),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: color.withOpacity(0.16)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: color.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          tipo.toUpperCase(),
                          style: TextStyle(
                            color: color,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      const Spacer(),
                      Text(
                        _formatDate(evaluation['created_at']),
                        style: const TextStyle(
                          color: olympusMuted,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if ((evaluation['fundamento'] ?? '')
                      .toString()
                      .trim()
                      .isNotEmpty)
                    Text(
                      'Fundamento: ${(evaluation['fundamento'] ?? '').toString()}',
                      style: const TextStyle(
                        color: olympusBlue,
                        fontWeight: FontWeight.w800,
                        fontSize: 12.5,
                      ),
                    ),
                  if ((evaluation['motivo'] ?? '').toString().trim().isNotEmpty)
                    Text(
                      'Motivo: ${(evaluation['motivo'] ?? '').toString()}',
                      style: const TextStyle(
                        color: olympusMuted,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  if ((evaluation['observacao'] ?? '')
                      .toString()
                      .trim()
                      .isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      (evaluation['observacao'] ?? '').toString(),
                      style: const TextStyle(
                        color: Color(0xFF6A7E94),
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
                  ],
                ],
              ),
            );
          }),
      ],
    );
  }

  List<Map<String, dynamic>> get _championshipGamesWithScout {
    if (!_isChampionshipStatsMode) return const [];

    final eventIds = _periodMatchScouts
        .map((row) => (row['event_id'] ?? '').toString())
        .where((id) => id.isNotEmpty)
        .toSet();

    final byEventId = <String, Map<String, dynamic>>{};

    for (final eventId in eventIds) {
      final convocation = _convocationForChampionshipEventId(eventId);

      if (convocation != null) {
        byEventId[eventId] = convocation;
      } else {
        final scoutRows = _periodMatchScouts
            .where((row) => (row['event_id'] ?? '').toString() == eventId)
            .toList();

        scoutRows.sort((a, b) {
          final aDate = _parseDate(a['updated_at'] ?? a['created_at']);
          final bDate = _parseDate(b['updated_at'] ?? b['created_at']);
          if (aDate == null && bDate == null) return 0;
          if (aDate == null) return 1;
          if (bDate == null) return -1;
          return bDate.compareTo(aDate);
        });

        final firstScout = scoutRows.isNotEmpty ? scoutRows.first : null;

        byEventId[eventId] = {
          'event_id': eventId,
          'event_name':
              'Jogo ${eventId.length > 8 ? eventId.substring(0, 8) : eventId}',
          'event_date': firstScout?['updated_at'] ?? firstScout?['created_at'],
          'created_at': firstScout?['created_at'],
        };
      }
    }

    final games = byEventId.values.toList();

    games.sort((a, b) {
      final dateA = _parseChampionshipGameDate(a);
      final dateB = _parseChampionshipGameDate(b);

      if (dateA == null && dateB == null) {
        return _championshipGameName(a).compareTo(_championshipGameName(b));
      }

      if (dateA == null) return 1;
      if (dateB == null) return -1;

      return dateB.compareTo(dateA);
    });

    return games;
  }

  String _championshipGameId(Map<String, dynamic> row) {
    final directId = (row['id'] ?? '').toString();
    final eventId = (row['event_id'] ?? '').toString();

    if (eventId.isNotEmpty) return eventId;
    return directId;
  }

  Map<String, dynamic>? _embeddedChampionshipEvent(Map<String, dynamic> row) {
    final event = row['events'];
    if (event is Map) {
      return Map<String, dynamic>.from(event);
    }
    return null;
  }

  String _championshipGameName(Map<String, dynamic> row) {
    final event = _embeddedChampionshipEvent(row);

    final eventName = event != null
        ? (event['event_name'] ?? event['championship_name'])
        : (row['event_name'] ?? row['championship_name']);

    final name = (eventName ?? '').toString().trim();
    return name.isEmpty ? 'Jogo' : name;
  }

  Map<String, dynamic>? _convocationForChampionshipEventId(String eventId) {
    if (eventId.isEmpty) return null;

    for (final row in _convocations) {
      if ((row['event_id'] ?? '').toString() == eventId) {
        return row;
      }
    }

    return null;
  }

  bool _matchScoutBelongsToSelectedChampionship(Map<String, dynamic> scout) {
    final selectedName = _selectedChampionshipName;
    if (selectedName == null || selectedName.trim().isEmpty) return true;

    final eventId = (scout['event_id'] ?? '').toString();
    final convocation = _convocationForChampionshipEventId(eventId);

    // Se não houver convocação vinculada no app do atleta, não descarta o scout.
    // O scout é a fonte principal do desempenho em campeonatos.
    if (convocation == null) return true;

    return _championshipNameForRow(convocation) == selectedName;
  }

  String? get _effectiveChampionshipGameId {
    final games = _championshipGamesWithScout;
    if (games.isEmpty) return null;

    final current = _selectedChampionshipGameId;
    if (current != null &&
        games.any((event) => _championshipGameId(event) == current)) {
      return current;
    }

    return _championshipGameId(games.first);
  }

  List<Map<String, dynamic>> get _selectedChampionshipGameScouts {
    final selectedId = _effectiveChampionshipGameId;
    if (selectedId == null || selectedId.isEmpty) return const [];

    return _periodMatchScouts.where((row) {
      return (row['event_id'] ?? '').toString() == selectedId;
    }).toList();
  }

  Map<String, dynamic>? get _selectedChampionshipGame {
    final selectedId = _effectiveChampionshipGameId;
    if (selectedId == null || selectedId.isEmpty) return null;

    for (final event in _championshipGamesWithScout) {
      if (_championshipGameId(event) == selectedId) return event;
    }

    return null;
  }

  DateTime? _parseChampionshipGameDate(Map<String, dynamic> row) {
    final event = _embeddedChampionshipEvent(row);
    final value = event != null
        ? (event['event_date'] ?? event['created_at'])
        : (row['event_date'] ?? row['created_at']);
    final raw = (value ?? '').toString().trim();

    if (raw.isEmpty) return null;

    final iso = DateTime.tryParse(raw);
    if (iso != null) return iso.toLocal();

    try {
      final parts = raw.split('/');
      if (parts.length == 3) {
        return DateTime(
          int.parse(parts[2]),
          int.parse(parts[1]),
          int.parse(parts[0]),
        );
      }
    } catch (_) {}

    return null;
  }

  String _formatChampionshipGameDate(Map<String, dynamic> row) {
    final event = _embeddedChampionshipEvent(row);
    final rawDate = event != null
        ? (event['event_date'] ?? '').toString().trim()
        : (row['event_date'] ?? '').toString().trim();
    final rawTime = event != null
        ? (event['event_time'] ?? '').toString().trim()
        : (row['event_time'] ?? '').toString().trim();

    if (rawDate.isEmpty && rawTime.isEmpty) return 'Data não informada';
    if (rawTime.isEmpty) return rawDate;
    if (rawDate.isEmpty) return rawTime;

    return '$rawDate • $rawTime';
  }

  int _positiveActionsFromScoutRows(List<Map<String, dynamic>> rows) {
    return rows.fold<int>(0, (sum, row) {
      return sum +
          _scoutInt(row, 'saque_ponto') +
          _scoutInt(row, 'recepcao_boa') +
          _scoutInt(row, 'levantamento_bom') +
          _scoutInt(row, 'ataque_ponto') +
          _scoutInt(row, 'bloqueio_ponto') +
          _scoutInt(row, 'defesa_boa');
    });
  }

  int _errorsFromScoutRows(List<Map<String, dynamic>> rows) {
    return rows.fold<int>(0, (sum, row) {
      return sum +
          _scoutInt(row, 'saque_erro') +
          _scoutInt(row, 'recepcao_erro') +
          _scoutInt(row, 'levantamento_erro') +
          _scoutInt(row, 'ataque_erro') +
          _scoutInt(row, 'bloqueio_erro') +
          _scoutInt(row, 'defesa_erro');
    });
  }

  int _efficiencyFromScoutRows(List<Map<String, dynamic>> rows) {
    final positives = _positiveActionsFromScoutRows(rows);
    final errors = _errorsFromScoutRows(rows);
    final total = positives + errors;

    if (total == 0) return 0;

    return ((positives / total) * 100).round().clamp(0, 100);
  }

  int _scoreFromScoutRows(List<Map<String, dynamic>> rows) {
    final positives = _positiveActionsFromScoutRows(rows);
    final errors = _errorsFromScoutRows(rows);
    final total = positives + errors;

    if (total == 0) return 0;

    final base = ((positives / total) * 10).round();
    final bonusVolume = positives >= 10 ? 1 : 0;
    final penalty = errors >= 8 ? 1 : 0;

    return (base + bonusVolume - penalty).clamp(0, 10);
  }

  Map<String, int> _positiveByFundamentFromScoutRows(
    List<Map<String, dynamic>> rows,
  ) {
    final map = <String, int>{
      'Saque': 0,
      'Recepção': 0,
      'Levantamento': 0,
      'Ataque': 0,
      'Bloqueio': 0,
      'Defesa': 0,
    };

    for (final row in rows) {
      map['Saque'] = map['Saque']! + _scoutInt(row, 'saque_ponto');
      map['Recepção'] = map['Recepção']! + _scoutInt(row, 'recepcao_boa');
      map['Levantamento'] =
          map['Levantamento']! + _scoutInt(row, 'levantamento_bom');
      map['Ataque'] = map['Ataque']! + _scoutInt(row, 'ataque_ponto');
      map['Bloqueio'] = map['Bloqueio']! + _scoutInt(row, 'bloqueio_ponto');
      map['Defesa'] = map['Defesa']! + _scoutInt(row, 'defesa_boa');
    }

    map.removeWhere((_, value) => value <= 0);
    return map;
  }

  Map<String, int> _errorsByFundamentFromScoutRows(
    List<Map<String, dynamic>> rows,
  ) {
    final map = <String, int>{
      'Saque': 0,
      'Recepção': 0,
      'Levantamento': 0,
      'Ataque': 0,
      'Bloqueio': 0,
      'Defesa': 0,
    };

    for (final row in rows) {
      map['Saque'] = map['Saque']! + _scoutInt(row, 'saque_erro');
      map['Recepção'] = map['Recepção']! + _scoutInt(row, 'recepcao_erro');
      map['Levantamento'] =
          map['Levantamento']! + _scoutInt(row, 'levantamento_erro');
      map['Ataque'] = map['Ataque']! + _scoutInt(row, 'ataque_erro');
      map['Bloqueio'] = map['Bloqueio']! + _scoutInt(row, 'bloqueio_erro');
      map['Defesa'] = map['Defesa']! + _scoutInt(row, 'defesa_erro');
    }

    map.removeWhere((_, value) => value <= 0);
    return map;
  }

  Widget _championshipProfessionalHero() {
    if (!_isChampionshipStatsMode) return const SizedBox.shrink();

    final positivos = _championshipPositiveActions;
    final erros = _championshipErrors;
    final total = positivos + erros;
    final eficiencia = _championshipEfficiencyPercent;
    final nota = _championshipAutomaticScore;
    final label = _championshipPerformanceLabel;

    Color statusColor;
    IconData statusIcon;

    if (nota >= 8) {
      statusColor = olympusSuccess;
      statusIcon = Icons.trending_up_rounded;
    } else if (nota >= 5) {
      statusColor = olympusWarning;
      statusIcon = Icons.insights_rounded;
    } else if (nota > 0) {
      statusColor = olympusDanger;
      statusIcon = Icons.warning_amber_rounded;
    } else {
      statusColor = olympusMuted;
      statusIcon = Icons.sports_volleyball_rounded;
    }

    Widget compactStat({
      required String label,
      required String value,
      required IconData icon,
      required Color color,
    }) {
      return Expanded(
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: _StatsResponsive.isMobile(context) ? 8 : 12,
            vertical: _StatsResponsive.isMobile(context) ? 10 : 12,
          ),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.11),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withOpacity(0.16)),
          ),
          child: Column(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(height: 7),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: _StatsResponsive.font(context, 17),
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.78),
                  fontSize: _StatsResponsive.font(context, 10.5),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      width: double.infinity,
      margin: EdgeInsets.fromLTRB(
        _StatsResponsive.isDesktop(context)
            ? 48
            : (_StatsResponsive.isTablet(context) ? 28 : 16),
        0,
        _StatsResponsive.isDesktop(context)
            ? 48
            : (_StatsResponsive.isTablet(context) ? 28 : 16),
        _StatsResponsive.space(context, 12),
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        gradient: const LinearGradient(
          colors: [
            Color(0xFF071A30),
            Color(0xFF123861),
            Color(0xFF2C5F8D),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: olympusGold.withOpacity(0.55), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: olympusGold.withOpacity(0.20),
            blurRadius: 24,
            spreadRadius: 1,
            offset: const Offset(0, 10),
          ),
          BoxShadow(
            color: Colors.black.withOpacity(0.20),
            blurRadius: 18,
            offset: const Offset(0, 9),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(30),
        child: Stack(
          children: [
            Positioned(
              top: -46,
              right: -34,
              child: Container(
                width: 148,
                height: 148,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withOpacity(0.07),
                ),
              ),
            ),
            Positioned(
              bottom: -42,
              left: -28,
              child: Container(
                width: 118,
                height: 118,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: olympusGold.withOpacity(0.10),
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.all(
                _StatsResponsive.isMobile(context) ? 16 : 20,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: _StatsResponsive.isMobile(context) ? 54 : 62,
                        height: _StatsResponsive.isMobile(context) ? 54 : 62,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFFF8E08E), Color(0xFFD4AF37)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: olympusGold.withOpacity(0.35),
                              blurRadius: 15,
                              spreadRadius: 1,
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.emoji_events_rounded,
                          color: olympusBlue,
                          size: 32,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Desempenho em campeonatos',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: _StatsResponsive.font(context, 20),
                                fontWeight: FontWeight.w900,
                                height: 1.08,
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              total == 0
                                  ? 'Ainda sem scout por fundamento no período selecionado.'
                                  : '$label • $eficiencia% de eficiência em jogo',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.78),
                                fontSize: _StatsResponsive.font(context, 10.5),
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 11,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: statusColor.withOpacity(0.18),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: statusColor.withOpacity(0.32),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(statusIcon, color: statusColor, size: 16),
                            const SizedBox(width: 5),
                            Text(
                              'Nota $nota',
                              style: TextStyle(
                                color: statusColor,
                                fontSize: _StatsResponsive.font(context, 11),
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      compactStat(
                        label: 'Ações',
                        value: '$positivos',
                        icon: Icons.check_circle_rounded,
                        color: olympusSuccess,
                      ),
                      const SizedBox(width: 8),
                      compactStat(
                        label: 'Erros',
                        value: '$erros',
                        icon: Icons.cancel_rounded,
                        color: olympusDanger,
                      ),
                      const SizedBox(width: 8),
                      compactStat(
                        label: 'Eficiência',
                        value: '$eficiencia%',
                        icon: Icons.insights_rounded,
                        color: olympusGold,
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      compactStat(
                        label: 'Jogos',
                        value: '$_championshipEvaluatedMatchesCount',
                        icon: Icons.sports_score_rounded,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 8),
                      compactStat(
                        label: 'Sets',
                        value: '$_championshipEvaluatedSetsCount',
                        icon: Icons.view_week_rounded,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 8),
                      compactStat(
                        label: 'Ações totais',
                        value: '$total',
                        icon: Icons.timeline_rounded,
                        color: Colors.white,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _championshipProfessionalBreakdown() {
    if (!_isChampionshipStatsMode) return const SizedBox.shrink();

    final positives = _championshipPositiveByFundament.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final errors = _championshipErrorsByFundament.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    Widget panel({
      required String title,
      required String subtitle,
      required IconData icon,
      required Color color,
      required List<MapEntry<String, int>> entries,
      required String emptyText,
    }) {
      return Expanded(
        child: Container(
          padding: EdgeInsets.all(
            _StatsResponsive.isMobile(context) ? 10 : 12,
          ),
          decoration: BoxDecoration(
            color: color.withOpacity(0.08),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: color.withOpacity(0.14)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, color: color, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        color: color,
                        fontSize: _StatsResponsive.font(context, 12.5),
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                style: TextStyle(
                  color: olympusMuted,
                  fontSize: _StatsResponsive.font(context, 10.5),
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 9),
              if (entries.isEmpty)
                Text(
                  emptyText,
                  style: TextStyle(
                    color: olympusMuted,
                    fontSize: _StatsResponsive.font(context, 12),
                    fontWeight: FontWeight.w700,
                  ),
                )
              else
                ...entries.take(4).map((entry) {
                  final maxValue =
                      entries.first.value <= 0 ? 1 : entries.first.value;
                  final progress = (entry.value / maxValue).clamp(0.0, 1.0);

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 7),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                entry.key,
                                style: TextStyle(
                                  color: olympusBlue,
                                  fontSize: _StatsResponsive.font(context, 11),
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                            Text(
                              '${entry.value}',
                              style: TextStyle(
                                color: color,
                                fontSize: _StatsResponsive.font(context, 12.5),
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(999),
                          child: LinearProgressIndicator(
                            value: progress,
                            minHeight: 6,
                            backgroundColor: Colors.white.withOpacity(0.70),
                            valueColor: AlwaysStoppedAnimation<Color>(color),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
            ],
          ),
        ),
      );
    }

    return Container(
      width: double.infinity,
      margin: EdgeInsets.fromLTRB(
        _StatsResponsive.isDesktop(context)
            ? 48
            : (_StatsResponsive.isTablet(context) ? 28 : 16),
        0,
        _StatsResponsive.isDesktop(context)
            ? 48
            : (_StatsResponsive.isTablet(context) ? 28 : 16),
        _StatsResponsive.space(context, 12),
      ),
      padding: EdgeInsets.all(_StatsResponsive.isMobile(context) ? 10 : 12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.96),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: olympusBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < 380;

          final strongPanel = panel(
            title: 'Fortes',
            subtitle: 'Ações positivas por fundamento.',
            icon: Icons.trending_up_rounded,
            color: olympusSuccess,
            entries: positives,
            emptyText: 'Sem ações positivas registradas.',
          );

          final errorPanel = panel(
            title: 'Ajustar',
            subtitle: 'Erros por fundamento.',
            icon: Icons.warning_amber_rounded,
            color: olympusDanger,
            entries: errors,
            emptyText: 'Sem erros registrados.',
          );

          if (narrow) {
            return Column(
              children: [
                Row(children: [strongPanel]),
                const SizedBox(height: 12),
                Row(children: [errorPanel]),
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              strongPanel,
              const SizedBox(width: 12),
              errorPanel,
            ],
          );
        },
      ),
    );
  }

  Widget _championshipProfessionalSummary() {
    if (!_isChampionshipStatsMode) return const SizedBox.shrink();

    final efficiency = _championshipEfficiencyPercent;
    final strong = _championshipStrongestFundament;
    final critical = _championshipCriticalFundament;
    final actions = _championshipPositiveActions;
    final errors = _championshipErrors;
    final total = actions + errors;

    String recommendation;
    IconData recommendationIcon;
    Color recommendationColor;

    if (total == 0) {
      recommendation =
          'Quando houver scout no jogo, esta área mostrará a leitura automática do desempenho.';
      recommendationIcon = Icons.info_outline_rounded;
      recommendationColor = olympusMuted;
    } else if (efficiency >= 75) {
      recommendation =
          'Alto impacto nos campeonatos. Manter volume de jogo e usar os fundamentos fortes como referência.';
      recommendationIcon = Icons.verified_rounded;
      recommendationColor = olympusSuccess;
    } else if (efficiency >= 55) {
      recommendation =
          'Desempenho competitivo, mas ainda com margem de ajuste nos fundamentos críticos.';
      recommendationIcon = Icons.insights_rounded;
      recommendationColor = olympusWarning;
    } else {
      recommendation =
          'Priorizar correção técnica e tomada de decisão no próximo ciclo de treino.';
      recommendationIcon = Icons.priority_high_rounded;
      recommendationColor = olympusDanger;
    }

    return Container(
      width: double.infinity,
      margin: EdgeInsets.fromLTRB(
        _StatsResponsive.isDesktop(context)
            ? 48
            : (_StatsResponsive.isTablet(context) ? 28 : 16),
        0,
        _StatsResponsive.isDesktop(context)
            ? 48
            : (_StatsResponsive.isTablet(context) ? 28 : 16),
        _StatsResponsive.space(context, 12),
      ),
      padding: EdgeInsets.all(_StatsResponsive.isMobile(context) ? 14 : 16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.96),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: olympusBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.psychology_alt_rounded, color: olympusGold),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Leitura técnica automática',
                  style: TextStyle(
                    color: olympusBlue,
                    fontSize: _StatsResponsive.font(context, 17),
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 13),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              color: recommendationColor.withOpacity(0.09),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: recommendationColor.withOpacity(0.18)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(recommendationIcon, color: recommendationColor, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    recommendation,
                    style: TextStyle(
                      color: recommendationColor,
                      fontSize: _StatsResponsive.font(context, 12.5),
                      fontWeight: FontWeight.w800,
                      height: 1.32,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final narrow = constraints.maxWidth < 520;

              Widget tag({
                required String label,
                required String value,
                required IconData icon,
                required Color color,
              }) {
                return Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: color.withOpacity(0.16)),
                  ),
                  child: Row(
                    children: [
                      Icon(icon, color: color, size: 20),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              label,
                              style: TextStyle(
                                color: color,
                                fontSize: _StatsResponsive.font(context, 10.8),
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              value,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: olympusBlue,
                                fontSize: _StatsResponsive.font(context, 11.5),
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }

              final items = [
                tag(
                  label: 'Mais forte',
                  value: strong,
                  icon: Icons.flash_on_rounded,
                  color: olympusSuccess,
                ),
                tag(
                  label: 'Ajustar',
                  value: critical,
                  icon: Icons.build_circle_outlined,
                  color: olympusDanger,
                ),
              ];

              if (narrow) {
                return Column(
                  children: [
                    SizedBox(width: double.infinity, child: items[0]),
                    const SizedBox(height: 10),
                    SizedBox(width: double.infinity, child: items[1]),
                  ],
                );
              }

              return Row(
                children: [
                  Expanded(child: items[0]),
                  const SizedBox(width: 10),
                  Expanded(child: items[1]),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _championshipGamesSection() {
    if (!_isChampionshipStatsMode) return const SizedBox.shrink();

    final games = _championshipGamesWithScout;
    if (games.isEmpty) return const SizedBox.shrink();

    final selectedGame = _selectedChampionshipGame;
    final selectedRows = _selectedChampionshipGameScouts;
    final positives = _positiveActionsFromScoutRows(selectedRows);
    final errors = _errorsFromScoutRows(selectedRows);
    final total = positives + errors;
    final efficiency = _efficiencyFromScoutRows(selectedRows);
    final score = _scoreFromScoutRows(selectedRows);
    final positiveFundaments = _positiveByFundamentFromScoutRows(selectedRows)
        .entries
        .toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final errorFundaments = _errorsByFundamentFromScoutRows(selectedRows)
        .entries
        .toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    Widget gameChip(Map<String, dynamic> game) {
      final id = _championshipGameId(game);
      final selected = id == _effectiveChampionshipGameId;
      final name = _championshipGameName(game);

      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(
          selected: selected,
          showCheckmark: false,
          selectedColor: olympusGold,
          backgroundColor: olympusBg,
          side: BorderSide(
            color: selected ? olympusGold : olympusBorder,
          ),
          label: Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          labelStyle: TextStyle(
            color: selected ? olympusBlue : olympusMuted,
            fontWeight: FontWeight.w900,
            fontSize: _StatsResponsive.font(context, 12),
          ),
          onSelected: (_) {
            setState(() {
              _selectedChampionshipGameId = id;
            });
          },
        ),
      );
    }

    Widget stat({
      required String label,
      required String value,
      required IconData icon,
      required Color color,
    }) {
      return Expanded(
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: _StatsResponsive.isMobile(context) ? 8 : 10,
            vertical: _StatsResponsive.isMobile(context) ? 10 : 12,
          ),
          decoration: BoxDecoration(
            color: color.withOpacity(0.08),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: color.withOpacity(0.17)),
          ),
          child: Column(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(height: 7),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: color,
                  fontSize: _StatsResponsive.font(context, 17),
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: color,
                  fontSize: _StatsResponsive.font(context, 10.5),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      );
    }

    Widget fundamentList({
      required String title,
      required List<MapEntry<String, int>> entries,
      required Color color,
      required String empty,
    }) {
      return Expanded(
        child: Container(
          padding: EdgeInsets.all(_StatsResponsive.isMobile(context) ? 12 : 14),
          decoration: BoxDecoration(
            color: color.withOpacity(0.07),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withOpacity(0.13)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: color,
                  fontSize: _StatsResponsive.font(context, 13),
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 7),
              if (entries.isEmpty)
                Text(
                  empty,
                  style: TextStyle(
                    color: olympusMuted,
                    fontSize: _StatsResponsive.font(context, 12),
                    fontWeight: FontWeight.w700,
                  ),
                )
              else
                ...entries.take(5).map((entry) {
                  final maxValue =
                      entries.first.value <= 0 ? 1 : entries.first.value;
                  final progress = (entry.value / maxValue).clamp(0.0, 1.0);

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                entry.key,
                                style: TextStyle(
                                  color: olympusBlue,
                                  fontSize: _StatsResponsive.font(context, 12),
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                            Text(
                              '${entry.value}',
                              style: TextStyle(
                                color: color,
                                fontSize: _StatsResponsive.font(context, 12),
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(999),
                          child: LinearProgressIndicator(
                            value: progress,
                            minHeight: 7,
                            backgroundColor: Colors.white.withOpacity(0.70),
                            valueColor: AlwaysStoppedAnimation<Color>(color),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
            ],
          ),
        ),
      );
    }

    return Container(
      width: double.infinity,
      margin: EdgeInsets.fromLTRB(
        _StatsResponsive.isDesktop(context)
            ? 48
            : (_StatsResponsive.isTablet(context) ? 28 : 16),
        0,
        _StatsResponsive.isDesktop(context)
            ? 48
            : (_StatsResponsive.isTablet(context) ? 28 : 16),
        _StatsResponsive.space(context, 12),
      ),
      padding: EdgeInsets.all(_StatsResponsive.isMobile(context) ? 14 : 16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.96),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: olympusBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
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
              const Icon(Icons.sports_score_rounded, color: olympusGold),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Jogos avaliados',
                  style: TextStyle(
                    color: olympusBlue,
                    fontSize: _StatsResponsive.font(context, 17),
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: olympusBlue.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: olympusBlue.withOpacity(0.12)),
                ),
                child: Text(
                  '${games.length} jogo(s)',
                  style: TextStyle(
                    color: olympusBlue,
                    fontSize: _StatsResponsive.font(context, 11),
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 42,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: games.map(gameChip).toList(),
            ),
          ),
          const SizedBox(height: 14),
          if (selectedGame != null) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    olympusBlue.withOpacity(0.08),
                    olympusLightBlue.withOpacity(0.04),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: olympusBlue.withOpacity(0.12)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: olympusGold.withOpacity(0.16),
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: const Icon(
                      Icons.emoji_events_rounded,
                      color: olympusBlue,
                      size: 23,
                    ),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _championshipGameName(selectedGame),
                          style: TextStyle(
                            color: olympusBlue,
                            fontSize: _StatsResponsive.font(context, 14),
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          _formatChampionshipGameDate(selectedGame),
                          style: TextStyle(
                            color: olympusMuted,
                            fontSize: _StatsResponsive.font(context, 11.5),
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
          Row(
            children: [
              stat(
                label: 'Ações',
                value: '$positives',
                icon: Icons.check_circle_rounded,
                color: olympusSuccess,
              ),
              const SizedBox(width: 8),
              stat(
                label: 'Erros',
                value: '$errors',
                icon: Icons.cancel_rounded,
                color: olympusDanger,
              ),
              const SizedBox(width: 8),
              stat(
                label: 'Nota',
                value: '$score',
                icon: Icons.star_rounded,
                color: olympusGold,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              stat(
                label: 'Eficiência',
                value: '$efficiency%',
                icon: Icons.insights_rounded,
                color: olympusBlue,
              ),
              const SizedBox(width: 8),
              stat(
                label: 'Sets',
                value: '${selectedRows.length}',
                icon: Icons.view_week_rounded,
                color: olympusPurple,
              ),
              const SizedBox(width: 8),
              stat(
                label: 'Total',
                value: '$total',
                icon: Icons.timeline_rounded,
                color: olympusMuted,
              ),
            ],
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final narrow = constraints.maxWidth < 380;

              final positivesList = fundamentList(
                title: 'Ações por fundamento',
                entries: positiveFundaments,
                color: olympusSuccess,
                empty: 'Sem ações positivas neste jogo.',
              );

              final errorsList = fundamentList(
                title: 'Erros por fundamento',
                entries: errorFundaments,
                color: olympusDanger,
                empty: 'Sem erros neste jogo.',
              );

              if (narrow) {
                return Column(
                  children: [
                    Row(children: [positivesList]),
                    const SizedBox(height: 12),
                    Row(children: [errorsList]),
                  ],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  positivesList,
                  const SizedBox(width: 12),
                  errorsList,
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _championshipActionDetailsSection() {
    if (!_isChampionshipStatsMode) return const SizedBox.shrink();

    final rows = _selectedChampionshipGameActionDetails.isNotEmpty
        ? _selectedChampionshipGameActionDetails
        : _periodMatchScoutActionDetails;

    if (rows.isEmpty) return const SizedBox.shrink();

    final positives = _detailsCountBySubtype(rows: rows, result: 'acerto')
        .entries
        .toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final errors = _detailsCountBySubtype(rows: rows, result: 'erro')
        .entries
        .toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final impact = _detailsWeightSum(rows);

    Widget listBlock({
      required String title,
      required List<MapEntry<String, int>> entries,
      required Color color,
      required IconData icon,
      required String empty,
    }) {
      return Expanded(
        child: Container(
          padding: EdgeInsets.all(_StatsResponsive.isMobile(context) ? 12 : 14),
          decoration: BoxDecoration(
            color: color.withOpacity(0.07),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: color.withOpacity(0.16)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, color: color, size: 17),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        color: color,
                        fontSize: _StatsResponsive.font(context, 13),
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (entries.isEmpty)
                Text(
                  empty,
                  style: TextStyle(
                    color: olympusMuted,
                    fontSize: _StatsResponsive.font(context, 12),
                    fontWeight: FontWeight.w700,
                  ),
                )
              else
                ...entries.take(4).map((entry) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            entry.key,
                            style: TextStyle(
                              color: olympusBlue,
                              fontSize: _StatsResponsive.font(context, 12),
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: color.withOpacity(0.13),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            '${entry.value}',
                            style: TextStyle(
                              color: color,
                              fontSize: _StatsResponsive.font(context, 11),
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
            ],
          ),
        ),
      );
    }

    return Container(
      width: double.infinity,
      margin: EdgeInsets.fromLTRB(
        _StatsResponsive.isDesktop(context)
            ? 48
            : (_StatsResponsive.isTablet(context) ? 28 : 16),
        0,
        _StatsResponsive.isDesktop(context)
            ? 48
            : (_StatsResponsive.isTablet(context) ? 28 : 16),
        _StatsResponsive.space(context, 12),
      ),
      padding: EdgeInsets.all(_StatsResponsive.isMobile(context) ? 14 : 16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.96),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: olympusBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 12,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.fact_check_rounded, color: olympusGold),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Detalhamento técnico',
                  style: TextStyle(
                    color: olympusBlue,
                    fontSize: _StatsResponsive.font(context, 17),
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: (impact >= 0 ? olympusSuccess : olympusDanger)
                      .withOpacity(0.10),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: (impact >= 0 ? olympusSuccess : olympusDanger)
                        .withOpacity(0.18),
                  ),
                ),
                child: Text(
                  'Impacto ${impact >= 0 ? '+' : ''}$impact',
                  style: TextStyle(
                    color: impact >= 0 ? olympusSuccess : olympusDanger,
                    fontSize: _StatsResponsive.font(context, 11),
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          Text(
            'Subtipos lançados pelo técnico.',
            style: TextStyle(
              color: olympusMuted,
              fontSize: _StatsResponsive.font(context, 12),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 13),
          LayoutBuilder(
            builder: (context, constraints) {
              final narrow = constraints.maxWidth < 620;

              final positiveBlock = listBlock(
                title: 'Acertos',
                entries: positives,
                color: olympusSuccess,
                icon: Icons.check_circle_rounded,
                empty: 'Sem acertos detalhados.',
              );

              final errorBlock = listBlock(
                title: 'Erros',
                entries: errors,
                color: olympusDanger,
                icon: Icons.cancel_rounded,
                empty: 'Sem erros detalhados.',
              );

              if (narrow) {
                return Column(
                  children: [
                    Row(children: [positiveBlock]),
                    const SizedBox(height: 12),
                    Row(children: [errorBlock]),
                  ],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  positiveBlock,
                  const SizedBox(width: 12),
                  errorBlock,
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: olympusBg,
      appBar: AppBar(
        title: const Text('Estatísticas do Atleta'),
        backgroundColor: olympusBlue,
        foregroundColor: Colors.white,
        leading: IconButton(
          tooltip: 'Voltar para o Dashboard',
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: _goBackToDashboard,
        ),
        actions: [
          IconButton(
            tooltip: 'Atualizar',
            onPressed: _loadData,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragEnd: (details) {
          final velocity = details.primaryVelocity ?? 0;
          if (velocity > 320) {
            _goBackToDashboard();
          }
        },
        child: Stack(
          children: [
            Positioned.fill(child: _background()),
            if (_loading)
              const Center(
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            else if (_error != null)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(22),
                  child: Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              )
            else
              RefreshIndicator(
                onRefresh: _loadData,
                child: ListView(
                  controller: _scrollController,
                  physics: const BouncingScrollPhysics(
                    parent: AlwaysScrollableScrollPhysics(),
                  ),
                  padding: const EdgeInsets.only(bottom: 28),
                  children: [
                    _header(),
                    if (_isChampionshipStatsMode)
                      _championshipProfessionalHero(),
                    if (_isChampionshipStatsMode)
                      _championshipProfessionalSummary(),
                    if (_isChampionshipStatsMode) _championshipGamesSection(),
                    if (_isChampionshipStatsMode)
                      _championshipActionDetailsSection(),
                    if (_isChampionshipStatsMode)
                      _championshipProfessionalBreakdown(),
                    if (!_isChampionshipStatsMode) _scoreHeroCard(),
                    if (_statsMode == 'treino') _trainingPlanPieChartAthlete(),
                    _metricsGrid(),
                    const SizedBox(height: 12),
                    _evolutionChart(),
                    _fundamentsSection(),
                    _historySection(),
                    _insightsSection(),
                    _messagesSection(),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _BlinkingMetricValue extends StatefulWidget {
  const _BlinkingMetricValue({
    required this.text,
    required this.color,
  });

  final String text;
  final Color color;

  @override
  State<_BlinkingMetricValue> createState() => _BlinkingMetricValueState();
}

class _BlinkingMetricValueState extends State<_BlinkingMetricValue>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);

    _opacity = Tween<double>(begin: 0.45, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: Text(
        widget.text,
        style: TextStyle(
          color: widget.color,
          fontSize: _StatsResponsive.font(context, 23),
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _TrainingPlanPiePainter extends CustomPainter {
  _TrainingPlanPiePainter({
    required this.data,
    required this.colors,
    required this.totalMinutes,
    required this.centerText,
    required this.mutedColor,
    required this.titleColor,
  });

  final Map<String, int> data;
  final Map<String, Color> colors;
  final int totalMinutes;
  final String centerText;
  final Color mutedColor;
  final Color titleColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    final center = Offset(size.width * 0.31, size.height / 2);
    final radius = math.min(size.height * 0.32, size.width * 0.20);

    final basePaint = Paint()
      ..color = const Color(0xFFE4EDF5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 22
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, radius, basePaint);

    final categories = ['Fundamentos', 'Tático', 'Físico'];
    double startAngle = -math.pi / 2;

    final arcPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 22
      ..strokeCap = StrokeCap.round;

    if (totalMinutes > 0) {
      for (final category in categories) {
        final value = data[category] ?? 0;
        if (value <= 0) continue;

        final sweep = (value / totalMinutes) * math.pi * 2;
        arcPaint.color = colors[category] ?? titleColor;

        canvas.drawArc(
          Rect.fromCircle(center: center, radius: radius),
          startAngle,
          sweep,
          false,
          arcPaint,
        );

        startAngle += sweep;
      }
    }

    canvas.drawCircle(
      center,
      radius - 22,
      Paint()..color = Colors.white.withOpacity(0.94),
    );

    final titlePainter = TextPainter(
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
      text: TextSpan(
        text: 'Total',
        style: TextStyle(
          color: mutedColor,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    )..layout(maxWidth: radius * 1.7);

    titlePainter.paint(
      canvas,
      Offset(center.dx - titlePainter.width / 2, center.dy - 21),
    );

    final totalPainter = TextPainter(
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
      text: TextSpan(
        text: centerText,
        style: TextStyle(
          color: titleColor,
          fontSize: 16,
          fontWeight: FontWeight.w900,
        ),
      ),
    )..layout(maxWidth: radius * 1.9);

    totalPainter.paint(
      canvas,
      Offset(center.dx - totalPainter.width / 2, center.dy - 2),
    );

    final legendX = size.width * 0.58;
    double legendY = size.height * 0.20;

    for (final category in categories) {
      final value = data[category] ?? 0;
      final percent =
          totalMinutes <= 0 ? 0 : (value / totalMinutes * 100).round();
      final color = colors[category] ?? titleColor;

      canvas.drawCircle(
        Offset(legendX, legendY + 7),
        5,
        Paint()..color = color,
      );

      final legendPainter = TextPainter(
        textDirection: TextDirection.ltr,
        text: TextSpan(
          children: [
            TextSpan(
              text: '$category\n',
              style: TextStyle(
                color: titleColor,
                fontSize: 12,
                fontWeight: FontWeight.w900,
                height: 1.2,
              ),
            ),
            TextSpan(
              text: '$value min • $percent%',
              style: TextStyle(
                color: mutedColor,
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                height: 1.25,
              ),
            ),
          ],
        ),
      )..layout(maxWidth: size.width - legendX - 8);

      legendPainter.paint(canvas, Offset(legendX + 12, legendY));
      legendY += 42;
    }
  }

  @override
  bool shouldRepaint(covariant _TrainingPlanPiePainter oldDelegate) {
    return oldDelegate.data != data ||
        oldDelegate.totalMinutes != totalMinutes ||
        oldDelegate.centerText != centerText ||
        oldDelegate.colors != colors;
  }
}

class _MonthlyPresenceAbsence {
  const _MonthlyPresenceAbsence({
    required this.month,
    required this.presences,
    required this.absences,
  });

  final int month;
  final int presences;
  final int absences;
}

class _AnnualPresenceAbsencePainter extends CustomPainter {
  _AnnualPresenceAbsencePainter({
    required this.data,
    required this.presenceColor,
    required this.absenceColor,
    required this.gridColor,
    required this.labelColor,
    this.selectedMonth,
    this.selectedColor,
    this.showAbsences = true,
  });

  final List<_MonthlyPresenceAbsence> data;
  final Color presenceColor;
  final Color absenceColor;
  final Color gridColor;
  final Color labelColor;
  final int? selectedMonth;
  final Color? selectedColor;
  final bool showAbsences;

  static const List<String> _monthLabels = [
    '',
    'Jan',
    'Fev',
    'Mar',
    'Abr',
    'Mai',
    'Jun',
    'Jul',
    'Ago',
    'Set',
    'Out',
    'Nov',
    'Dez',
  ];

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty || size.width <= 0 || size.height <= 0) return;

    final padding = EdgeInsets.fromLTRB(
      size.width < 360 ? 30 : 34,
      18,
      12,
      34,
    );

    final chartWidth = size.width - padding.left - padding.right;
    final chartHeight = size.height - padding.top - padding.bottom;

    if (chartWidth <= 0 || chartHeight <= 0) return;

    final maxPresence = data.map((e) => e.presences).fold<int>(0, math.max);
    final maxAbsence =
        showAbsences ? data.map((e) => e.absences).fold<int>(0, math.max) : 0;
    final maxValue = math.max(1, math.max(maxPresence, maxAbsence));

    final textPainter = TextPainter(textDirection: TextDirection.ltr);

    final axisPaint = Paint()
      ..color = gridColor.withOpacity(0.72)
      ..strokeWidth = 1;

    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;

    for (int i = 0; i <= 4; i++) {
      final y = padding.top + chartHeight * (i / 4);
      canvas.drawLine(
        Offset(padding.left, y),
        Offset(padding.left + chartWidth, y),
        gridPaint,
      );

      final value = (maxValue - (maxValue * i / 4)).round();
      textPainter.text = TextSpan(
        text: value.toString(),
        style: TextStyle(
          color: labelColor,
          fontSize: 10,
          fontWeight: FontWeight.w800,
        ),
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(padding.left - textPainter.width - 8, y - 6),
      );
    }

    canvas.drawLine(
      Offset(padding.left, padding.top),
      Offset(padding.left, padding.top + chartHeight),
      axisPaint,
    );

    canvas.drawLine(
      Offset(padding.left, padding.top + chartHeight),
      Offset(padding.left + chartWidth, padding.top + chartHeight),
      axisPaint,
    );

    final monthSlot = chartWidth / data.length;
    final barWidth = math.min(18.0, math.max(7.0, monthSlot * 0.26));
    final gap = showAbsences ? math.max(2.0, monthSlot * 0.08) : 0.0;
    final radius = Radius.circular(math.min(5.0, barWidth / 2));

    if (selectedMonth != null && selectedMonth! >= 1 && selectedMonth! <= 12) {
      final selectedIndex = selectedMonth! - 1;
      final selectedCenterX = padding.left + (selectedIndex + 0.5) * monthSlot;
      final highlightWidth = math.max(24.0, monthSlot * 0.78);

      final highlightRect = Rect.fromLTWH(
        selectedCenterX - highlightWidth / 2,
        padding.top - 4,
        highlightWidth,
        chartHeight + 10,
      );

      canvas.drawRRect(
        RRect.fromRectAndRadius(highlightRect, const Radius.circular(12)),
        Paint()..color = (selectedColor ?? Colors.white).withOpacity(0.10),
      );

      canvas.drawLine(
        Offset(selectedCenterX, padding.top),
        Offset(selectedCenterX, padding.top + chartHeight),
        Paint()
          ..color = (selectedColor ?? Colors.white).withOpacity(0.42)
          ..strokeWidth = 1.2,
      );
    }

    void drawValueLabel({
      required int value,
      required double x,
      required double topY,
      required Color color,
    }) {
      if (value <= 0) return;

      textPainter.text = TextSpan(
        text: value.toString(),
        style: TextStyle(
          color: color,
          fontSize: 9,
          fontWeight: FontWeight.w900,
        ),
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(x - textPainter.width / 2, topY - 13),
      );
    }

    for (int i = 0; i < data.length; i++) {
      final item = data[i];
      final centerX = padding.left + (i + 0.5) * monthSlot;
      final baseY = padding.top + chartHeight;

      final presenceHeight = item.presences <= 0
          ? 0.0
          : math.max(4.0, (item.presences / maxValue) * chartHeight);
      final absenceHeight = item.absences <= 0
          ? 0.0
          : math.max(4.0, (item.absences / maxValue) * chartHeight);

      final presenceLeft =
          showAbsences ? centerX - barWidth - gap / 2 : centerX - barWidth / 2;
      final absenceLeft = centerX + gap / 2;

      final presenceRect = Rect.fromLTWH(
        presenceLeft,
        baseY - presenceHeight,
        barWidth,
        presenceHeight,
      );
      final absenceRect = Rect.fromLTWH(
        absenceLeft,
        baseY - absenceHeight,
        barWidth,
        absenceHeight,
      );

      if (presenceHeight > 0) {
        canvas.drawRRect(
          RRect.fromRectAndCorners(
            presenceRect,
            topLeft: radius,
            topRight: radius,
          ),
          Paint()..color = presenceColor,
        );
        canvas.drawRRect(
          RRect.fromRectAndCorners(
            presenceRect.inflate(2),
            topLeft: radius,
            topRight: radius,
          ),
          Paint()
            ..color = presenceColor.withOpacity(0.18)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
        );
        drawValueLabel(
          value: item.presences,
          x: presenceRect.center.dx,
          topY: presenceRect.top,
          color: presenceColor,
        );
      }

      if (showAbsences && absenceHeight > 0) {
        canvas.drawRRect(
          RRect.fromRectAndCorners(
            absenceRect,
            topLeft: radius,
            topRight: radius,
          ),
          Paint()..color = absenceColor,
        );
        canvas.drawRRect(
          RRect.fromRectAndCorners(
            absenceRect.inflate(2),
            topLeft: radius,
            topRight: radius,
          ),
          Paint()
            ..color = absenceColor.withOpacity(0.18)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
        );
        drawValueLabel(
          value: item.absences,
          x: absenceRect.center.dx,
          topY: absenceRect.top,
          color: absenceColor,
        );
      }

      final label = _monthLabels[item.month];
      final isSelected = selectedMonth == item.month;
      textPainter.text = TextSpan(
        text: label,
        style: TextStyle(
          color: isSelected ? (selectedColor ?? Colors.white) : labelColor,
          fontSize: 10,
          fontWeight: isSelected ? FontWeight.w900 : FontWeight.w800,
        ),
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(centerX - textPainter.width / 2, baseY + 10),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _AnnualPresenceAbsencePainter oldDelegate) {
    return oldDelegate.data != data ||
        oldDelegate.presenceColor != presenceColor ||
        oldDelegate.absenceColor != absenceColor ||
        oldDelegate.gridColor != gridColor ||
        oldDelegate.labelColor != labelColor ||
        oldDelegate.selectedMonth != selectedMonth ||
        oldDelegate.selectedColor != selectedColor ||
        oldDelegate.showAbsences != showAbsences;
  }
}

class _TrendPoint {
  _TrendPoint(this.date, this.value);

  final DateTime date;
  final int value;
}

class _AthleteTrendPainter extends CustomPainter {
  _AthleteTrendPainter({
    required this.points,
    required this.lineColor,
    required this.fillColor,
  });

  final List<_TrendPoint> points;
  final Color lineColor;
  final Color fillColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty || size.width <= 0 || size.height <= 0) return;

    final padding = const EdgeInsets.fromLTRB(28, 12, 12, 28);
    final chartWidth = size.width - padding.left - padding.right;
    final chartHeight = size.height - padding.top - padding.bottom;

    final values = points.map((e) => e.value).toList();
    final minValue = values.reduce(math.min);
    final maxValue = values.reduce(math.max);
    final range = math.max(1, maxValue - minValue);

    final gridPaint = Paint()
      ..color = const Color(0xFFE4EDF5).withOpacity(0.72)
      ..strokeWidth = 1;

    for (int i = 0; i <= 3; i++) {
      final y = padding.top + chartHeight * (i / 3);
      canvas.drawLine(
        Offset(padding.left, y),
        Offset(padding.left + chartWidth, y),
        gridPaint,
      );
    }

    final chartPoints = <Offset>[];

    for (int i = 0; i < points.length; i++) {
      final x = points.length == 1
          ? padding.left + chartWidth / 2
          : padding.left + chartWidth * (i / (points.length - 1));

      final normalized = (points[i].value - minValue) / range;
      final y = padding.top + chartHeight - (normalized * chartHeight);

      chartPoints.add(Offset(x, y));
    }

    if (chartPoints.length == 1) {
      final dotPaint = Paint()..color = lineColor;
      canvas.drawCircle(chartPoints.first, 4, dotPaint);
      return;
    }

    final linePath = Path()..moveTo(chartPoints.first.dx, chartPoints.first.dy);
    for (final point in chartPoints.skip(1)) {
      linePath.lineTo(point.dx, point.dy);
    }

    final fillPath = Path.from(linePath)
      ..lineTo(chartPoints.last.dx, padding.top + chartHeight)
      ..lineTo(chartPoints.first.dx, padding.top + chartHeight)
      ..close();

    canvas.drawPath(fillPath, Paint()..color = fillColor);

    final linePaint = Paint()
      ..color = lineColor
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    canvas.drawPath(linePath, linePaint);

    final dotPaint = Paint()..color = lineColor;
    final dotBorderPaint = Paint()..color = Colors.white;

    for (final point in chartPoints) {
      canvas.drawCircle(point, 5, dotBorderPaint);
      canvas.drawCircle(point, 3.5, dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _AthleteTrendPainter oldDelegate) {
    return oldDelegate.points != points ||
        oldDelegate.lineColor != lineColor ||
        oldDelegate.fillColor != fillColor;
  }
}
