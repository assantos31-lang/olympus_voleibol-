import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'admin_training_plans_list_page.dart';

enum TrendMode {
  weekly,
  monthly,
}

class AdminTrainingPlansPage extends StatefulWidget {
  const AdminTrainingPlansPage({super.key});

  @override
  State<AdminTrainingPlansPage> createState() => _AdminTrainingPlansPageState();
}

class _AdminTrainingPlansPageState extends State<AdminTrainingPlansPage> {
  final SupabaseClient _supabase = Supabase.instance.client;

  static const Color olympusBlue = Color(0xFF1E3A5F);
  static const Color olympusLightBlue = Color(0xFF2C5F8D);
  static const Color olympusGold = Color(0xFFD4AF37);
  static const Color olympusBg = Color(0xFFF4F7FB);
  static const Color olympusText = Color(0xFF17324D);
  static const Color olympusMuted = Color(0xFF53657B);
  static const Color olympusBorder = Color(0xFFE4EDF5);
  static const Color olympusDanger = Color(0xFFDC2626);
  static const Color olympusSuccess = Color(0xFF16A34A);
  static const Color olympusWarning = Color(0xFFF59E0B);
  static const Color olympusPurple = Color(0xFF7C3AED);
  static const Color olympusSubtle = Color(0xFF64748B);

  bool _loading = true;
  String? _error;

  List<Map<String, dynamic>> _events = [];
  Map<String, List<Map<String, dynamic>>> _plansByEvent = {};

  String _selectedMonth = '';
  String _selectedCoachId = '';
  String _selectedGender = '';
  TrendMode _trendMode = TrendMode.weekly;

  final Map<String, int> _categoryGoals = {
    'Fundamentos': 40,
    'Tático': 35,
    'Físico': 25,
  };

