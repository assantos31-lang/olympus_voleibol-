import 'package:flutter/material.dart';
import '../theme/olympus_theme.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AdminTrainingPlansListPage extends StatefulWidget {
  const AdminTrainingPlansListPage({super.key});

  @override
  State<AdminTrainingPlansListPage> createState() =>
      _AdminTrainingPlansListPageState();
}

class _AdminTrainingPlansListPageState
    extends State<AdminTrainingPlansListPage> {
  final SupabaseClient _supabase = Supabase.instance.client;

  static const Color olympusBg = Color(0xFFF4F7FB);
  static const Color olympusText = Color(0xFF17324D);
  static const Color olympusMuted = Color(0xFF53657B);
  static const Color olympusSubtle = Color(0xFF6A7E94);
  static const Color olympusBorder = Color(0xFFE4EDF5);
  static const Color olympusDanger = Color(0xFFDC2626);
  static const Color olympusSuccess = Color(0xFF16A34A);
  static const Color olympusWarning = Color(0xFFF59E0B);
  static const Color olympusPurple = Color(0xFF7C3AED);

  bool _loading = true;
  String? _error;

  List<Map<String, dynamic>> _events = [];
  Map<String, List<Map<String, dynamic>>> _plansByEvent = {};

  String _selectedMonth = '';
  String _selectedCoachId = '';

  @override
  void initState() {
    super.initState();
    _setCurrentMonth();
    _loadTrainingPlans();
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

  String _formatEventDateTime(Map<String, dynamic> event) {
    final date = _asString(event['event_date']);
    final time = _normalizeTime(event['event_time']);

    if (date.isEmpty && time.isEmpty) return 'Sem data definida';
    if (date.isEmpty) return time;
    if (time.isEmpty) return date;

    return '$date • $time';
  }

  String _formatLocal(Map<String, dynamic> event) {
    final city = _asString(event['city']);
    final state = _asString(event['state']);

    if (city.isEmpty && state.isEmpty) return '';
    if (city.isEmpty) return state;
    if (state.isEmpty) return city;

    return '$city/$state';
  }

  String _formatMonthLabel(String monthYear) {
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

  Future<void> _loadTrainingPlans() async {
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
        _error = 'Erro ao carregar treinos programados: $e';
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
    return _formatMonthLabel(_selectedMonth);
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
    return count;
  }

  String? _safeSelectedCoachValue(List<Map<String, dynamic>> coaches) {
    if (_selectedCoachId.isEmpty) return '';
    final exists = coaches.any(
      (coach) => _asString(coach['coach_id']) == _selectedCoachId,
    );
    return exists ? _selectedCoachId : null;
  }

  void _clearFilters() {
    setState(() {
      _selectedMonth = '';
      _selectedCoachId = '';
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
                              child: Icon(
                                Icons.tune_rounded,
                                color: olympusBlue,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Filtros dos treinos',
                                    style: TextStyle(
                                      color: olympusBlue,
                                      fontSize: 18,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  SizedBox(height: 2),
                                  Text(
                                    'Refine a lista por mês e técnico.',
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
                                child: Text(_formatMonthLabel(month)),
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
                        const SizedBox(height: 18),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () {
                                  setModalState(() {
                                    tempMonth = '';
                                    tempCoach = '';
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
          style: TextStyle(
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
      decoration: BoxDecoration(
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
                  'Treinos programados',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Lista detalhada por mês e técnico.',
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
                          ? 'Filtrar treinos'
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
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Lista detalhada por mês e técnico.',
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
    final chips = <Widget>[
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
    ];

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
    return _buildFiltersBar();
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

  Widget _buildEventCard(Map<String, dynamic> event) {
    final isMobile = _isMobile(context);
    final eventId = _asString(event['id']);
    final plans = _plansForEvent(eventId);
    final local = _formatLocal(event);
    final gender = _asString(event['gender']);

    int totalMinutes = 0;
    for (final plan in plans) {
      totalMinutes += (plan['total_minutes'] ?? 0) as int;
    }

    return Container(
      margin:
          EdgeInsets.fromLTRB(isMobile ? 12 : 16, 0, isMobile ? 12 : 16, 12),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: EdgeInsets.all(isMobile ? 14 : 16),
          decoration: _cardDecoration(),
          child: ExpansionTile(
            tilePadding: EdgeInsets.zero,
            childrenPadding: EdgeInsets.zero,
            initiallyExpanded: plans.length == 1,
            title: Text(
              _asString(event['event_name']).isEmpty
                  ? 'Treino'
                  : _asString(event['event_name']),
              style: TextStyle(
                color: olympusText,
                fontSize: isMobile ? 16 : 17,
                fontWeight: FontWeight.w900,
              ),
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _formatEventDateTime(event),
                    style: TextStyle(
                      color: olympusMuted,
                      fontSize: isMobile ? 12 : 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (gender.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      'Categoria/Gênero: $gender',
                      style: TextStyle(
                        color: olympusSubtle,
                        fontSize: isMobile ? 12 : 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                  if (local.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      local,
                      style: TextStyle(
                        color: olympusSubtle,
                        fontSize: isMobile ? 12 : 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 7,
                    runSpacing: 7,
                    children: [
                      _infoPill(
                        '${plans.length} programação${plans.length == 1 ? '' : 'ões'}',
                        olympusPurple,
                      ),
                      _infoPill(
                        _formatDuration(totalMinutes),
                        olympusSuccess,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            children: [
              const SizedBox(height: 12),
              if (plans.isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: olympusWarning.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: olympusWarning.withOpacity(0.25)),
                  ),
                  child: const Text(
                    'Nenhuma programação encontrada para este treino.',
                    style: TextStyle(
                      color: olympusWarning,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                )
              else
                ...plans.map(_buildCoachPlanCard),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCoachPlanCard(Map<String, dynamic> plan) {
    final blocks = List<Map<String, dynamic>>.from(plan['blocks'] as List);
    final notes = _asString(plan['notes']);
    final updatedAt = _asString(plan['updated_at']);
    final coachName = _asString(plan['coach_name']).isEmpty
        ? 'Técnico'
        : _asString(plan['coach_name']);
    final avatarUrl = _asString(plan['coach_avatar_url']);
    final totalMinutes = (plan['total_minutes'] ?? 0) as int;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: olympusBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: olympusBorder),
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
                    _coachAvatar(avatarUrl, coachName),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        coachName,
                        style: TextStyle(
                          color: olympusBlue,
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
                if (updatedAt.isNotEmpty) ...[
                  const SizedBox(height: 5),
                  Text(
                    'Atualizado em $updatedAt',
                    style: const TextStyle(
                      color: olympusSubtle,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                Wrap(
                  spacing: 7,
                  runSpacing: 7,
                  children: [
                    _infoPill(
                      '${blocks.length} bloco${blocks.length == 1 ? '' : 's'}',
                      olympusBlue,
                    ),
                    _infoPill(_formatDuration(totalMinutes), olympusSuccess),
                  ],
                ),
              ],
            )
          else
            Row(
              children: [
                _coachAvatar(avatarUrl, coachName),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        coachName,
                        style: TextStyle(
                          color: olympusBlue,
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      if (updatedAt.isNotEmpty)
                        Text(
                          'Atualizado em $updatedAt',
                          style: const TextStyle(
                            color: olympusSubtle,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    _infoPill(
                      '${blocks.length} bloco${blocks.length == 1 ? '' : 's'}',
                      olympusBlue,
                    ),
                    const SizedBox(height: 5),
                    Text(
                      _formatDuration(totalMinutes),
                      style: const TextStyle(
                        color: olympusSuccess,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          const SizedBox(height: 12),
          if (blocks.isEmpty)
            const Text(
              'Sem blocos cadastrados.',
              style: TextStyle(
                color: olympusMuted,
                fontWeight: FontWeight.w700,
              ),
            )
          else
            ...List.generate(
              blocks.length,
              (index) => _buildBlockCard(index, blocks[index]),
            ),
          if (notes.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: olympusBorder),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Observações',
                    style: TextStyle(
                      color: olympusBlue,
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    notes,
                    style: const TextStyle(
                      color: olympusMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _coachAvatar(String avatarUrl, String coachName) {
    return CircleAvatar(
      radius: 19,
      backgroundColor: olympusBlue.withOpacity(0.12),
      backgroundImage:
          avatarUrl.trim().isNotEmpty ? NetworkImage(avatarUrl) : null,
      child: avatarUrl.trim().isEmpty
          ? Text(
              coachName.isNotEmpty ? coachName[0].toUpperCase() : 'T',
              style: TextStyle(
                color: olympusBlue,
                fontWeight: FontWeight.w900,
              ),
            )
          : null,
    );
  }

  Widget _buildBlockCard(int index, Map<String, dynamic> block) {
    final category = _asString(block['category']);
    final type = _asString(block['type']);
    final start = _normalizeTime(block['start_time']);
    final end = _normalizeTime(block['end_time']);
    final observation = _asString(block['observation']);
    final minutes = _blockMinutes(block);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: olympusBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: olympusGold.withOpacity(0.22),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Center(
              child: Text(
                '${index + 1}',
                style: TextStyle(
                  color: olympusBlue,
                  fontWeight: FontWeight.w900,
                  fontSize: 12,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  type.isEmpty ? 'Bloco ${index + 1}' : type,
                  style: const TextStyle(
                    color: olympusText,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  [
                    if (category.isNotEmpty) category,
                    '${start.isEmpty ? '--:--' : start} às ${end.isEmpty ? '--:--' : end}',
                    _formatDuration(minutes),
                  ].join(' • '),
                  style: const TextStyle(
                    color: olympusMuted,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (observation.isNotEmpty) ...[
                  const SizedBox(height: 5),
                  Text(
                    observation,
                    style: const TextStyle(
                      color: olympusSubtle,
                      fontSize: 11.5,
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
  }

  Widget _infoPill(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w800,
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
      appBar: AppBar(
        title: const Text('Treinos programados'),
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
                      decoration: BoxDecoration(
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
            onPressed: _loadTrainingPlans,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          _buildFiltersBar(),
          _buildSummary(filteredEvents),
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
                    : filteredEvents.isEmpty
                        ? const Center(
                            child: Padding(
                              padding: EdgeInsets.all(24),
                              child: Text(
                                'Nenhum treino programado encontrado para os filtros selecionados.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: olympusMuted,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          )
                        : RefreshIndicator(
                            onRefresh: _loadTrainingPlans,
                            child: ListView.builder(
                              padding: const EdgeInsets.only(bottom: 24),
                              itemCount: filteredEvents.length,
                              itemBuilder: (context, index) {
                                return _buildEventCard(filteredEvents[index]);
                              },
                            ),
                          ),
          ),
        ],
      ),
    );
  }
}
