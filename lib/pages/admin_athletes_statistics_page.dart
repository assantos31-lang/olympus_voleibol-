import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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

class AthleteStatisticsPage extends StatefulWidget {
  final String? athleteId;
  final bool adminView;

  const AthleteStatisticsPage({
    super.key,
    this.athleteId,
    this.adminView = false,
  });

  static const String heroTag = 'athlete-statistics-hero';

  static Route<void> route({
    String? athleteId,
    bool adminView = false,
  }) {
    return PageRouteBuilder<void>(
      transitionDuration: const Duration(milliseconds: 420),
      reverseTransitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (context, animation, secondaryAnimation) {
        return AthleteStatisticsPage(
          athleteId: athleteId,
          adminView: adminView,
        );
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
  State<AthleteStatisticsPage> createState() => _AthleteStatisticsPageState();
}

class _AthleteStatisticsPageState extends State<AthleteStatisticsPage> {
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
  Map<String, Map<String, dynamic>> _eventsById = {};
  List<Map<String, dynamic>> _trainingPlanBlocks = [];

  String _period = 'mes';
  int? _selectedAnnualMonth;

  final ScrollController _scrollController = ScrollController();
  double _scrollOffset = 0;

  @override
  void initState() {
    super.initState();
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
      widget.adminView ? '/admin-dashboard' : '/athlete-dashboard',
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

    // ✅ IMPORTANTE:
    // A tabela `checkins` representa presença.
    // Alguns check-ins antigos/atrasados podem ter sido gravados sem
    // `check_in_status` ou com variações de texto. Para não manter falta
    // indevidamente, qualquer linha existente em `checkins` sem status de
    // erro/cancelamento também conta como presença.
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

  String _normalizeEvaluationText(dynamic value) {
    final raw = (value ?? '').toString().trim().toLowerCase();

    if (raw.isEmpty) return '';

    return raw
        .replaceAll('ç', 'c')
        .replaceAll('ã', 'a')
        .replaceAll('á', 'a')
        .replaceAll('à', 'a')
        .replaceAll('â', 'a')
        .replaceAll('é', 'e')
        .replaceAll('ê', 'e')
        .replaceAll('í', 'i')
        .replaceAll('ó', 'o')
        .replaceAll('ô', 'o')
        .replaceAll('õ', 'o')
        .replaceAll('ú', 'u');
  }

  String _evaluationSearchText(Map<String, dynamic> row) {
    return [
      row['tipo'],
      row['slot'],
      row['motivo'],
      row['fundamento'],
      row['observacao'],
    ]
        .map(_normalizeEvaluationText)
        .where((value) => value.isNotEmpty)
        .join(' ');
  }

  bool _isDestaqueEvaluation(Map<String, dynamic> row) {
    final tipo = _normalizeEvaluationText(row['tipo']);
    if (tipo == 'destaque' || tipo == 'destaques') return true;

    final text = _evaluationSearchText(row);
    return text.contains('destaque') ||
        text.contains('destaques') ||
        text.contains('positivo') ||
        text.contains('ponto positivo') ||
        text.contains('elogio') ||
        text.contains('forte');
  }

  bool _isAtencaoEvaluation(Map<String, dynamic> row) {
    final tipo = _normalizeEvaluationText(row['tipo']);
    if (tipo == 'atencao' || tipo == 'atencoes') return true;

    final text = _evaluationSearchText(row);
    return text.contains('atencao') ||
        text.contains('ponto de atencao') ||
        text.contains('melhorar') ||
        text.contains('correcao');
  }

  bool _isCompletaEvaluation(Map<String, dynamic> row) {
    final tipo = _normalizeEvaluationText(row['tipo']);
    if (tipo == 'completa' || tipo == 'completo') return true;

    final text = _evaluationSearchText(row);
    return text.contains('completa') ||
        text.contains('completo') ||
        text.contains('avaliacao mensal') ||
        text.contains('avaliacao completa');
  }

  bool _isInsideEvaluationPeriod(Map<String, dynamic> row, DateTime? start) {
    if (start == null) return true;

    final date = _parseDate(row['created_at']);
    if (date == null) return false;

    final dayOnly = DateTime(date.year, date.month, date.day);
    final startOnly = DateTime(start.year, start.month, start.day);

    return !dayOnly.isBefore(startOnly);
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

  Future<Map<String, Map<String, dynamic>>> _loadEventsByIds(
    Iterable<String> eventIds,
  ) async {
    final ids = eventIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();

    if (ids.isEmpty) return {};

    try {
      final rows = await _supabase
          .from('events')
          .select('id, event_type, gender, event_date, event_time, created_at')
          .inFilter('id', ids);

      final map = <String, Map<String, dynamic>>{};
      for (final row in List<Map<String, dynamic>>.from(rows as List)) {
        final id = (row['id'] ?? '').toString();
        if (id.isNotEmpty) {
          map[id] = row;
        }
      }

      return map;
    } catch (e) {
      debugPrint('Erro ao carregar eventos dos check-ins: $e');
      return {};
    }
  }

  Future<List<Map<String, dynamic>>> _loadTrainingPlanBlocks(
    String athleteId,
  ) async {
    try {
      dynamic rows;

      try {
        rows = await _supabase.rpc(
          'get_checked_in_training_plan_blocks_for_athlete',
          params: {'p_athlete_id': athleteId},
        );
      } catch (_) {
        rows = await _supabase.rpc(
          'get_checked_in_training_plan_blocks_for_athlete',
        );
      }

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

      final athleteId =
          widget.adminView ? (widget.athleteId ?? '').trim() : user.id;

      if (athleteId.isEmpty) {
        throw Exception('Atleta não identificado.');
      }

      final profileRows = await _supabase
          .from('profiles')
          .select('id, full_name, avatar_url, gender, user_type')
          .eq('id', athleteId)
          .limit(1);

      final profiles = List<Map<String, dynamic>>.from(profileRows as List);

      final evaluationsRows = await _safeSelect(
        'training_evaluations',
        'id, event_id, coach_id, athlete_id, tipo, slot, motivo, fundamento, observacao, created_at, score',
      );

      final evaluations = evaluationsRows.where((row) {
        return (row['athlete_id'] ?? '').toString() == athleteId;
      }).toList()
        ..sort((a, b) {
          final ad = _parseDate(a['created_at']) ?? DateTime(1900);
          final bd = _parseDate(b['created_at']) ?? DateTime(1900);
          return bd.compareTo(ad);
        });

      final checkins = await _safeSelect(
        'checkins',
        'id, user_id, event_id, check_in_status, created_at',
        userId: athleteId,
      );

      final convocations = await _safeSelect(
        'convocations',
        'id, user_id, event_id, status, justification, created_at, events!$_eventsEmbedFk (id, event_type, gender, event_date, event_time)',
        userId: athleteId,
      );

      final eventIds = <String>{
        ...checkins
            .map((row) => (row['event_id'] ?? '').toString())
            .where((id) => id.isNotEmpty),
        ...convocations
            .map((row) => (row['event_id'] ?? '').toString())
            .where((id) => id.isNotEmpty),
      };
      final eventsById = await _loadEventsByIds(eventIds);

      final messages = await _loadMessages(athleteId);
      final trainingPlanBlocks = await _loadTrainingPlanBlocks(athleteId);

      if (!mounted) return;
      setState(() {
        _profile = profiles.isNotEmpty ? profiles.first : null;
        _evaluations = evaluations;
        _checkins = checkins;
        _convocations = convocations;
        _eventsById = eventsById;
        _trainingPlanBlocks = trainingPlanBlocks;
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
    return _evaluations
        .where((row) => _isInsideEvaluationPeriod(row, start))
        .toList();
  }

  List<Map<String, dynamic>> get _periodMessages {
    final start = _periodStart();
    return _messages
        .where((row) => _isInsidePeriod(row['created_at'], start))
        .toList();
  }

  int get _destaques {
    return _periodEvaluations.where(_isDestaqueEvaluation).length;
  }

  int get _atencoes {
    return _periodEvaluations.where(_isAtencaoEvaluation).length;
  }

  int get _completas {
    return _periodEvaluations.where(_isCompletaEvaluation).length;
  }

  int get _score {
    int total = 0;

    for (final row in _periodEvaluations) {
      if (_isDestaqueEvaluation(row)) {
        total += 2;
      } else if (_isAtencaoEvaluation(row)) {
        total -= 1;
      } else if (_isCompletaEvaluation(row)) {
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

  Map<String, dynamic>? _eventForEventId(String eventId) {
    if (eventId.isEmpty) return null;

    final direct = _eventsById[eventId];
    if (direct != null) return direct;

    final convocation = _convocationForEventId(eventId);
    final embeddedEvent = convocation?['events'];
    if (embeddedEvent is Map) {
      return Map<String, dynamic>.from(embeddedEvent);
    }

    return null;
  }

  bool _eventMapIsTrainingAndInsidePeriod(
    Map<String, dynamic> event,
    DateTime? start,
  ) {
    final wrapped = {'events': event};
    if (!_isTrainingEvent(wrapped)) return false;
    if (!_eventMatchesAthleteGender(wrapped)) return false;
    if (!_isInsideTrainingPeriod(wrapped, start)) return false;
    return true;
  }

  Set<String> get _convokedTrainingEventIds {
    final start = _periodStart();

    final eventIds = _convocations
        .where((row) {
          if (!_isTrainingEvent(row)) return false;
          if (!_eventMatchesAthleteGender(row)) return false;
          if (!_isInsideTrainingPeriod(row, start)) return false;
          return true;
        })
        .map((row) => (row['event_id'] ?? '').toString())
        .where((id) => id.isNotEmpty)
        .toSet();

    // ✅ Inclui também treinos com check-in válido, mesmo quando o atleta
    // não tem registro correspondente em `convocations`. Isso cobre check-ins
    // atrasados/manuais feitos pelo admin.
    eventIds.addAll(_checkedInTrainingEventIdsInPeriod(start));

    return eventIds;
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
    if (eventId.isEmpty) return false;

    final convocation = _convocationForEventId(eventId);

    if (convocation != null) {
      if (!_isTrainingEvent(convocation)) return false;
      if (!_eventMatchesAthleteGender(convocation)) return false;
      if (!_isInsideTrainingPeriod(convocation, start)) return false;
      return true;
    }

    final event = _eventForEventId(eventId);
    if (event == null) return false;

    return _eventMapIsTrainingAndInsidePeriod(event, start);
  }

  Set<String> _checkedInTrainingEventIdsInPeriod(DateTime? start) {
    return _checkins
        .where((row) {
          if (!_isCheckinDone(row['check_in_status'])) return false;

          final eventId = (row['event_id'] ?? '').toString();
          if (eventId.isEmpty) return false;

          final event = _eventForEventId(eventId);
          if (event == null) return false;

          return _eventMapIsTrainingAndInsidePeriod(event, start);
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

  Set<String> _explicitAbsenceTrainingEventIdsInPeriod(DateTime? start) {
    return _checkins
        .where((row) {
          if (!_isExplicitAbsenceCheckinStatus(row['check_in_status'])) {
            return false;
          }

          final eventId = (row['event_id'] ?? '').toString();
          if (eventId.isEmpty) return false;

          final event = _eventForEventId(eventId);
          if (event == null) return false;

          return _eventMapIsTrainingAndInsidePeriod(event, start);
        })
        .map((row) => (row['event_id'] ?? '').toString())
        .where((id) => id.isNotEmpty)
        .toSet();
  }

  int get _trainingBaseCount {
    // Base do percentual de presença: somente treinos já consolidados.
    // Treinos futuros ou ainda dentro do prazo de check-in ficam como
    // pendentes e NÃO entram no denominador da porcentagem.
    return _trainingPresenceCount + _trainingAcceptedAbsentCount;
  }

  int get _trainingPresenceCount {
    final baseEventIds = _convokedTrainingEventIds;
    if (baseEventIds.isEmpty) return 0;

    final start = _periodStart();

    return _checkins
        .where((row) {
          if (!_isCheckinDone(row['check_in_status'])) return false;
          if (!_isCheckinInsideConvokedTrainingPeriod(row, start)) return false;

          final eventId = (row['event_id'] ?? '').toString();
          return baseEventIds.contains(eventId);
        })
        .map((row) => (row['event_id'] ?? '').toString())
        .where((id) => id.isNotEmpty)
        .toSet()
        .length;
  }

  int get _trainingPendingCount {
    final start = _periodStart();
    final now = DateTime.now();
    final doneEventIds = _checkedInTrainingEventIdsInPeriod(start);

    return _convocations
        .where((row) {
          if (!_isTrainingEvent(row)) return false;
          if (!_eventMatchesAthleteGender(row)) return false;
          if (!_isInsideTrainingPeriod(row, start)) return false;

          final eventId = (row['event_id'] ?? '').toString();
          if (eventId.isEmpty || doneEventIds.contains(eventId)) return false;

          final eventDate = _eventDateTime(row);
          if (eventDate == null) return true;

          return !now.isAfter(eventDate.add(const Duration(minutes: 30)));
        })
        .map((row) => (row['event_id'] ?? '').toString())
        .where((id) => id.isNotEmpty)
        .toSet()
        .length;
  }

  int get _trainingAcceptedAbsentCount {
    final start = _periodStart();
    final doneEventIds = _checkedInTrainingEventIdsInPeriod(start);
    final explicitAbsences = _explicitAbsenceTrainingEventIdsInPeriod(start);

    return _convocations
        .where((row) {
          if (!_isTrainingEvent(row)) return false;
          if (!_eventMatchesAthleteGender(row)) return false;
          if (!_isInsideTrainingPeriod(row, start)) return false;

          final eventId = (row['event_id'] ?? '').toString();
          if (eventId.isEmpty || doneEventIds.contains(eventId)) return false;

          // Mesma correção feita na tela do atleta:
          // pendente/vencido NÃO vira falta automaticamente.
          // Falta só conta quando existe ausência explícita registrada.
          return explicitAbsences.contains(eventId);
        })
        .map((row) => (row['event_id'] ?? '').toString())
        .where((id) => id.isNotEmpty)
        .toSet()
        .length;
  }

  List<_MonthlyPresenceAbsence> get _annualPresenceAbsenceByMonth {
    final year = DateTime.now().year;

    final monthlyPresenceEventIds = <int, Set<String>>{
      for (int month = 1; month <= 12; month++) month: <String>{},
    };
    final monthlyAbsentEventIds = <int, Set<String>>{
      for (int month = 1; month <= 12; month++) month: <String>{},
    };

    final convokedTrainingEventDates = <String, DateTime>{};

    for (final row in _convocations) {
      if (!_isTrainingEvent(row)) continue;
      if (!_eventMatchesAthleteGender(row)) continue;

      final eventDate = _eventDateTime(row);
      if (!_isOnOrAfterStatsRuleStart(eventDate)) continue;
      if (eventDate == null || eventDate.year != year) continue;

      final eventId = (row['event_id'] ?? '').toString();
      if (eventId.isEmpty) continue;

      convokedTrainingEventDates[eventId] = eventDate;
    }

    final checkedTrainingEventDates = <String, DateTime>{};
    final doneEventIds = <String>{};

    for (final row in _checkins) {
      if (!_isCheckinDone(row['check_in_status'])) continue;

      final eventId = (row['event_id'] ?? '').toString();
      if (eventId.isEmpty) continue;

      final event = _eventForEventId(eventId);
      if (event == null) continue;
      if (!_eventMapIsTrainingAndInsidePeriod(event, null)) continue;

      final eventDate = _eventDateTime({'events': event});
      if (!_isOnOrAfterStatsRuleStart(eventDate)) continue;
      if (eventDate == null || eventDate.year != year) continue;

      checkedTrainingEventDates[eventId] = eventDate;
      doneEventIds.add(eventId);
    }

    final explicitAbsenceEventIds =
        _explicitAbsenceTrainingEventIdsInPeriod(null);

    final allTrainingEventDates = <String, DateTime>{
      ...convokedTrainingEventDates,
      ...checkedTrainingEventDates,
    };

    for (final entry in allTrainingEventDates.entries) {
      final eventId = entry.key;
      final eventDate = entry.value;
      final month = eventDate.month;

      // Check-in válido sempre ganha da falta.
      if (doneEventIds.contains(eventId)) {
        monthlyPresenceEventIds[month]!.add(eventId);
        monthlyAbsentEventIds[month]!.remove(eventId);
        continue;
      }

      // Mesma correção feita na tela do atleta:
      // pendente/vencido NÃO vira falta no gráfico anual.
      // Falta só aparece quando existe ausência explícita registrada.
      if (explicitAbsenceEventIds.contains(eventId)) {
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
    final start = _periodStart();

    return _convocations
        .where((row) {
          final status = (row['status'] ?? '').toString().toLowerCase().trim();
          if (status != 'rejected' &&
              status != 'declined' &&
              status != 'refused') {
            return false;
          }
          if (!_isTrainingEvent(row)) return false;
          if (!_eventMatchesAthleteGender(row)) return false;
          if (!_isInsideTrainingPeriod(row, start)) return false;
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
      if (!_isAtencaoEvaluation(row)) continue;

      final fundamento = _normalizeFundamento(row['fundamento']);
      map[fundamento] = (map[fundamento] ?? 0) + 1;
    }

    return map;
  }

  Map<String, int> get _positiveByFundament {
    final map = <String, int>{};

    for (final row in _periodEvaluations) {
      if (!_isDestaqueEvaluation(row)) continue;

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
      int score = 0;
      if (_isDestaqueEvaluation(row)) {
        score = 2;
      } else if (_isAtencaoEvaluation(row)) {
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
    final items = <String>[];

    if (_periodEvaluations.isEmpty) {
      if (_evaluations.isEmpty) {
        items.add('Ainda não há avaliações cadastradas para este atleta.');
      } else {
        items.add(
            'Há ${_evaluations.length} avaliação(ns) cadastrada(s), mas nenhuma entrou no período ${_periodLabel()}. Verifique a data created_at da avaliação.');
      }
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
                      fit: BoxFit.cover,
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
            (widget.adminView
                ? 'Atleta'
                : _supabase.auth.currentUser?.userMetadata?['full_name']) ??
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
                tag: AthleteStatisticsPage.heroTag,
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
                      widget.adminView
                          ? 'Visão ADMIN • ${_periodLabel()}'
                          : 'Estatísticas do Atleta • ${_periodLabel()}',
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

  Widget _periodChip(String value, String label) {
    final selected = _period == value;

    return ChoiceChip(
      label: Text(label),
      selected: selected,
      selectedColor: olympusGold,
      backgroundColor: olympusBlue.withOpacity(0.28),
      showCheckmark: false,
      labelStyle: TextStyle(
        color: selected ? olympusBlue : Colors.white,
        fontWeight: FontWeight.w900,
      ),
      side: BorderSide(
        color: selected ? olympusGold : Colors.white.withOpacity(0.28),
      ),
      onSelected: (_) {
        if (selected) return;
        setState(() => _period = value);
      },
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
    if (_isDestaqueEvaluation(row)) return 2;
    if (_isAtencaoEvaluation(row)) return -1;

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
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 9),
        decoration: BoxDecoration(
          color: color.withOpacity(0.13),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: color.withOpacity(0.34),
          ),
        ),
        child: Column(
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
              style: TextStyle(
                color: Colors.white.withOpacity(0.72),
                fontSize: 10,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
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
        borderRadius: BorderRadius.circular(28),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: Container(
            padding: EdgeInsets.fromLTRB(
              _StatsResponsive.space(context, 18),
              _StatsResponsive.space(context, 18),
              _StatsResponsive.space(context, 18),
              _StatsResponsive.space(context, 16),
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
                          width: 54,
                          height: 54,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(18),
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
                                blurRadius: 16,
                                spreadRadius: 1,
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.scoreboard_rounded,
                            color: olympusBlue,
                            size: 28,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Score do período',
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
                                  fontSize: 19,
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
                    const SizedBox(height: 18),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '$_score',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: _StatsResponsive.font(context, 58),
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
                    const SizedBox(height: 15),
                    Row(
                      children: [
                        _scoreMiniPill(
                          label: 'Destaques',
                          value: _destaques.toString(),
                          color: olympusSuccess,
                          icon: Icons.star_rounded,
                        ),
                        const SizedBox(width: 8),
                        _scoreMiniPill(
                          label: 'Atenções',
                          value: _atencoes.toString(),
                          color: olympusWarning,
                          icon: Icons.warning_amber_rounded,
                        ),
                        const SizedBox(width: 8),
                        _scoreMiniPill(
                          label: 'Mensais',
                          value: _completas.toString(),
                          color: olympusLightBlue,
                          icon: Icons.assignment_turned_in_outlined,
                        ),
                      ],
                    ),
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
              onTap: () => _showItemExplanation(
                title: 'Presença / Falta',
                explanation:
                    'Base atual: ${_formatPercentValue(_presenceRate)} de presença e ${_formatPercentValue(_absenceRate)} de faltas sobre $_trainingBaseCount treino(s) já consolidado(s).\n\n'
                    'Presenças: $_trainingPresenceCount • Faltas: $_trainingAcceptedAbsentCount • Pendentes: $_trainingPendingCount • Recusados: $_trainingRejectedCount.\n\n'
                    'Presença = check-ins realizados em treinos convocados.\n'
                    'Falta = somente ausência explícita registrada. Pendente/vencido não vira falta automaticamente.\n\n'
                    'Regra válida ${_periodRuleLabel()}.',
              ),
            ),
          ),
          _compactMetricDivider(),
          Expanded(
            child: _compactMetricItem(
              icon: Icons.star_rounded,
              color: olympusSuccess,
              value: _destaques.toString(),
              label: 'Destaques',
              onTap: () => _showItemExplanation(
                title: 'Destaques',
                explanation:
                    'Quantidade de avaliações do tipo destaque recebidas no período selecionado.',
              ),
            ),
          ),
          _compactMetricDivider(),
          Expanded(
            child: _compactMetricItem(
              icon: Icons.warning_amber_rounded,
              color: olympusWarning,
              value: _atencoes.toString(),
              label: 'Atenções',
              onTap: () => _showItemExplanation(
                title: 'Atenções',
                explanation:
                    'Quantidade de pontos de atenção registrados pelo técnico no período selecionado.',
              ),
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
    VoidCallback? onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
          child: Column(
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
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
          ),
        ),
      ),
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
                  'Presença = check-ins realizados ÷ treinos já consolidados, incluindo check-in atrasado lançado pelo admin. Falta = somente ausência explícita registrada. Treinos futuros ou ainda dentro do prazo ficam pendentes e não entram no percentual. Esta tela considera somente treinos a partir de 01/05/2026. Quando o evento possui gênero, o cálculo considera apenas treinos do mesmo gênero cadastrado no perfil da atleta.',
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          'Base atual: ${_formatPercentValue(_presenceRate)} de presença e ${_formatPercentValue(_absenceRate)} de faltas sobre $_trainingBaseCount treino(s) já consolidado(s). Presenças: $_trainingPresenceCount • Faltas: $_trainingAcceptedAbsentCount • Pendentes: $_trainingPendingCount • Recusados: $_trainingRejectedCount. Regra válida ${_periodRuleLabel()}. Gênero usado no filtro: $genderLabel.',
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
    final hasData = totalPresences > 0 || totalAbsences > 0;

    final selectedMonth = _selectedAnnualMonth;
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
                  Color(0xFF081C33),
                  Color(0xFF123861),
                  Color(0xFF1E5C8C),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              border: Border.all(
                color: Colors.white24,
                width: 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: olympusLightBlue.withOpacity(0.26),
                  blurRadius: 22,
                  offset: const Offset(0, 10),
                ),
                BoxShadow(
                  color: olympusGold.withOpacity(0.12),
                  blurRadius: 26,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: Stack(
              children: [
                _athleteParallaxLayer(
                  alignment: Alignment.bottomCenter,
                  opacity: 0.30,
                  parallaxFactor: 0.115,
                  scale: 1.24,
                  strongerBottomShade: true,
                ),
                Positioned(
                  top: -42,
                  right: -34,
                  child: Container(
                    width: 128,
                    height: 128,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withOpacity(0.06),
                    ),
                  ),
                ),
                Positioned(
                  bottom: -48,
                  left: -36,
                  child: Container(
                    width: 122,
                    height: 122,
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
                      crossAxisAlignment: CrossAxisAlignment.start,
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
                                color: olympusGold.withOpacity(0.30),
                                blurRadius: 14,
                                spreadRadius: 1,
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.show_chart_rounded,
                            color: olympusBlue,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Presença anual',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Toque em um mês para ver o detalhe',
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.72),
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                        _infoButton(
                          title: 'Presença anual',
                          explanation:
                              'Gráfico anual com presenças e faltas por mês. Presença é check-in realizado em treino convocado, incluindo check-in atrasado lançado pelo admin. Falta é somente ausência explícita registrada; pendente/vencido não vira falta automaticamente. A regra considera treinos a partir de 01/05/2026 e o gênero do atleta quando o evento possui gender.',
                          color: olympusGold,
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        _annualSummaryPill(
                          label: 'Presenças',
                          value: totalPresences,
                          color: olympusSuccess,
                          icon: Icons.check_circle_rounded,
                        ),
                        const SizedBox(width: 10),
                        _annualSummaryPill(
                          label: 'Faltas',
                          value: totalAbsences,
                          color: olympusDanger,
                          icon: Icons.cancel_rounded,
                        ),
                      ],
                    ),
                    if (selectedData != null) ...[
                      const SizedBox(height: 12),
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
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
                        child: Row(
                          children: [
                            const Icon(
                              Icons.touch_app_rounded,
                              color: olympusGold,
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '${_fullMonthLabel(selectedData.month)}: ${selectedData.presences} presença(s) / ${selectedData.absences} falta(s)',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          ],
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
                          color: Colors.white.withOpacity(0.11),
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
                                    final month = (normalized * 11).round() + 1;

                                    setState(() {
                                      _selectedAnnualMonth = month.clamp(1, 12);
                                    });
                                  },
                                  child: CustomPaint(
                                    painter: _AnnualPresenceAbsencePainter(
                                      data: data,
                                      presenceColor: olympusSuccess,
                                      absenceColor: olympusDanger,
                                      gridColor: Colors.white.withOpacity(0.16),
                                      labelColor:
                                          Colors.white.withOpacity(0.74),
                                      selectedMonth: _selectedAnnualMonth,
                                      selectedColor: olympusGold,
                                    ),
                                    child: const SizedBox.expand(),
                                  ),
                                );
                              },
                            )
                          : Center(
                              child: Text(
                                'Ainda não há dados suficientes para montar o gráfico anual.',
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
                        _chartLegendDot(
                          label: 'Presenças',
                          color: olympusSuccess,
                        ),
                        const SizedBox(width: 14),
                        _chartLegendDot(
                          label: 'Faltas',
                          color: olympusDanger,
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _annualSummaryPill({
    required String label,
    required int value,
    required Color color,
    required IconData icon,
  }) {
    return Expanded(
      child: Container(
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
    final positive = _positiveByFundament.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final attention = _attentionByFundament.entries.toList()
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
              explanation:
                  'Mostra os fundamentos que mais apareceram nas avaliações. Fortes vêm dos destaques; Para melhorar vem dos pontos de atenção.',
            ),
          ],
        ),
        const SizedBox(height: 14),
        listBlock(
          title: 'Fortes',
          entries: positive,
          color: olympusSuccess,
          empty: 'Nenhum fundamento em destaque no período.',
        ),
        const SizedBox(height: 16),
        listBlock(
          title: 'Para melhorar',
          entries: attention,
          color: olympusWarning,
          empty: 'Nenhum ponto de atenção no período.',
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

    Color colorForEvaluation(Map<String, dynamic> row) {
      if (_isDestaqueEvaluation(row)) return olympusSuccess;
      if (_isAtencaoEvaluation(row)) return olympusWarning;
      if (_isCompletaEvaluation(row)) return olympusGold;
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
            final color = colorForEvaluation(evaluation);

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: olympusBg,
      appBar: AppBar(
        title: Text(widget.adminView
            ? 'Estatísticas do Atleta'
            : 'Estatísticas do Atleta'),
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
                    _scoreHeroCard(),
                    _annualPresenceAbsenceChart(),
                    _trainingPlanPieChartAthlete(),
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
  });

  final List<_MonthlyPresenceAbsence> data;
  final Color presenceColor;
  final Color absenceColor;
  final Color gridColor;
  final Color labelColor;
  final int? selectedMonth;
  final Color? selectedColor;

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
    final maxAbsence = data.map((e) => e.absences).fold<int>(0, math.max);
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
    final gap = math.max(2.0, monthSlot * 0.08);
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

      final presenceLeft = centerX - barWidth - gap / 2;
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

      if (absenceHeight > 0) {
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
        oldDelegate.selectedColor != selectedColor;
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