  final ScrollController _quickSummaryScrollController = ScrollController();
  final ScrollController _categoriesScrollController = ScrollController();
  final ScrollController _foundationsScrollController = ScrollController();
  final ScrollController _coachesScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _setCurrentMonth();
    _loadDashboard();
  }

  @override
  void dispose() {
    _quickSummaryScrollController.dispose();
    _categoriesScrollController.dispose();
    _foundationsScrollController.dispose();
    _coachesScrollController.dispose();
    super.dispose();
  }

  void _setCurrentMonth() {
    final now = DateTime.now();
    _selectedMonth = '${now.month.toString().padLeft(2, '0')}/${now.year}';
  }

  bool _isMobile(BuildContext context) {
    return MediaQuery.of(context).size.width < 600;
  }

  bool _isNarrow(BuildContext context) {
    return MediaQuery.of(context).size.width < 430;
  }

  String _asString(dynamic value) => (value ?? '').toString().trim();

  bool _isTrainingEvent(Map<String, dynamic> event) {
    final type = _asString(event['event_type']).toLowerCase();
    return type == 'treino';
  }

  String _normalizeTime(dynamic value) {
    final raw = _asString(value);
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

  DateTime? _parseEventDate(Map<String, dynamic> event) {
    final raw = _asString(event['event_date']);
    final parts = raw.split('/');

    if (parts.length != 3) return null;

    final day = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    final year = int.tryParse(parts[2]);

    if (day == null || month == null || year == null) return null;

    return DateTime(year, month, day);
  }

  DateTime _parseEventDateTime(Map<String, dynamic> event) {
    final date = _parseEventDate(event);
    if (date == null) return DateTime(2100);

    final time = _normalizeTime(event['event_time']);
    final parts = time.split(':');

    final hour = parts.length >= 2 ? int.tryParse(parts[0]) ?? 0 : 0;
    final minute = parts.length >= 2 ? int.tryParse(parts[1]) ?? 0 : 0;

    return DateTime(date.year, date.month, date.day, hour, minute);
  }

  DateTime? _parseBlockTime(dynamic value) {
    final clean = _normalizeTime(value);
    final parts = clean.split(':');

    if (parts.length != 2) return null;

    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);

    if (hour == null || minute == null) return null;

    return DateTime(2000, 1, 1, hour, minute);
  }

  int _blockMinutes(Map<String, dynamic> block) {
    final start = _parseBlockTime(block['start_time']);
    final end = _parseBlockTime(block['end_time']);

    if (start == null || end == null || !end.isAfter(start)) return 0;

    return end.difference(start).inMinutes;
  }

  String _formatDuration(int minutes) {
    if (minutes <= 0) return '0min';

    final h = minutes ~/ 60;
    final m = minutes % 60;

    if (h == 0) return '${m}min';
    if (m == 0) return '${h}h';
    return '${h}h ${m}min';
  }

  String _formatEventDateTime(Map<String, dynamic> event) {
    final date = _asString(event['event_date']);
    final time = _normalizeTime(event['event_time']);

    if (date.isEmpty && time.isEmpty) return 'Sem data definida';
    if (date.isEmpty) return time;
    if (time.isEmpty) return date;

    return '$date • $time';
  }

  String _normalizeGender(dynamic value) {
    final raw = _asString(value).toLowerCase();

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

  String _genderLabel(String value) {
    switch (_normalizeGender(value)) {
      case 'feminino':
        return 'Feminino';
      case 'masculino':
        return 'Masculino';
      default:
        return 'Todos os gêneros';
    }
  }

  String _monthLabel(String monthYear) {
    final parts = monthYear.split('/');
    if (parts.length != 2) return monthYear;

    final month = int.tryParse(parts[0]) ?? 1;
    final year = int.tryParse(parts[1]) ?? 2000;

    const names = [
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

    final name = month >= 1 && month <= 12 ? names[month - 1] : 'Mês';
    return '$name/$year';
  }

  Future<void> _loadDashboard() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final user = _supabase.auth.currentUser;
      if (user == null) {
        throw Exception('Usuário não autenticado.');
      }

      final blocksResponse = await _supabase
          .from('training_plan_blocks')
          .select(
            'id, event_id, coach_id, category, type, start_time, end_time, observation, position, updated_at',
          )
          .order('position', ascending: true);

      final notesResponse = await _supabase
          .from('training_plan_notes')
          .select('event_id, coach_id, notes, updated_at');

      final blocks = List<Map<String, dynamic>>.from(blocksResponse as List);
      final notes = List<Map<String, dynamic>>.from(notesResponse as List);

      final eventIds = <String>{};
      final coachIds = <String>{};

      for (final block in blocks) {
        final eventId = _asString(block['event_id']);
        final coachId = _asString(block['coach_id']);
        if (eventId.isNotEmpty) eventIds.add(eventId);
        if (coachId.isNotEmpty) coachIds.add(coachId);
      }

      for (final note in notes) {
        final eventId = _asString(note['event_id']);
        final coachId = _asString(note['coach_id']);
        if (eventId.isNotEmpty) eventIds.add(eventId);
        if (coachId.isNotEmpty) coachIds.add(coachId);
      }

      if (eventIds.isEmpty) {
        if (!mounted) return;
        setState(() {
          _events = [];
          _plansByEvent = {};
          _loading = false;
        });
        return;
      }

      final eventsResponse = await _supabase
          .from('events')
          .select(
            'id, event_name, event_type, event_date, event_time, gender, city, state',
          )
          .inFilter('id', eventIds.toList());

      final eventsRaw = List<Map<String, dynamic>>.from(eventsResponse as List);

      final events = eventsRaw.where(_isTrainingEvent).toList();
      final validEventIds = events.map((e) => _asString(e['id'])).toSet();

      Map<String, Map<String, dynamic>> profilesById = {};
      if (coachIds.isNotEmpty) {
        final profilesResponse = await _supabase
            .from('profiles')
            .select('id, full_name, avatar_url')
            .inFilter('id', coachIds.toList());

        final profiles =
            List<Map<String, dynamic>>.from(profilesResponse as List);

        profilesById = {
          for (final profile in profiles) _asString(profile['id']): profile,
        };
      }

      final blocksByKey = <String, List<Map<String, dynamic>>>{};
      for (final block in blocks) {
        final eventId = _asString(block['event_id']);
        final coachId = _asString(block['coach_id']);

        if (!validEventIds.contains(eventId) || coachId.isEmpty) continue;

        final key = '$eventId::$coachId';
        blocksByKey.putIfAbsent(key, () => []);
        blocksByKey[key]!.add(block);
      }

      final notesByKey = <String, Map<String, dynamic>>{};
      for (final note in notes) {
        final eventId = _asString(note['event_id']);
        final coachId = _asString(note['coach_id']);

        if (!validEventIds.contains(eventId) || coachId.isEmpty) continue;

        notesByKey['$eventId::$coachId'] = note;
      }

      final allKeys = <String>{...blocksByKey.keys, ...notesByKey.keys};
      final plansByEvent = <String, List<Map<String, dynamic>>>{};

      for (final key in allKeys) {
        final parts = key.split('::');
        if (parts.length != 2) continue;

        final eventId = parts[0];
        final coachId = parts[1];

        final profile = profilesById[coachId];
        final coachName = _asString(profile?['full_name']).isEmpty
            ? 'Técnico'
            : _asString(profile?['full_name']);

        final planBlocks = blocksByKey[key] ?? <Map<String, dynamic>>[];
        int totalMinutes = 0;

        for (final block in planBlocks) {
          totalMinutes += _blockMinutes(block);
        }

        final plan = {
          'event_id': eventId,
          'coach_id': coachId,
          'coach_name': coachName,
          'coach_avatar_url': _asString(profile?['avatar_url']),
          'blocks': planBlocks,
          'notes': _asString(notesByKey[key]?['notes']),
          'updated_at': _lastUpdated(planBlocks, notesByKey[key]),
          'total_minutes': totalMinutes,
        };

        plansByEvent.putIfAbsent(eventId, () => []);
        plansByEvent[eventId]!.add(plan);
      }

      for (final entry in plansByEvent.entries) {
        entry.value.sort(
          (a, b) => _asString(a['coach_name']).compareTo(
            _asString(b['coach_name']),
          ),
        );
      }

      events.sort(
          (a, b) => _parseEventDateTime(a).compareTo(_parseEventDateTime(b)));

      if (!mounted) return;
      setState(() {
        _events = events;
        _plansByEvent = plansByEvent;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Erro ao carregar dashboard: $e';
      });
    }
  }

  String _lastUpdated(
    List<Map<String, dynamic>> blocks,
    Map<String, dynamic>? note,
  ) {
    final dates = <DateTime>[];

    for (final block in blocks) {
      final parsed = DateTime.tryParse(_asString(block['updated_at']));
      if (parsed != null) dates.add(parsed);
    }

    final noteDate = DateTime.tryParse(_asString(note?['updated_at']));
    if (noteDate != null) dates.add(noteDate);

    if (dates.isEmpty) return '';

    dates.sort();
    final last = dates.last.toLocal();

    return '${last.day.toString().padLeft(2, '0')}/'
        '${last.month.toString().padLeft(2, '0')}/'
        '${last.year} '
        '${last.hour.toString().padLeft(2, '0')}:'
        '${last.minute.toString().padLeft(2, '0')}';
  }

  List<Map<String, dynamic>> _plansForEvent(String eventId) {
    final plans = List<Map<String, dynamic>>.from(_plansByEvent[eventId] ?? []);

    if (_selectedCoachId.isEmpty) return plans;

    return plans.where((plan) {
      return _asString(plan['coach_id']) == _selectedCoachId;
    }).toList();
  }

  List<Map<String, dynamic>> _filteredEvents() {
    var list = List<Map<String, dynamic>>.from(_events);

    if (_selectedMonth.isNotEmpty) {
      list = list.where((event) {
        final date = _asString(event['event_date']);
        if (date.length < 7) return false;
        return date.substring(3) == _selectedMonth;
      }).toList();
    }

    if (_selectedCoachId.isNotEmpty) {
      list = list.where((event) {
        final eventId = _asString(event['id']);
        return _plansForEvent(eventId).isNotEmpty;
      }).toList();
    }

    if (_selectedGender.isNotEmpty) {
      list = list.where((event) {
        return _normalizeGender(event['gender']) == _selectedGender;
      }).toList();
    }

    return list;
  }

  List<Map<String, dynamic>> _allCoaches() {
    final map = <String, Map<String, dynamic>>{};

    for (final plans in _plansByEvent.values) {
      for (final plan in plans) {
        final coachId = _asString(plan['coach_id']);
        if (coachId.isEmpty) continue;

        map[coachId] = {
          'coach_id': coachId,
          'coach_name': _asString(plan['coach_name']).isEmpty
              ? 'Técnico'
              : _asString(plan['coach_name']),
        };
      }
    }

    final list = map.values.toList();
    list.sort(
      (a, b) =>
          _asString(a['coach_name']).compareTo(_asString(b['coach_name'])),
    );

    return list;
  }

  List<Map<String, dynamic>> _filteredPlansForSummary(
    List<Map<String, dynamic>> events,
  ) {
    final plans = <Map<String, dynamic>>[];

    for (final event in events) {
      plans.addAll(_plansForEvent(_asString(event['id'])));
    }

    return plans;
  }

  Map<String, int> _timeByField(
    List<Map<String, dynamic>> plans,
    String field,
  ) {
    final totals = <String, int>{};

    for (final plan in plans) {
      final blocks = List<Map<String, dynamic>>.from(plan['blocks'] as List);

      for (final block in blocks) {
        final label = _asString(block[field]).isEmpty
            ? 'Não informado'
            : _asString(block[field]);

        final minutes = _blockMinutes(block);
        if (minutes <= 0) continue;

        totals[label] = (totals[label] ?? 0) + minutes;
      }
    }

    final entries = totals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Map.fromEntries(entries);
  }

  Map<String, Map<String, int>> _coachComparisonByFoundation(
    List<Map<String, dynamic>> plans,
  ) {
    final result = <String, Map<String, int>>{};

    for (final plan in plans) {
      final coachName = _asString(plan['coach_name']).isEmpty
          ? 'Técnico'
          : _asString(plan['coach_name']);

      final blocks = List<Map<String, dynamic>>.from(plan['blocks'] as List);
      result.putIfAbsent(coachName, () => <String, int>{});

      for (final block in blocks) {
        final foundation = _asString(block['type']).isEmpty
            ? 'Não informado'
            : _asString(block['type']);
        final minutes = _blockMinutes(block);

        if (minutes <= 0) continue;

        result[coachName]![foundation] =
            (result[coachName]![foundation] ?? 0) + minutes;
      }
    }

    return result;
  }

  Map<String, int> _timeByCategoryWithGoals(
    List<Map<String, dynamic>> plans,
  ) {
    final data = _timeByField(plans, 'category');

    for (final category in _categoryGoals.keys) {
      data.putIfAbsent(category, () => 0);
    }

    final entries = data.entries.toList()
      ..sort((a, b) {
        final keys = _categoryGoals.keys.toList();
        final ai = keys.indexOf(a.key);
        final bi = keys.indexOf(b.key);

        if (ai >= 0 && bi >= 0) return ai.compareTo(bi);
        if (ai >= 0) return -1;
        if (bi >= 0) return 1;
        return b.value.compareTo(a.value);
      });

    return Map.fromEntries(entries);
  }

  Map<String, int> _trendByPeriod(List<Map<String, dynamic>> events) {
    final totals = <String, int>{};

    for (final event in events) {
      final date = _parseEventDate(event);
      if (date == null) continue;

      final key =
          _trendMode == TrendMode.weekly ? _weekKey(date) : _monthKey(date);

      int eventMinutes = 0;
      for (final plan in _plansForEvent(_asString(event['id']))) {
        eventMinutes += (plan['total_minutes'] ?? 0) as int;
      }

      if (eventMinutes <= 0) continue;
      totals[key] = (totals[key] ?? 0) + eventMinutes;
    }

    final entries = totals.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    return Map.fromEntries(entries);
  }

  int _weekOfYear(DateTime date) {
    final firstDay = DateTime(date.year, 1, 1);
    final dayOfYear = date.difference(firstDay).inDays + 1;
    return ((dayOfYear - date.weekday + 10) / 7).floor().clamp(1, 53);
  }

  String _weekKey(DateTime date) {
    return '${date.year}-S${_weekOfYear(date).toString().padLeft(2, '0')}';
  }

  String _monthKey(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}';
  }

  String _trendLabel(String key) {
    if (key.contains('-S')) {
      final parts = key.split('-S');
      if (parts.length == 2) return 'Sem. ${parts[1]}/${parts[0]}';
    }

    final parts = key.split('-');
    if (parts.length == 2) return '${parts[1]}/${parts[0]}';

    return key;
  }

  List<String> _availableMonths() {
    final months = <String>{};

    for (final event in _events) {
      final date = _asString(event['event_date']);
      if (date.length >= 7) months.add(date.substring(3));
    }

    final list = months.toList();
    list.sort((a, b) {
      final ap = a.split('/');
      final bp = b.split('/');

      if (ap.length != 2 || bp.length != 2) return a.compareTo(b);

      final ay = int.tryParse(ap[1]) ?? 0;
      final by = int.tryParse(bp[1]) ?? 0;
      if (ay != by) return ay.compareTo(by);

      final am = int.tryParse(ap[0]) ?? 0;
      final bm = int.tryParse(bp[0]) ?? 0;
      return am.compareTo(bm);
    });

    return list;
  }

  String? _safeSelectedMonthValue(List<String> months) {
    if (_selectedMonth.isEmpty) return '';
    if (months.contains(_selectedMonth)) return _selectedMonth;
    return null;
  }

  String _selectedMonthLabel() {
    if (_selectedMonth.isEmpty) return 'Todos os meses';
    return _monthLabel(_selectedMonth);
  }

  String _selectedCoachName() {
    if (_selectedCoachId.isEmpty) return 'Todos os técnicos';

    final coaches = _allCoaches();
    for (final coach in coaches) {
      if (_asString(coach['coach_id']) == _selectedCoachId) {
        final name = _asString(coach['coach_name']);
        return name.isEmpty ? 'Técnico' : name;
      }
    }

    return 'Técnico';
  }

  int _activeFiltersCount() {
    int count = 0;
    if (_selectedMonth.isNotEmpty) count++;
    if (_selectedCoachId.isNotEmpty) count++;
    if (_selectedGender.isNotEmpty) count++;
    return count;
  }

  void _clearFilters() {
    setState(() {
      _selectedMonth = '';
      _selectedCoachId = '';
      _selectedGender = '';
    });
  }

  void _openFiltersBottomSheet() {
    final months = _availableMonths();
    final coaches = _allCoaches();

    String tempMonth = months.contains(_selectedMonth) ? _selectedMonth : '';
    String tempCoach = coaches.any(
      (coach) => _asString(coach['coach_id']) == _selectedCoachId,
    )
        ? _selectedCoachId
        : '';
    String tempGender =
        (_selectedGender == 'feminino' || _selectedGender == 'masculino')
            ? _selectedGender
            : '';

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return SafeArea(
              top: false,
              child: Padding(
                padding: EdgeInsets.only(
                  left: 12,
                  right: 12,
                  bottom: MediaQuery.of(context).viewInsets.bottom + 12,
                ),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(28),
                      bottom: Radius.circular(22),
                    ),
                    border: Border.all(color: olympusBorder),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.14),
                        blurRadius: 24,
                        offset: const Offset(0, -6),
                      ),
                    ],
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Center(
                          child: Container(
                            width: 44,
                            height: 5,
                            decoration: BoxDecoration(
                              color: olympusBorder,
                              borderRadius: BorderRadius.circular(999),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Container(
                              width: 42,
                              height: 42,
                              decoration: BoxDecoration(
                                color: olympusBlue.withOpacity(0.10),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: const Icon(
                                Icons.tune_rounded,
                                color: olympusBlue,
                              ),
                            ),
                            const SizedBox(width: 12),
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Filtros do dashboard',
                                    style: TextStyle(
                                      color: olympusBlue,
                                      fontSize: 18,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  SizedBox(height: 2),
                                  Text(
                                    'Refine por mês, técnico e gênero.',
                                    style: TextStyle(
                                      color: olympusMuted,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        _modernDropdown(
                          label: 'Mês',
                          icon: Icons.calendar_month_rounded,
                          value: months.contains(tempMonth) ? tempMonth : '',
                          items: [
                            const DropdownMenuItem<String>(
                              value: '',
                              child: Text('Todos os meses'),
                            ),
                            ...months.map(
                              (month) => DropdownMenuItem<String>(
                                value: month,
                                child: Text(_monthLabel(month)),
                              ),
                            ),
                          ],
                          onChanged: (value) {
                            setModalState(() {
                              tempMonth = value ?? '';
                            });
                          },
                        ),
                        const SizedBox(height: 12),
                        _modernDropdown(
                          label: 'Técnico',
                          icon: Icons.sports_rounded,
                          value: tempCoach,
                          items: [
                            const DropdownMenuItem<String>(
                              value: '',
                              child: Text('Todos os técnicos'),
                            ),
                            ...coaches.map(
                              (coach) => DropdownMenuItem<String>(
                                value: _asString(coach['coach_id']),
                                child: Text(
                                  _asString(coach['coach_name']),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                          ],
                          onChanged: (value) {
                            setModalState(() {
                              tempCoach = value ?? '';
                            });
                          },
                        ),
                        const SizedBox(height: 12),
                        _modernDropdown(
                          label: 'Gênero',
                          icon: Icons.groups_2_rounded,
                          value: tempGender,
                          items: const [
                            DropdownMenuItem<String>(
                              value: '',
                              child: Text('Todos os gêneros'),
                            ),
                            DropdownMenuItem<String>(
                              value: 'feminino',
                              child: Text('Feminino'),
                            ),
                            DropdownMenuItem<String>(
                              value: 'masculino',
                              child: Text('Masculino'),
                            ),
                          ],
                          onChanged: (value) {
                            setModalState(() {
                              tempGender = value ?? '';
                            });
                          },
                        ),
                        const SizedBox(height: 18),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () {
                                  setModalState(() {
                                    tempMonth = '';
                                    tempCoach = '';
                                    tempGender = '';
                                  });
                                },
                                icon: const Icon(Icons.close_rounded, size: 18),
                                label: const Text('Limpar'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: olympusBlue,
                                  side: const BorderSide(color: olympusBorder),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 13,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: () {
                                  setState(() {
                                    _selectedMonth = tempMonth;
                                    _selectedCoachId = tempCoach;
                                    _selectedGender = tempGender;
                                  });
                                  Navigator.pop(context);
                                },
                                icon: const Icon(Icons.check_rounded, size: 18),
                                label: const Text('Aplicar'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: olympusBlue,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 13,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _modernDropdown({
    required String label,
    required IconData icon,
    required String value,
    required List<DropdownMenuItem<String>> items,
    required ValueChanged<String?> onChanged,
  }) {
    final hasValue = items.any((item) => item.value == value);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: olympusBlue,
            fontSize: 12,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 7),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: olympusBg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: olympusBorder),
          ),
          child: Row(
            children: [
              Icon(icon, color: olympusMuted, size: 19),
              const SizedBox(width: 10),
              Expanded(
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: hasValue ? value : null,
                    isExpanded: true,
                    borderRadius: BorderRadius.circular(14),
                    hint: const Text('Selecione'),
                    items: items,
                    onChanged: onChanged,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFiltersBar() {
    final activeCount = _activeFiltersCount();

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [olympusBlue, olympusLightBlue],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(18),
          bottomRight: Radius.circular(18),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_isNarrow(context))
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Visão geral das programações',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Use filtros para ajustar os gráficos.',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.74),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _openFiltersBottomSheet,
                    icon: const Icon(Icons.tune_rounded, size: 18),
                    label: Text(
                      activeCount == 0
                          ? 'Filtrar dashboard'
                          : 'Filtros ativos ($activeCount)',
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: olympusGold,
                      foregroundColor: olympusBlue,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
              ],
            )
          else
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.white.withOpacity(0.18)),
                  ),
                  child: const Icon(
                    Icons.analytics_outlined,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Visão geral das programações',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Filtros leves, tela limpa e gráficos em destaque.',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.74),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: _openFiltersBottomSheet,
                  icon: const Icon(Icons.tune_rounded, size: 18),
                  label: Text(
                    activeCount == 0 ? 'Filtros' : 'Filtros ($activeCount)',
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: olympusGold,
                    foregroundColor: olympusBlue,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 13,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ],
            ),
          const SizedBox(height: 10),
          _buildActiveFilterChips(),
        ],
      ),
    );
  }

  Widget _buildActiveFilterChips() {
    final chips = <Widget>[];

    chips.add(
      _filterChip(
        icon: Icons.calendar_month_rounded,
        label: _selectedMonthLabel(),
        onDeleted: _selectedMonth.isEmpty
            ? null
            : () {
                setState(() {
                  _selectedMonth = '';
                });
              },
      ),
    );

    chips.add(
      _filterChip(
        icon: Icons.sports_rounded,
        label: _selectedCoachName(),
        onDeleted: _selectedCoachId.isEmpty
            ? null
            : () {
                setState(() {
                  _selectedCoachId = '';
                });
              },
      ),
    );

    chips.add(
      _filterChip(
        icon: Icons.groups_2_rounded,
        label: _genderLabel(_selectedGender),
        onDeleted: _selectedGender.isEmpty
            ? null
            : () {
                setState(() {
                  _selectedGender = '';
                });
              },
      ),
    );

    if (_activeFiltersCount() > 0) {
      chips.add(
        TextButton.icon(
          onPressed: _clearFilters,
          icon: const Icon(Icons.clear_all_rounded, size: 17),
          label: const Text('Limpar'),
          style: TextButton.styleFrom(
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 8),
          ),
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final chip in chips) ...[
            chip,
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }

  Widget _filterChip({
    required IconData icon,
    required String label,
    required VoidCallback? onDeleted,
  }) {
    final isActive = onDeleted != null;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: isActive ? Colors.white : Colors.white.withOpacity(0.15),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: isActive ? Colors.white : Colors.white.withOpacity(0.20),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 16,
            color: isActive ? olympusBlue : Colors.white,
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: isActive ? olympusBlue : Colors.white,
              fontSize: 11.5,
              fontWeight: FontWeight.w900,
            ),
          ),
          if (onDeleted != null) ...[
            const SizedBox(width: 5),
            InkWell(
              borderRadius: BorderRadius.circular(999),
              onTap: onDeleted,
              child: const Icon(
                Icons.close_rounded,
                size: 15,
                color: olympusMuted,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFilters() {
    final months = _availableMonths();
    final coaches = _allCoaches();

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [olympusBlue, olympusLightBlue],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(16),
          bottomRight: Radius.circular(16),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final vertical = constraints.maxWidth < 520;

          final monthDropdown = _whiteDropdown(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String?>(
                value: _safeSelectedMonthValue(months),
                isExpanded: true,
                hint: const Text('Todos os meses'),
                items: [
                  const DropdownMenuItem(
                    value: '',
                    child: Text('Todos os meses'),
                  ),
                  ...months.map((month) {
                    return DropdownMenuItem(
                      value: month,
                      child: Text(_monthLabel(month)),
                    );
                  }),
                ],
                onChanged: (value) {
                  setState(() {
                    _selectedMonth = value ?? '';
                  });
                },
              ),
            ),
          );

          final coachDropdown = _whiteDropdown(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String?>(
                value: _selectedCoachId,
                isExpanded: true,
                items: [
                  const DropdownMenuItem(
                    value: '',
                    child: Text('Todos os técnicos'),
                  ),
                  ...coaches.map((coach) {
                    return DropdownMenuItem(
                      value: _asString(coach['coach_id']),
                      child: Text(
                        _asString(coach['coach_name']),
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                  }),
                ],
                onChanged: (value) {
                  setState(() {
                    _selectedCoachId = value ?? '';
                  });
                },
              ),
            ),
          );

          final genderDropdown = _whiteDropdown(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _selectedGender,
                isExpanded: true,
                items: const [
                  DropdownMenuItem(
                    value: '',
                    child: Text('Todos os gêneros'),
                  ),
                  DropdownMenuItem(
                    value: 'feminino',
                    child: Text('Feminino'),
                  ),
                  DropdownMenuItem(
                    value: 'masculino',
                    child: Text('Masculino'),
                  ),
                ],
                onChanged: (value) {
                  setState(() {
                    _selectedGender = value ?? '';
                  });
                },
              ),
            ),
          );

          final button = ElevatedButton.icon(
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const AdminTrainingPlansListPage(),
                ),
              );
              await _loadDashboard();
            },
            icon: const Icon(Icons.list_alt_rounded, size: 18),
            label: const Text('Ver treinos'),
            style: ElevatedButton.styleFrom(
              backgroundColor: olympusGold,
              foregroundColor: olympusBlue,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 15),
            ),
          );

          if (vertical) {
            return Column(
              children: [
                SizedBox(width: double.infinity, child: monthDropdown),
                const SizedBox(height: 10),
                SizedBox(width: double.infinity, child: coachDropdown),
                const SizedBox(height: 10),
                SizedBox(width: double.infinity, child: genderDropdown),
                const SizedBox(height: 10),
                SizedBox(width: double.infinity, child: button),
              ],
            );
          }

          return Row(
            children: [
              Expanded(child: monthDropdown),
              const SizedBox(width: 10),
              Expanded(child: coachDropdown),
              const SizedBox(width: 10),
              Expanded(child: genderDropdown),
              const SizedBox(width: 10),
              button,
            ],
          );
        },
      ),
    );
  }

  Widget _whiteDropdown({required Widget child}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: child,
    );
  }

  Widget _buildSummary(List<Map<String, dynamic>> events) {
    int totalPlans = 0;
    int totalBlocks = 0;
    int totalMinutes = 0;

    for (final event in events) {
      final plans = _plansForEvent(_asString(event['id']));
      totalPlans += plans.length;

      for (final plan in plans) {
        final blocks = List<Map<String, dynamic>>.from(plan['blocks'] as List);
        totalBlocks += blocks.length;
        totalMinutes += (plan['total_minutes'] ?? 0) as int;
      }
    }

    final cards = [
      _summaryCard(
        icon: Icons.fitness_center,
        label: 'Treinos',
        value: events.length.toString(),
        color: olympusBlue,
      ),
      _summaryCard(
        icon: Icons.person,
        label: 'Programações',
        value: totalPlans.toString(),
        color: olympusPurple,
      ),
      _summaryCard(
        icon: Icons.view_agenda_outlined,
        label: 'Blocos',
        value: totalBlocks.toString(),
        color: olympusGold,
      ),
      _summaryCard(
        icon: Icons.timer_outlined,
        label: 'Tempo',
        value: _formatDuration(totalMinutes),
        color: olympusSuccess,
      ),
    ];

    if (_isNarrow(context)) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(child: cards[0]),
                const SizedBox(width: 8),
                Expanded(child: cards[1]),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: cards[2]),
                const SizedBox(width: 8),
                Expanded(child: cards[3]),
              ],
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
      child: Row(
        children: [
          Expanded(child: cards[0]),
          const SizedBox(width: 8),
          Expanded(child: cards[1]),
          const SizedBox(width: 8),
          Expanded(child: cards[2]),
          const SizedBox(width: 8),
          Expanded(child: cards[3]),
        ],
      ),
    );
  }

  Widget _summaryCard({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: _cardDecoration(),
      child: Column(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 17,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: olympusMuted,
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title, {String? subtitle, IconData? icon}) {
    return Row(
      children: [
        if (icon != null) ...[
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: olympusBlue.withOpacity(0.08),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(icon, color: olympusBlue, size: 18),
          ),
          const SizedBox(width: 9),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: olympusBlue,
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: olympusMuted,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _premiumQuickSummary(List<Map<String, dynamic>> events) {
    final plans = _filteredPlansForSummary(events);
    int totalBlocks = 0;
    int totalMinutes = 0;

    for (final plan in plans) {
      final blocks = List<Map<String, dynamic>>.from(plan['blocks'] as List);
      totalBlocks += blocks.length;
      totalMinutes += (plan['total_minutes'] ?? 0) as int;
    }

    String topFoundation = '—';
    final byFoundation = _timeByField(plans, 'type');
    if (byFoundation.isNotEmpty) {
      topFoundation = byFoundation.entries.first.key;
    }

    String topCoach = '—';
    final comparison = _coachComparisonByFoundation(plans);
    if (comparison.isNotEmpty) {
      final ranked = comparison.entries.toList()
        ..sort((a, b) {
          final at = a.value.values.fold<int>(0, (sum, v) => sum + v);
          final bt = b.value.values.fold<int>(0, (sum, v) => sum + v);
          return bt.compareTo(at);
        });
      topCoach = ranked.first.key;
    }

    final cards = [
      _premiumMetricCard(
        label: 'Treinos',
        value: events.length.toString(),
        icon: Icons.fitness_center_rounded,
        color: olympusBlue,
      ),
      _premiumMetricCard(
        label: 'Tempo',
        value: _formatDuration(totalMinutes),
        icon: Icons.timer_rounded,
        color: olympusSuccess,
      ),
      _premiumMetricCard(
        label: 'Blocos',
        value: totalBlocks.toString(),
        icon: Icons.dashboard_customize_rounded,
        color: olympusGold,
      ),
      _premiumMetricCard(
        label: 'Top técnico',
        value: topCoach,
        icon: Icons.emoji_events_rounded,
        color: olympusPurple,
        compactText: true,
      ),
      _premiumMetricCard(
        label: 'Top fundamento',
        value: topFoundation,
        icon: Icons.sports_volleyball_rounded,
        color: olympusWarning,
        compactText: true,
      ),
    ];

    return Scrollbar(
      controller: _quickSummaryScrollController,
      thumbVisibility: true,
      interactive: true,
      child: SizedBox(
        height: 124,
        child: ListView.separated(
          controller: _quickSummaryScrollController,
          padding: const EdgeInsets.only(bottom: 12),
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          itemCount: cards.length,
          separatorBuilder: (_, __) => const SizedBox(width: 10),
          itemBuilder: (context, index) => cards[index],
        ),
      ),
    );
  }

  Widget _premiumMetricCard({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
    bool compactText = false,
  }) {
    return Container(
      width: compactText ? 164 : 126,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: olympusBorder),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.07),
            blurRadius: 14,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: color.withOpacity(0.10),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 19),
          ),
          const Spacer(),
          Text(
            value,
            maxLines: compactText ? 1 : 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color,
              fontSize: compactText ? 13 : 17,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: olympusMuted,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  void _showDrillDown({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required List<Map<String, dynamic>> items,
  }) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return SafeArea(
          top: false,
          child: DraggableScrollableSheet(
            initialChildSize: 0.72,
            minChildSize: 0.42,
            maxChildSize: 0.92,
            builder: (context, scrollController) {
              return Container(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 44,
                        height: 5,
                        decoration: BoxDecoration(
                          color: olympusBorder,
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: color.withOpacity(0.10),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Icon(icon, color: color),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title,
                                style: const TextStyle(
                                  color: olympusBlue,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                subtitle,
                                style: const TextStyle(
                                  color: olympusMuted,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Expanded(
                      child: items.isEmpty
                          ? const Center(
                              child: Text(
                                'Nenhum detalhe encontrado para este filtro.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: olympusMuted,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            )
                          : ListView.separated(
                              controller: scrollController,
                              itemCount: items.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 10),
                              itemBuilder: (context, index) {
                                final item = items[index];
                                final minutes = item['minutes'] as int? ?? 0;
                                final description =
                                    _asString(item['description']);
                                final extra = _asString(item['extra']);

                                return Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: olympusBg,
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(color: olympusBorder),
                                  ),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Container(
                                        width: 32,
                                        height: 32,
                                        decoration: BoxDecoration(
                                          color: color.withOpacity(0.10),
                                          borderRadius:
                                              BorderRadius.circular(11),
                                        ),
                                        child: Center(
                                          child: Text(
                                            '${index + 1}',
                                            style: TextStyle(
                                              color: color,
                                              fontSize: 11,
                                              fontWeight: FontWeight.w900,
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              _asString(item['title']),
                                              style: const TextStyle(
                                                color: olympusBlue,
                                                fontSize: 13.5,
                                                fontWeight: FontWeight.w900,
                                              ),
                                            ),
                                            if (description.isNotEmpty) ...[
                                              const SizedBox(height: 3),
                                              Text(
                                                description,
                                                style: const TextStyle(
                                                  color: olympusMuted,
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                            ],
                                            if (extra.isNotEmpty) ...[
                                              const SizedBox(height: 5),
                                              Text(
                                                extra,
                                                style: const TextStyle(
                                                  color: olympusSubtle,
                                                  fontSize: 11.5,
                                                  fontWeight: FontWeight.w600,
                                                  height: 1.25,
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        _formatDuration(minutes),
                                        style: TextStyle(
                                          color: color,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w900,
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
              );
            },
          ),
        );
      },
    );
  }

  List<Map<String, dynamic>> _drillDownItemsForField(
    List<Map<String, dynamic>> plans,
    String field,
    String value,
  ) {
    final items = <Map<String, dynamic>>[];

    for (final plan in plans) {
      final coachName = _asString(plan['coach_name']).isEmpty
          ? 'Técnico'
          : _asString(plan['coach_name']);
      final blocks = List<Map<String, dynamic>>.from(plan['blocks'] as List);

      for (final block in blocks) {
        final label = _asString(block[field]).isEmpty
            ? 'Não informado'
            : _asString(block[field]);

        if (label != value) continue;

        final minutes = _blockMinutes(block);
        if (minutes <= 0) continue;

        final type = _asString(block['type']);
        final category = _asString(block['category']);
        final start = _normalizeTime(block['start_time']);
        final end = _normalizeTime(block['end_time']);
        final observation = _asString(block['observation']);

        items.add({
          'title': type.isEmpty ? label : type,
          'description':
              '$coachName • ${category.isEmpty ? 'Sem categoria' : category}',
          'extra': [
            if (start.isNotEmpty || end.isNotEmpty)
              '${start.isEmpty ? '--:--' : start} às ${end.isEmpty ? '--:--' : end}',
            if (observation.isNotEmpty) observation,
          ].join(' • '),
          'minutes': minutes,
        });
      }
    }

    items.sort((a, b) => (b['minutes'] as int).compareTo(a['minutes'] as int));
    return items;
  }

  List<Map<String, dynamic>> _drillDownItemsForCoach(
    List<Map<String, dynamic>> plans,
    String coachNameFilter,
  ) {
    final items = <Map<String, dynamic>>[];

    for (final plan in plans) {
      final coachName = _asString(plan['coach_name']).isEmpty
          ? 'Técnico'
          : _asString(plan['coach_name']);

      if (coachName != coachNameFilter) continue;

      final blocks = List<Map<String, dynamic>>.from(plan['blocks'] as List);

      for (final block in blocks) {
        final minutes = _blockMinutes(block);
        if (minutes <= 0) continue;

        final type = _asString(block['type']);
        final category = _asString(block['category']);
        final start = _normalizeTime(block['start_time']);
        final end = _normalizeTime(block['end_time']);
        final observation = _asString(block['observation']);

        items.add({
          'title': type.isEmpty ? 'Bloco de treino' : type,
          'description': category.isEmpty ? 'Sem categoria' : category,
          'extra': [
            if (start.isNotEmpty || end.isNotEmpty)
              '${start.isEmpty ? '--:--' : start} às ${end.isEmpty ? '--:--' : end}',
            if (observation.isNotEmpty) observation,
          ].join(' • '),
          'minutes': minutes,
        });
      }
    }

    items.sort((a, b) => (b['minutes'] as int).compareTo(a['minutes'] as int));
    return items;
  }

  Widget _premiumHorizontalFoundations(List<Map<String, dynamic>> plans) {
    final data = _timeByField(plans, 'type');
    final entries = data.entries.toList();

    if (entries.isEmpty) {
      return _emptyPremiumCard('Nenhum fundamento encontrado.');
    }

    final maxValue = entries.first.value;

    return Scrollbar(
      controller: _foundationsScrollController,
      thumbVisibility: true,
      interactive: true,
      child: SizedBox(
        height: 150,
        child: ListView.separated(
          controller: _foundationsScrollController,
          padding: const EdgeInsets.only(bottom: 12),
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          itemCount: entries.length,
          separatorBuilder: (_, __) => const SizedBox(width: 10),
          itemBuilder: (context, index) {
            final entry = entries[index];
            final percent = maxValue <= 0 ? 0.0 : entry.value / maxValue;

            return _premiumDataCard(
              title: entry.key,
              value: _formatDuration(entry.value),
              icon: Icons.sports_volleyball_rounded,
              color: olympusPurple,
              percent: percent,
              rank: index + 1,
              onTap: () => _showDrillDown(
                title: entry.key,
                subtitle: 'Blocos de treino deste fundamento',
                icon: Icons.sports_volleyball_rounded,
                color: olympusPurple,
                items: _drillDownItemsForField(plans, 'type', entry.key),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _premiumHorizontalCategories(List<Map<String, dynamic>> plans) {
    final data = _timeByField(plans, 'category');
    final entries = data.entries.toList();

    if (entries.isEmpty) {
      return _emptyPremiumCard('Nenhuma categoria encontrada.');
    }

    final maxValue = entries.first.value;

    return Scrollbar(
      controller: _categoriesScrollController,
      thumbVisibility: true,
      interactive: true,
      child: SizedBox(
        height: 144,
        child: ListView.separated(
          controller: _categoriesScrollController,
          padding: const EdgeInsets.only(bottom: 12),
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          itemCount: entries.length,
          separatorBuilder: (_, __) => const SizedBox(width: 10),
          itemBuilder: (context, index) {
            final entry = entries[index];
            final percent = maxValue <= 0 ? 0.0 : entry.value / maxValue;

            return _premiumDataCard(
              title: entry.key,
              value: _formatDuration(entry.value),
              icon: Icons.category_rounded,
              color: olympusBlue,
              percent: percent,
              rank: index + 1,
              onTap: () => _showDrillDown(
                title: entry.key,
                subtitle: 'Blocos de treino desta categoria',
                icon: Icons.category_rounded,
                color: olympusBlue,
                items: _drillDownItemsForField(plans, 'category', entry.key),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _premiumHorizontalCoaches(List<Map<String, dynamic>> plans) {
    final comparison = _coachComparisonByFoundation(plans);

    if (comparison.isEmpty) {
      return _emptyPremiumCard('Nenhum técnico encontrado.');
    }

    final entries = comparison.entries.map((entry) {
      final total =
          entry.value.values.fold<int>(0, (sum, value) => sum + value);
      return MapEntry(entry.key, total);
    }).toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final maxValue = entries.first.value;

    return Scrollbar(
      controller: _coachesScrollController,
      thumbVisibility: true,
      interactive: true,
      child: SizedBox(
        height: 150,
        child: ListView.separated(
          controller: _coachesScrollController,
          padding: const EdgeInsets.only(bottom: 12),
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          itemCount: entries.length,
          separatorBuilder: (_, __) => const SizedBox(width: 10),
          itemBuilder: (context, index) {
            final entry = entries[index];
            final percent = maxValue <= 0 ? 0.0 : entry.value / maxValue;

            final cardColor = index == 0 ? olympusGold : olympusBlue;

            return _premiumDataCard(
              title: entry.key,
              value: _formatDuration(entry.value),
              icon: Icons.person_rounded,
              color: cardColor,
              percent: percent,
              rank: index + 1,
              onTap: () => _showDrillDown(
                title: entry.key,
                subtitle: 'Blocos programados por este técnico',
                icon: Icons.person_rounded,
                color: cardColor,
                items: _drillDownItemsForCoach(plans, entry.key),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _premiumDataCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
    required double percent,
    required int rank,
    VoidCallback? onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          width: 158,
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: olympusBorder),
            boxShadow: [
              BoxShadow(
                color: color.withOpacity(0.06),
                blurRadius: 14,
                offset: const Offset(0, 7),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.10),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon, color: color, size: 18),
                  ),
                  const Spacer(),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.09),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '$rankº',
                      style: TextStyle(
                        color: color,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: olympusText,
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: TextStyle(
                  color: color,
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const Spacer(),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: Container(
                  height: 8,
                  color: color.withOpacity(0.10),
                  child: FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: percent.clamp(0.0, 1.0),
                    child: Container(color: color.withOpacity(0.78)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _premiumGoalsCard(List<Map<String, dynamic>> plans) {
    final data = _timeByCategoryWithGoals(plans);
    final total = data.values.fold<int>(0, (sum, value) => sum + value);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(
            'Metas',
            subtitle: 'Real x planejado por categoria',
            icon: Icons.track_changes_rounded,
          ),
          const SizedBox(height: 13),
          if (total <= 0)
            const Text(
              'Sem tempo cadastrado para comparar com a meta.',
              style: TextStyle(
                color: olympusMuted,
                fontWeight: FontWeight.w600,
              ),
            )
          else
            ...data.entries.map((entry) {
              final category = entry.key;
              final minutes = entry.value;
              final actual = total <= 0 ? 0.0 : (minutes / total) * 100;
              final goal = (_categoryGoals[category] ?? 0).toDouble();
              final delta = actual - goal;

              Color color;
              String status;

              if (goal == 0) {
                color = olympusMuted;
                status = 'sem meta';
              } else if (delta.abs() <= 5) {
                color = olympusSuccess;
                status = 'dentro';
              } else if (delta > 5) {
                color = olympusWarning;
                status = 'acima';
              } else {
                color = olympusDanger;
                status = 'abaixo';
              }

              return Container(
                margin: const EdgeInsets.only(bottom: 11),
                padding: const EdgeInsets.all(11),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.055),
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(color: color.withOpacity(0.13)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            category,
                            style: const TextStyle(
                              color: olympusBlue,
                              fontSize: 13,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        _statusPill(status, color),
                      ],
                    ),
                    const SizedBox(height: 7),
                    Row(
                      children: [
                        Text(
                          '${actual.toStringAsFixed(1)}%',
                          style: TextStyle(
                            color: color,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'meta ${goal.toStringAsFixed(0)}% • ${_formatDuration(minutes)}',
                          style: const TextStyle(
                            color: olympusMuted,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _percentBar('Real', actual, color),
                    const SizedBox(height: 6),
                    _percentBar('Meta', goal, olympusBlue),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _emptyPremiumCard(String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: _cardDecoration(),
      child: Text(
        message,
        style: const TextStyle(
          color: olympusMuted,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _smartInsightsCard(
    List<Map<String, dynamic>> events,
    List<Map<String, dynamic>> plans,
  ) {
    int totalMinutes = 0;
    int totalBlocks = 0;

    for (final plan in plans) {
      totalMinutes += (plan['total_minutes'] ?? 0) as int;
      final blocks = List<Map<String, dynamic>>.from(plan['blocks'] as List);
      totalBlocks += blocks.length;
    }

    final byCategory = _timeByCategoryWithGoals(plans);
    final totalCategoryMinutes =
        byCategory.values.fold<int>(0, (sum, value) => sum + value);

    final insights = <Map<String, dynamic>>[];

    if (events.isEmpty || plans.isEmpty) {
      insights.add({
        'icon': Icons.info_outline_rounded,
        'title': 'Sem programação suficiente',
        'text': 'Ainda não há dados suficientes para gerar alertas.',
        'color': olympusMuted,
      });
    } else {
      final averagePerTraining =
          events.isEmpty ? 0 : totalMinutes ~/ events.length;
      insights.add({
        'icon': Icons.timer_rounded,
        'title': 'Média por treino',
        'text':
            'Cada treino tem em média ${_formatDuration(averagePerTraining)} planejados.',
        'color': olympusBlue,
      });

      if (totalBlocks > 0 && events.isNotEmpty) {
        final averageBlocks = totalBlocks / events.length;
        insights.add({
          'icon': Icons.dashboard_customize_rounded,
          'title': 'Volume de blocos',
          'text':
              'Média de ${averageBlocks.toStringAsFixed(1)} bloco(s) por treino.',
          'color': olympusPurple,
        });
      }

      for (final entry in byCategory.entries) {
        final goal = _categoryGoals[entry.key];
        if (goal == null || totalCategoryMinutes <= 0) continue;

        final actual = (entry.value / totalCategoryMinutes) * 100;
        final delta = actual - goal;

        if (delta.abs() > 10) {
          insights.add({
            'icon': delta > 0
                ? Icons.trending_up_rounded
                : Icons.trending_down_rounded,
            'title': '${entry.key} fora da meta',
            'text':
                '${actual.toStringAsFixed(1)}% real contra ${goal.toStringAsFixed(0)}% de meta.',
            'color': delta > 0 ? olympusWarning : olympusDanger,
          });
        }
      }

      final byCoach = _coachComparisonByFoundation(plans);
      if (byCoach.length > 1) {
        final ranked = byCoach.entries.map((entry) {
          final total =
              entry.value.values.fold<int>(0, (sum, value) => sum + value);
          return MapEntry(entry.key, total);
        }).toList()
          ..sort((a, b) => b.value.compareTo(a.value));

        if (ranked.isNotEmpty) {
          insights.add({
            'icon': Icons.emoji_events_rounded,
            'title': 'Técnico com maior volume',
            'text':
                '${ranked.first.key} lidera com ${_formatDuration(ranked.first.value)}.',
            'color': olympusGold,
          });
        }
      }
    }

    final visibleInsights = insights.take(5).toList();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(
            'Insights automáticos',
            subtitle: 'Leitura rápida dos dados do filtro atual',
            icon: Icons.auto_awesome_rounded,
          ),
          const SizedBox(height: 12),
          ...visibleInsights.map((insight) {
            final color = insight['color'] as Color;
            return Container(
              margin: const EdgeInsets.only(bottom: 9),
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                color: color.withOpacity(0.07),
                borderRadius: BorderRadius.circular(15),
                border: Border.all(color: color.withOpacity(0.14)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(insight['icon'] as IconData, color: color, size: 20),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          insight['title'].toString(),
                          style: TextStyle(
                            color: color,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          insight['text'].toString(),
                          style: const TextStyle(
                            color: olympusMuted,
                            fontSize: 11.8,
                            fontWeight: FontWeight.w600,
                            height: 1.25,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _weeklyHeatmapCard(List<Map<String, dynamic>> events) {
    final totals = <int, int>{
      DateTime.monday: 0,
      DateTime.tuesday: 0,
      DateTime.wednesday: 0,
      DateTime.thursday: 0,
      DateTime.friday: 0,
      DateTime.saturday: 0,
      DateTime.sunday: 0,
    };

    for (final event in events) {
      final date = _parseEventDate(event);
      if (date == null) continue;

      int minutes = 0;
      for (final plan in _plansForEvent(_asString(event['id']))) {
        minutes += (plan['total_minutes'] ?? 0) as int;
      }

      totals[date.weekday] = (totals[date.weekday] ?? 0) + minutes;
    }

    final maxValue = totals.values.isEmpty
        ? 0
        : totals.values.reduce((a, b) => a > b ? a : b);

    const labels = {
      DateTime.monday: 'Seg',
      DateTime.tuesday: 'Ter',
      DateTime.wednesday: 'Qua',
      DateTime.thursday: 'Qui',
      DateTime.friday: 'Sex',
      DateTime.saturday: 'Sáb',
      DateTime.sunday: 'Dom',
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(
            'Mapa semanal',
            subtitle: 'Distribuição do volume por dia da semana',
            icon: Icons.calendar_view_week_rounded,
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: labels.entries.map((entry) {
              final minutes = totals[entry.key] ?? 0;
              final percent = maxValue <= 0 ? 0.0 : minutes / maxValue;
              final height = 34.0 + (74.0 * percent);

              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(
                        _formatDuration(minutes),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: olympusMuted,
                          fontSize: 9.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 6),
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 220),
                        height: height,
                        decoration: BoxDecoration(
                          color: minutes == 0
                              ? olympusBorder.withOpacity(0.65)
                              : olympusBlue
                                  .withOpacity(0.18 + (0.62 * percent)),
                          borderRadius: BorderRadius.circular(13),
                          border: Border.all(
                            color: minutes == 0
                                ? olympusBorder
                                : olympusBlue.withOpacity(0.20),
                          ),
                        ),
                      ),
                      const SizedBox(height: 7),
                      Text(
                        entry.value,
                        style: const TextStyle(
                          color: olympusBlue,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildDashboard(List<Map<String, dynamic>> events) {
    final plans = _filteredPlansForSummary(events);

    if (events.isEmpty || plans.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Text(
            'Nenhuma programação de treino encontrada para os filtros atuais.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: olympusMuted,
              fontWeight: FontWeight.w700,
              fontSize: _isMobile(context) ? 14 : 15,
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 100),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(
            'Resumo rápido',
            subtitle: 'Principais indicadores do filtro atual',
            icon: Icons.bolt_rounded,
          ),
          const SizedBox(height: 10),
          _premiumQuickSummary(events),
          const SizedBox(height: 18),
          _smartInsightsCard(events, plans),
          const SizedBox(height: 18),
          _weeklyHeatmapCard(events),
          const SizedBox(height: 18),
          _sectionTitle(
            'Categorias',
            subtitle: 'Distribuição do tempo por tipo de treino',
            icon: Icons.category_rounded,
          ),
          const SizedBox(height: 10),
          _premiumHorizontalCategories(plans),
          const SizedBox(height: 18),
          _sectionTitle(
            'Fundamentos',
            subtitle: 'Conteúdos mais treinados no período',
            icon: Icons.sports_volleyball_rounded,
          ),
          const SizedBox(height: 10),
          _premiumHorizontalFoundations(plans),
          const SizedBox(height: 18),
          _sectionTitle(
            'Técnicos',
            subtitle: 'Ranking por volume de tempo programado',
            icon: Icons.groups_rounded,
          ),
          const SizedBox(height: 10),
          _premiumHorizontalCoaches(plans),
          const SizedBox(height: 18),
          _premiumGoalsCard(plans),
          const SizedBox(height: 12),
          _trendCard(events),
        ],
      ),
    );
  }

  Widget _openListCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: olympusBlue,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: olympusBlue.withOpacity(0.08)),
        boxShadow: [
          BoxShadow(
            color: olympusBlue.withOpacity(0.12),
            blurRadius: 14,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: _isNarrow(context)
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.14),
                        borderRadius: BorderRadius.circular(13),
                      ),
                      child: const Icon(
                        Icons.list_alt_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Treinos programados',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Abra a lista completa com filtros por técnico e mês.',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.76),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) =>
                              const AdminTrainingPlansListPage(),
                        ),
                      );
                      await _loadDashboard();
                    },
                    icon: const Icon(Icons.open_in_new_rounded, size: 18),
                    label: const Text('Acessar lista'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: olympusBlue,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(13),
                      ),
                    ),
                  ),
                ),
              ],
            )
          : Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.14),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.list_alt_rounded,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Treinos programados',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'Lista completa com filtros por técnico, mês e todos os meses.',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.74),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) =>
                            const AdminTrainingPlansListPage(),
                      ),
                    );
                    await _loadDashboard();
                  },
                  icon: const Icon(Icons.open_in_new_rounded, size: 18),
                  label: const Text('Acessar'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: olympusBlue,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(13),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _barChartCard({
    required String title,
    required String subtitle,
    required Map<String, int> data,
    required IconData icon,
    required Color color,
  }) {
    final max =
        data.values.isEmpty ? 0 : data.values.reduce((a, b) => a > b ? a : b);
    final total = data.values.fold<int>(0, (sum, value) => sum + value);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(
            icon: icon,
            title: title,
            subtitle: subtitle,
            color: color,
            trailing: _formatDuration(total),
          ),
          const SizedBox(height: 13),
          if (data.isEmpty)
            const Text(
              'Sem dados para exibir.',
              style: TextStyle(
                color: olympusMuted,
                fontWeight: FontWeight.w600,
              ),
            )
          else
            ...data.entries.map((entry) {
              final percent = max <= 0 ? 0.0 : entry.value / max;

              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _chartBar(
                  label: entry.key,
                  minutes: entry.value,
                  percent: percent,
                  color: color,
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _coachComparisonCard(List<Map<String, dynamic>> plans) {
    final comparison = _coachComparisonByFoundation(plans);

    final allFoundations = <String>{};
    for (final data in comparison.values) {
      allFoundations.addAll(data.keys);
    }

    final foundations = allFoundations.toList()
      ..sort((a, b) {
        int totalA = 0;
        int totalB = 0;
        for (final data in comparison.values) {
          totalA += data[a] ?? 0;
          totalB += data[b] ?? 0;
        }
        return totalB.compareTo(totalA);
      });

    final topFoundations = foundations.take(5).toList();

    int max = 0;
    final coachTotals = <String, int>{};

    for (final entry in comparison.entries) {
      final total =
          entry.value.values.fold<int>(0, (sum, value) => sum + value);
      coachTotals[entry.key] = total;
      if (total > max) max = total;
    }

    final rankedCoaches = coachTotals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(
            icon: Icons.emoji_events_outlined,
            title: 'Ranking dos técnicos',
            subtitle: 'Comparação de tempo por fundamento',
            color: olympusGold,
          ),
          const SizedBox(height: 12),
          if (comparison.isEmpty)
            const Text(
              'Sem dados para comparar.',
              style: TextStyle(
                color: olympusMuted,
                fontWeight: FontWeight.w600,
              ),
            )
          else ...[
            ...rankedCoaches.asMap().entries.map((rankEntry) {
              final index = rankEntry.key;
              final coachName = rankEntry.value.key;
              final totalMinutes = rankEntry.value.value;
              final data = comparison[coachName] ?? {};
              final percent = max <= 0 ? 0.0 : totalMinutes / max;
              final medalColor = index == 0
                  ? olympusGold
                  : index == 1
                      ? olympusMuted
                      : index == 2
                          ? olympusWarning
                          : olympusBlue;

              final topCoachFoundations = data.entries.toList()
                ..sort((a, b) => b.value.compareTo(a.value));

              return Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 11),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: index == 0 ? olympusGold.withOpacity(0.08) : olympusBg,
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(
                    color: index == 0
                        ? olympusGold.withOpacity(0.24)
                        : olympusBorder,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_isNarrow(context))
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              _rankBadge(index + 1, medalColor),
                              const SizedBox(width: 9),
                              Expanded(
                                child: Text(
                                  coachName,
                                  style: const TextStyle(
                                    color: olympusBlue,
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 5),
                          Text(
                            _formatDuration(totalMinutes),
                            style: TextStyle(
                              color: medalColor,
                              fontSize: 12,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      )
                    else
                      Row(
                        children: [
                          _rankBadge(index + 1, medalColor),
                          const SizedBox(width: 9),
                          Expanded(
                            child: Text(
                              coachName,
                              style: const TextStyle(
                                color: olympusBlue,
                                fontSize: 13.5,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          Text(
                            _formatDuration(totalMinutes),
                            style: TextStyle(
                              color: medalColor,
                              fontSize: 12,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
                    const SizedBox(height: 9),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: Container(
                        height: 11,
                        color: medalColor.withOpacity(0.10),
                        child: FractionallySizedBox(
                          alignment: Alignment.centerLeft,
                          widthFactor: percent.clamp(0.0, 1.0),
                          child: Container(color: medalColor.withOpacity(0.76)),
                        ),
                      ),
                    ),
                    if (topCoachFoundations.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 7,
                        runSpacing: 7,
                        children: topCoachFoundations.take(3).map((foundation) {
                          return Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(color: olympusBorder),
                            ),
                            child: Text(
                              '${foundation.key}: ${_formatDuration(foundation.value)}',
                              style: const TextStyle(
                                color: olympusMuted,
                                fontSize: 10.8,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ],
                ),
              );
            }),
            if (topFoundations.isNotEmpty) ...[
              const SizedBox(height: 2),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(11),
                decoration: BoxDecoration(
                  color: olympusBlue.withOpacity(0.04),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: olympusBorder),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Fundamentos mais usados no filtro atual',
                      style: TextStyle(
                        color: olympusBlue,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 9),
                    Wrap(
                      spacing: 7,
                      runSpacing: 7,
                      children: topFoundations.map((foundation) {
                        int total = 0;
                        for (final data in comparison.values) {
                          total += data[foundation] ?? 0;
                        }

                        return Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 9,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: olympusGold.withOpacity(0.10),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: olympusGold.withOpacity(0.22),
                            ),
                          ),
                          child: Text(
                            '$foundation • ${_formatDuration(total)}',
                            style: const TextStyle(
                              color: olympusBlue,
                              fontSize: 10.8,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _rankBadge(int rank, Color color) {
    return Container(
      width: 31,
      height: 31,
      decoration: BoxDecoration(
        color: color.withOpacity(0.13),
        shape: BoxShape.circle,
        border: Border.all(color: color.withOpacity(0.28)),
      ),
      child: Center(
        child: Text(
          '$rankº',
          style: TextStyle(
            color: color,
            fontSize: 11,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }

  Widget _goalCard(List<Map<String, dynamic>> plans) {
    final data = _timeByCategoryWithGoals(plans);
    final total = data.values.fold<int>(0, (sum, value) => sum + value);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(
            icon: Icons.track_changes_rounded,
            title: 'Metas por categoria',
            subtitle: 'Real x planejado com alerta visual',
            color: olympusSuccess,
            trailing: total > 0 ? _formatDuration(total) : null,
          ),
          const SizedBox(height: 12),
          if (data.isEmpty || total <= 0)
            const Text(
              'Sem tempo cadastrado para comparar com a meta.',
              style: TextStyle(
                color: olympusMuted,
                fontWeight: FontWeight.w600,
              ),
            )
          else
            ...data.entries.map((entry) {
              final category = entry.key;
              final minutes = entry.value;
              final actual = total <= 0 ? 0.0 : (minutes / total) * 100;
              final goal = (_categoryGoals[category] ?? 0).toDouble();
              final delta = actual - goal;

              Color statusColor;
              String statusText;

              if (goal == 0) {
                statusColor = olympusMuted;
                statusText = 'sem meta';
              } else if (delta.abs() <= 5) {
                statusColor = olympusSuccess;
                statusText = 'dentro da meta';
              } else if (delta > 5) {
                statusColor = olympusWarning;
                statusText = '+${delta.toStringAsFixed(1)}pp';
              } else {
                statusColor = olympusDanger;
                statusText = '${delta.toStringAsFixed(1)}pp';
              }

              return Container(
                margin: const EdgeInsets.only(bottom: 11),
                padding: const EdgeInsets.all(11),
                decoration: BoxDecoration(
                  color: olympusBg,
                  borderRadius: BorderRadius.circular(13),
                  border: Border.all(color: olympusBorder),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_isNarrow(context))
                      Column(
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
                          const SizedBox(height: 4),
                          Text(
                            '${_formatDuration(minutes)} • ${actual.toStringAsFixed(1)}% real • ${goal.toStringAsFixed(0)}% meta',
                            style: const TextStyle(
                              color: olympusMuted,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 5),
                          _statusPill(statusText, statusColor),
                        ],
                      )
                    else
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              category,
                              style: const TextStyle(
                                color: olympusBlue,
                                fontSize: 13,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          Text(
                            '${_formatDuration(minutes)} • ${actual.toStringAsFixed(1)}% real • ${goal.toStringAsFixed(0)}% meta',
                            style: const TextStyle(
                              color: olympusMuted,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(width: 8),
                          _statusPill(statusText, statusColor),
                        ],
                      ),
                    const SizedBox(height: 10),
                    _percentBar('Real', actual, statusColor),
                    const SizedBox(height: 7),
                    _percentBar('Meta', goal, olympusBlue),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _trendCard(List<Map<String, dynamic>> events) {
    final data = _trendByPeriod(events);
    final max =
        data.values.isEmpty ? 0 : data.values.reduce((a, b) => a > b ? a : b);
    final total = data.values.fold<int>(0, (sum, value) => sum + value);
    final average = data.isEmpty ? 0 : (total / data.length).round();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(
            icon: Icons.show_chart_rounded,
            title: 'Evolução do planejamento',
            subtitle: 'Volume de treino distribuído no tempo',
            color: olympusPurple,
            trailing: total > 0 ? _formatDuration(total) : null,
          ),
          const SizedBox(height: 12),
          if (data.isNotEmpty)
            Row(
              children: [
                Expanded(
                  child: _trendMetric(
                    label: _trendMode == TrendMode.weekly ? 'Semanas' : 'Meses',
                    value: data.length.toString(),
                    icon: Icons.date_range_rounded,
                    color: olympusBlue,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _trendMetric(
                    label: 'Média',
                    value: _formatDuration(average),
                    icon: Icons.speed_rounded,
                    color: olympusPurple,
                  ),
                ),
              ],
            ),
          if (data.isNotEmpty) const SizedBox(height: 12),
          _trendToggle(),
          const SizedBox(height: 12),
          if (data.isEmpty)
            const Text(
              'Sem dados de evolução para o filtro atual.',
              style: TextStyle(
                color: olympusMuted,
                fontWeight: FontWeight.w600,
              ),
            )
          else
            Container(
              padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
              decoration: BoxDecoration(
                color: olympusPurple.withOpacity(0.035),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: olympusPurple.withOpacity(0.08)),
              ),
              child: SizedBox(
                height: _isMobile(context) ? 220 : 260,
                child: _TrendChart(
                  data: data,
                  maxValue: max,
                  barColor: olympusPurple,
                  labelFormatter: _trendLabel,
                  valueFormatter: _formatDuration,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _trendMetric({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.12)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: color,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  label,
                  style: const TextStyle(
                    color: olympusMuted,
                    fontSize: 10.5,
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

  Widget _trendToggle() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: olympusBg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: olympusBorder),
      ),
      child: Row(
        mainAxisSize: _isNarrow(context) ? MainAxisSize.max : MainAxisSize.min,
        children: [
          Expanded(
            flex: _isNarrow(context) ? 1 : 0,
            child: _trendToggleItem(
              label: 'Semanal',
              selected: _trendMode == TrendMode.weekly,
              onTap: () {
                setState(() {
                  _trendMode = TrendMode.weekly;
                });
              },
            ),
          ),
          Expanded(
            flex: _isNarrow(context) ? 1 : 0,
            child: _trendToggleItem(
              label: 'Mensal',
              selected: _trendMode == TrendMode.monthly,
              onTap: () {
                setState(() {
                  _trendMode = TrendMode.monthly;
                });
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _trendToggleItem({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? olympusPurple : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: selected ? Colors.white : olympusMuted,
            fontSize: 12,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }

  Widget _sectionHeader({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    String? trailing,
  }) {
    final trailingWidget = trailing == null
        ? null
        : Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
            decoration: BoxDecoration(
              color: color.withOpacity(0.10),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              trailing,
              style: TextStyle(
                color: color,
                fontSize: 11.5,
                fontWeight: FontWeight.w900,
              ),
            ),
          );

    final iconBox = Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, color: color, size: 21),
    );

    if (_isNarrow(context)) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              iconBox,
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: olympusBlue,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: const TextStyle(
              color: olympusMuted,
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (trailingWidget != null) ...[
            const SizedBox(height: 8),
            trailingWidget,
          ],
        ],
      );
    }

    return Row(
      children: [
        iconBox,
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: olympusBlue,
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(
                  color: olympusMuted,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        if (trailingWidget != null) trailingWidget,
      ],
    );
  }

  Widget _chartBar({
    required String label,
    required int minutes,
    required double percent,
    required Color color,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_isNarrow(context))
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: olympusText,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                '${minutes}min • ${_formatDuration(minutes)}',
                style: TextStyle(
                  color: color,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          )
        else
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: olympusText,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${minutes}min • ${_formatDuration(minutes)}',
                style: TextStyle(
                  color: color,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: Container(
            height: 12,
            width: double.infinity,
            color: color.withOpacity(0.10),
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: percent.clamp(0.0, 1.0),
              child: Container(
                decoration: BoxDecoration(
                  color: color.withOpacity(0.78),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _miniTableBar({
    required int minutes,
    required double percent,
    required Color color,
  }) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _formatDuration(minutes),
          style: TextStyle(
            color: color,
            fontSize: 11,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 5),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: Container(
            height: 9,
            width: 112,
            color: color.withOpacity(0.10),
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: percent.clamp(0.0, 1.0),
              child: Container(color: color.withOpacity(0.76)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _percentBar(String label, double percent, Color color) {
    return Row(
      children: [
        SizedBox(
          width: 42,
          child: Text(
            label,
            style: const TextStyle(
              color: olympusMuted,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: Container(
              height: 10,
              color: color.withOpacity(0.10),
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: (percent / 100).clamp(0.0, 1.0),
                child: Container(color: color.withOpacity(0.75)),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 48,
          child: Text(
            '${percent.toStringAsFixed(1)}%',
            textAlign: TextAlign.right,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ],
    );
  }

  Widget _statusPill(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.22)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 10.5,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  BoxDecoration _cardDecoration() {
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: olympusBorder),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.04),
          blurRadius: 10,
          offset: const Offset(0, 5),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final filteredEvents = _filteredEvents();

    return Scaffold(
      backgroundColor: olympusBg,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const AdminTrainingPlansListPage(),
            ),
          );
          await _loadDashboard();
        },
        backgroundColor: olympusGold,
        foregroundColor: olympusBlue,
        icon: const Icon(Icons.list_alt_rounded),
        label: const Text(
          'Treinos',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      appBar: AppBar(
        title: const Text('Dashboard de treinos'),
        backgroundColor: olympusBlue,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Filtros',
            onPressed: _openFiltersBottomSheet,
            icon: Stack(
              clipBehavior: Clip.none,
              children: [
                const Icon(Icons.tune_rounded),
                if (_activeFiltersCount() > 0)
                  Positioned(
                    right: -2,
                    top: -2,
                    child: Container(
                      width: 9,
                      height: 9,
                      decoration: const BoxDecoration(
                        color: olympusGold,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Atualizar',
            onPressed: _loadDashboard,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          _buildFiltersBar(),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            _error!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: olympusDanger,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _loadDashboard,
                        child: ListView(
                          padding: EdgeInsets.zero,
                          children: [
                            _buildDashboard(filteredEvents),
                          ],
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}

class _TrendChart extends StatelessWidget {
  const _TrendChart({
    required this.data,
    required this.maxValue,
    required this.barColor,
    required this.labelFormatter,
    required this.valueFormatter,
  });

  final Map<String, int> data;
  final int maxValue;
  final Color barColor;
  final String Function(String value) labelFormatter;
  final String Function(int value) valueFormatter;

  @override
  Widget build(BuildContext context) {
    final entries = data.entries.toList();
    final isMobile = MediaQuery.of(context).size.width < 600;
    final chartWidth = entries.length * (isMobile ? 58.0 : 72.0);

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SizedBox(
        width: chartWidth < MediaQuery.of(context).size.width - 56
            ? MediaQuery.of(context).size.width - 56
            : chartWidth,
        child: LayoutBuilder(
          builder: (context, constraints) {
            return CustomPaint(
              painter: _TrendChartPainter(
                entries: entries,
                maxValue: maxValue,
                barColor: barColor,
                labelFormatter: labelFormatter,
                valueFormatter: valueFormatter,
                isMobile: isMobile,
              ),
              size: Size(constraints.maxWidth, double.infinity),
            );
          },
        ),
      ),
    );
  }
}

class _TrendChartPainter extends CustomPainter {
  _TrendChartPainter({
    required this.entries,
    required this.maxValue,
    required this.barColor,
    required this.labelFormatter,
    required this.valueFormatter,
    required this.isMobile,
  });

  final List<MapEntry<String, int>> entries;
  final int maxValue;
  final Color barColor;
  final String Function(String value) labelFormatter;
  final String Function(int value) valueFormatter;
  final bool isMobile;

  @override
  void paint(Canvas canvas, Size size) {
    const axisColor = Color(0xFFE4EDF5);
    const textColor = Color(0xFF53657B);
    const titleColor = Color(0xFF17324D);

    final paint = Paint()
      ..color = barColor.withOpacity(0.78)
      ..style = PaintingStyle.fill;

    final gridPaint = Paint()
      ..color = axisColor
      ..strokeWidth = 1;

    final axisPaint = Paint()
      ..color = axisColor
      ..strokeWidth = 1.2;

    final leftPadding = isMobile ? 32.0 : 42.0;
    final bottomPadding = isMobile ? 58.0 : 62.0;
    final topPadding = 28.0;
    final rightPadding = 12.0;

    final chartHeight = size.height - topPadding - bottomPadding;
    final chartWidth = size.width - leftPadding - rightPadding;

    final origin = Offset(leftPadding, size.height - bottomPadding);
    final top = Offset(leftPadding, topPadding);

    for (int i = 0; i <= 4; i++) {
      final y = topPadding + chartHeight * (i / 4);
      canvas.drawLine(
        Offset(leftPadding, y),
        Offset(size.width - rightPadding, y),
        gridPaint,
      );
    }

    canvas.drawLine(
      origin,
      Offset(size.width - rightPadding, origin.dy),
      axisPaint,
    );
    canvas.drawLine(origin, top, axisPaint);

    if (entries.isEmpty || maxValue <= 0) return;

    final slotWidth = chartWidth / entries.length;
    final barWidth = (slotWidth * 0.46).clamp(18.0, 34.0);

    for (int i = 0; i < entries.length; i++) {
      final entry = entries[i];
      final percent = entry.value / maxValue;
      final barHeight = chartHeight * percent;

      final centerX = leftPadding + slotWidth * i + slotWidth / 2;
      final left = centerX - barWidth / 2;
      final topY = origin.dy - barHeight;

      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(left, topY, barWidth, barHeight),
        const Radius.circular(8),
      );

      canvas.drawRRect(rect, paint);

      _drawCenteredText(
        canvas,
        valueFormatter(entry.value),
        Offset(centerX, topY - 13),
        isMobile ? 9.5 : 10.5,
        titleColor,
        FontWeight.w800,
      );

      final label = labelFormatter(entry.key);
      _drawRotatedLabel(
        canvas,
        label,
        Offset(centerX, origin.dy + 14),
        isMobile ? 9.0 : 10.0,
        textColor,
      );
    }
  }

  void _drawCenteredText(
    Canvas canvas,
    String text,
    Offset center,
    double fontSize,
    Color color,
    FontWeight weight,
  ) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: fontSize,
          fontWeight: weight,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();

    painter.paint(
      canvas,
      Offset(center.dx - painter.width / 2, center.dy - painter.height / 2),
    );
  }

  void _drawRotatedLabel(
    Canvas canvas,
    String text,
    Offset origin,
    double fontSize,
    Color color,
  ) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: fontSize,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '...',
    )..layout(maxWidth: 70);

    canvas.save();
    canvas.translate(origin.dx, origin.dy);
    canvas.rotate(-0.55);
    painter.paint(canvas, Offset(-painter.width / 2, 0));
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _TrendChartPainter oldDelegate) {
    return oldDelegate.entries != entries ||
        oldDelegate.maxValue != maxValue ||
        oldDelegate.barColor != barColor ||
        oldDelegate.isMobile != isMobile;
  }
}
