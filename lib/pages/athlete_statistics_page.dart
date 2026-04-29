import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AthleteStatisticsPage extends StatefulWidget {
  const AthleteStatisticsPage({super.key});

  static const String heroTag = 'athlete-statistics-hero';

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

  bool _loading = true;
  String? _error;

  Map<String, dynamic>? _profile;
  List<Map<String, dynamic>> _evaluations = [];
  List<Map<String, dynamic>> _messages = [];
  List<Map<String, dynamic>> _checkins = [];
  List<Map<String, dynamic>> _convocations = [];

  String _period = 'mes';

  @override
  void initState() {
    super.initState();
    _loadData();
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

    return raw == 'realizado' ||
        raw == 'checked_in' ||
        raw == 'checkin_realizado' ||
        raw == 'ok' ||
        raw == 'success' ||
        raw == 'completed' ||
        raw == 'done';
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
        'id, user_id, event_id, check_in_status, created_at, events:event_id (id, event_type, gender, event_date, event_time)',
        userId: user.id,
      );

      final convocations = await _safeSelect(
        'convocations',
        'id, user_id, event_id, status, created_at, events:event_id (id, event_type, gender, event_date, event_time)',
        userId: user.id,
      );

      final messages = await _loadMessages(user.id);

      if (!mounted) return;
      setState(() {
        _profile = profiles.isNotEmpty ? profiles.first : null;
        _evaluations = evaluations;
        _checkins = checkins;
        _convocations = convocations;
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
        .where((row) => _isInsidePeriod(row['created_at'], start))
        .toList();
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

  Set<String> get _acceptedTrainingEventIds {
    final start = _periodStart();

    return _convocations
        .where((row) {
          final status = (row['status'] ?? '').toString().toLowerCase().trim();
          if (status != 'accepted') return false;
          if (!_isTrainingEvent(row)) return false;
          if (!_eventMatchesAthleteGender(row)) return false;
          if (!_isInsideTrainingPeriod(row, start)) return false;
          return true;
        })
        .map((row) => (row['event_id'] ?? '').toString())
        .where((id) => id.isNotEmpty)
        .toSet();
  }

  int get _trainingBaseCount {
    return _acceptedTrainingEventIds.length;
  }

  int get _trainingPresenceCount {
    final acceptedEventIds = _acceptedTrainingEventIds;
    if (acceptedEventIds.isEmpty) return 0;

    final start = _periodStart();

    return _checkins
        .where((row) {
          if (!_isCheckinDone(row['check_in_status'])) return false;
          if (!_isTrainingEvent(row)) return false;
          if (!_eventMatchesAthleteGender(row)) return false;
          if (!_isInsideTrainingPeriod(row, start)) return false;

          final eventId = (row['event_id'] ?? '').toString();
          return acceptedEventIds.contains(eventId);
        })
        .map((row) => (row['event_id'] ?? '').toString())
        .where((id) => id.isNotEmpty)
        .toSet()
        .length;
  }

  int get _trainingPendingCount {
    final start = _periodStart();
    final now = DateTime.now();
    final doneEventIds = _checkins
        .where((row) {
          if (!_isCheckinDone(row['check_in_status'])) return false;
          if (!_isTrainingEvent(row)) return false;
          if (!_eventMatchesAthleteGender(row)) return false;
          if (!_isInsideTrainingPeriod(row, start)) return false;
          return true;
        })
        .map((row) => (row['event_id'] ?? '').toString())
        .where((id) => id.isNotEmpty)
        .toSet();

    return _convocations
        .where((row) {
          final status = (row['status'] ?? '').toString().toLowerCase().trim();
          if (status != 'accepted') return false;
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
    final now = DateTime.now();
    final doneEventIds = _checkins
        .where((row) {
          if (!_isCheckinDone(row['check_in_status'])) return false;
          if (!_isTrainingEvent(row)) return false;
          if (!_eventMatchesAthleteGender(row)) return false;
          if (!_isInsideTrainingPeriod(row, start)) return false;
          return true;
        })
        .map((row) => (row['event_id'] ?? '').toString())
        .where((id) => id.isNotEmpty)
        .toSet();

    return _convocations
        .where((row) {
          final status = (row['status'] ?? '').toString().toLowerCase().trim();
          if (status != 'accepted') return false;
          if (!_isTrainingEvent(row)) return false;
          if (!_eventMatchesAthleteGender(row)) return false;
          if (!_isInsideTrainingPeriod(row, start)) return false;

          final eventId = (row['event_id'] ?? '').toString();
          if (eventId.isEmpty || doneEventIds.contains(eventId)) return false;

          final eventDate = _eventDateTime(row);
          if (eventDate == null) return false;

          return now.isAfter(eventDate.add(const Duration(minutes: 30)));
        })
        .map((row) => (row['event_id'] ?? '').toString())
        .where((id) => id.isNotEmpty)
        .toSet()
        .length;
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

    if (_presenceRate > 0 && _presenceRate < 0.65) {
      items.add('Sua presença está abaixo do ideal no período.');
    } else if (_presenceRate >= 0.85) {
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
      margin: margin ?? const EdgeInsets.fromLTRB(16, 0, 16, 12),
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

  Widget _header() {
    final fullName = (_profile?['full_name'] ??
            _supabase.auth.currentUser?.userMetadata?['full_name'] ??
            'Atleta')
        .toString();
    final avatarUrl = (_profile?['avatar_url'] ?? '').toString();

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      padding: const EdgeInsets.all(16),
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
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
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

  Widget _metricCard({
    required IconData icon,
    required String title,
    required String value,
    required Color color,
    required String explanation,
  }) {
    return Container(
      constraints: const BoxConstraints(minHeight: 116),
      padding: const EdgeInsets.all(12),
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
            child: Text(
              value,
              style: const TextStyle(
                color: olympusBlue,
                fontSize: 23,
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
        ],
      ),
    );
  }

  Widget _metricsGrid() {
    final metrics = [
      {
        'icon': Icons.trending_up_rounded,
        'title': 'Evolução',
        'value': _evolutionLabel,
        'color': olympusBlue,
        'explanation':
            'Mostra a leitura do período: Melhorando quando os destaques superam os pontos de atenção; Precisa de atenção quando os pontos de atenção superam os destaques; Estável quando há equilíbrio.',
      },
      {
        'icon': Icons.star_rounded,
        'title': 'Destaques',
        'value': '$_destaques',
        'color': olympusSuccess,
        'explanation':
            'Quantidade de avaliações do tipo destaque recebidas no período selecionado.',
      },
      {
        'icon': Icons.warning_amber_rounded,
        'title': 'Atenções',
        'value': '$_atencoes',
        'color': olympusWarning,
        'explanation':
            'Quantidade de pontos de atenção registrados pelo técnico no período selecionado.',
      },
      {
        'icon': Icons.scoreboard_rounded,
        'title': 'Score',
        'value': '$_score',
        'color': olympusGold,
        'explanation':
            'Pontuação calculada pelas avaliações: destaque soma +2, ponto de atenção subtrai -1 e avaliações completas usam o score/nota salvo no banco quando existir.',
      },
      {
        'icon': Icons.fact_check_outlined,
        'title': 'Presença',
        'value': '${(_presenceRate * 100).round()}%',
        'color': olympusPurple,
        'explanation':
            'Percentual calculado pela mesma regra do painel do atleta: check-ins realizados ÷ treinos aceitos. Só entram treinos a partir de 01/05/2026 e do mesmo gênero do atleta quando o evento possui gender.',
      },
      {
        'icon': Icons.assignment_turned_in_outlined,
        'title': 'Mensais',
        'value': '$_completas',
        'color': olympusLightBlue,
        'explanation':
            'Quantidade de avaliações completas mensais registradas no período selecionado.',
      },
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final crossAxisCount = width < 360
              ? 2
              : width < 720
                  ? 3
                  : 6;
          final aspectRatio = width < 360
              ? 1.04
              : width < 720
                  ? 1.12
                  : 1.0;

          return GridView.builder(
            itemCount: metrics.length,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: aspectRatio,
            ),
            itemBuilder: (context, index) {
              final item = metrics[index];

              return _metricCard(
                icon: item['icon'] as IconData,
                title: item['title'] as String,
                value: item['value'] as String,
                color: item['color'] as Color,
                explanation: item['explanation'] as String,
              );
            },
          );
        },
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
                  'Presença = check-ins realizados ÷ treinos aceitos. Esta tela usa a mesma lógica do painel do atleta, considerando somente treinos a partir de 01/05/2026. Quando o evento possui gênero, o cálculo considera apenas treinos do mesmo gênero cadastrado no perfil da atleta.',
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          'Base atual: $_trainingPresenceCount presença(s) em $_trainingBaseCount treino(s) aceito(s). Pendentes: $_trainingPendingCount • Ausência após aceite: $_trainingAcceptedAbsentCount • Recusados: $_trainingRejectedCount. Regra válida ${_periodRuleLabel()}. Gênero usado no filtro: $genderLabel.',
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
                  padding: const EdgeInsets.only(bottom: 28),
                  children: [
                    _header(),
                    _metricsGrid(),
                    const SizedBox(height: 12),
                    _presenceExplanationCard(),
                    _evolutionChart(),
                    _fundamentsSection(),
                    _insightsSection(),
                    _messagesSection(),
                    _historySection(),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
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
