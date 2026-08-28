import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../theme/olympus_theme.dart';

class AdminCheckinRankingPage extends StatefulWidget {
  const AdminCheckinRankingPage({super.key});

  @override
  State<AdminCheckinRankingPage> createState() =>
      _AdminCheckinRankingPageState();
}

class _AdminCheckinRankingPageState extends State<AdminCheckinRankingPage> {
  final SupabaseClient _supabase = Supabase.instance.client;
  final DateFormat _dayFormat = DateFormat('dd/MM/yyyy', 'pt_BR');

  bool _loading = true;
  bool _exporting = false;
  String? _error;
  String _gender = 'todos';
  String _period = 'mes_atual';
  late DateTime _startDate;
  late DateTime _endDate;
  List<_RankingEntry> _allEntries = const [];

  static final Map<String, _RankingCache> _cache = {};
  static const Duration _cacheDuration = Duration(minutes: 3);

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _startDate = DateTime(now.year, now.month);
    _endDate = DateTime(now.year, now.month + 1, 0);
    _loadRanking();
  }

  OlympusBranding get _branding => OlympusBrandingController.instance.branding;

  String _dateKey(DateTime value) => '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  DateTime? _parseEventDate(Map<String, dynamic> event) {
    final startAt = (event['event_start_at'] ?? '').toString().trim();
    if (startAt.isNotEmpty) {
      final parsed = DateTime.tryParse(startAt);
      if (parsed != null) {
        final local = parsed.toLocal();
        return DateTime(local.year, local.month, local.day);
      }
    }

    final raw = (event['event_date'] ?? '').toString().trim();
    if (raw.isEmpty) return null;
    final brazilian = RegExp(r'^(\d{1,2})/(\d{1,2})/(\d{4})$').firstMatch(raw);
    if (brazilian != null) {
      final day = int.tryParse(brazilian.group(1)!);
      final month = int.tryParse(brazilian.group(2)!);
      final year = int.tryParse(brazilian.group(3)!);
      if (day != null && month != null && year != null) {
        return DateTime(year, month, day);
      }
    }
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return null;
    return DateTime(parsed.year, parsed.month, parsed.day);
  }

  bool _isWithinSelectedPeriod(DateTime date) {
    final normalized = DateTime(date.year, date.month, date.day);
    return !normalized.isBefore(_startDate) && !normalized.isAfter(_endDate);
  }

  bool _isDone(dynamic value) {
    final raw = (value ?? '').toString().trim().toLowerCase();
    if (raw.isEmpty || raw == 'pending' || raw == 'pendente') return false;
    return const {
      'realizado',
      'realizado com sucesso',
      'checked_in',
      'checkin_realizado',
      'check-in realizado',
      'presente',
      'presence',
      'ok',
      'success',
      'completed',
      'done',
      'manual',
      'late',
      'atrasado',
      'checkin_atrasado',
    }.contains(raw);
  }

  String _normalizeGender(dynamic value) {
    final raw = (value ?? '').toString().trim().toLowerCase();
    if (raw == 'f' || raw == 'female' || raw.contains('feminino')) {
      return 'feminino';
    }
    if (raw == 'm' || raw == 'male' || raw.contains('masculino')) {
      return 'masculino';
    }
    return raw.isEmpty ? 'não informado' : raw;
  }

  String _genderLabel(String value) {
    switch (value) {
      case 'feminino':
        return 'Feminino';
      case 'masculino':
        return 'Masculino';
      default:
        return value == 'todos' ? 'Todos' : 'Não informado';
    }
  }

  Future<void> _loadRanking({bool force = false}) async {
    final cacheKey = '${_dateKey(_startDate)}:${_dateKey(_endDate)}';
    final cached = _cache[cacheKey];
    if (!force && cached != null && !cached.isExpired) {
      setState(() {
        _allEntries = cached.entries;
        _loading = false;
        _error = null;
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final eventRowsRaw = await _supabase
          .from('events')
          .select('id, event_name, event_date, event_start_at');
      final eventRows = List<Map<String, dynamic>>.from(eventRowsRaw as List);
      final eventDates = <String, DateTime>{};
      for (final event in eventRows) {
        final id = (event['id'] ?? '').toString();
        final date = _parseEventDate(event);
        if (id.isNotEmpty && date != null && _isWithinSelectedPeriod(date)) {
          eventDates[id] = date;
        }
      }

      if (eventDates.isEmpty) {
        _setLoaded(const [], cacheKey);
        return;
      }

      final checkinRowsRaw = await _supabase
          .from('checkins')
          .select('user_id, event_id, check_in_status')
          .inFilter('event_id', eventDates.keys.toList());
      final checkinRows = List<Map<String, dynamic>>.from(
        checkinRowsRaw as List,
      ).where((row) => _isDone(row['check_in_status'])).toList();

      final userIds = checkinRows
          .map((row) => (row['user_id'] ?? '').toString())
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList();
      if (userIds.isEmpty) {
        _setLoaded(const [], cacheKey);
        return;
      }

      final results = await Future.wait<dynamic>([
        _supabase
            .from('profiles')
            .select(
              'id, full_name, avatar_url, gender, court_position, user_type, is_active',
            )
            .inFilter('id', userIds),
        _supabase
            .from('user_roles')
            .select('user_id, role, is_active')
            .inFilter('user_id', userIds)
            .eq('is_active', true),
      ]);

      final profiles = List<Map<String, dynamic>>.from(results[0] as List);
      final roles = List<Map<String, dynamic>>.from(results[1] as List);
      final athleteRoleIds = roles
          .where((row) {
            final role = (row['role'] ?? '').toString().toLowerCase();
            return role == 'athlete' || role == 'atleta';
          })
          .map((row) => (row['user_id'] ?? '').toString())
          .toSet();
      final profilesById = <String, Map<String, dynamic>>{
        for (final profile in profiles)
          (profile['id'] ?? '').toString(): profile,
      };

      final eventsByUser = <String, Set<String>>{};
      for (final row in checkinRows) {
        final userId = (row['user_id'] ?? '').toString();
        final eventId = (row['event_id'] ?? '').toString();
        final profile = profilesById[userId];
        if (profile == null || profile['is_active'] == false) continue;
        final type = (profile['user_type'] ?? '').toString().toLowerCase();
        if (type != 'athlete' &&
            type != 'atleta' &&
            !athleteRoleIds.contains(userId)) {
          continue;
        }
        if (eventDates.containsKey(eventId)) {
          eventsByUser.putIfAbsent(userId, () => <String>{}).add(eventId);
        }
      }

      final entries = <_RankingEntry>[];
      for (final userEvents in eventsByUser.entries) {
        final profile = profilesById[userEvents.key]!;
        final datesByDay = <String, DateTime>{
          for (final eventId in userEvents.value)
            _dateKey(eventDates[eventId]!): eventDates[eventId]!,
        };
        final dates = datesByDay.values.toList()..sort();
        entries.add(
          _RankingEntry(
            userId: userEvents.key,
            name: (profile['full_name'] ?? 'Atleta sem nome').toString(),
            avatarUrl: (profile['avatar_url'] ?? '').toString().trim(),
            gender: _normalizeGender(profile['gender']),
            courtPosition: (profile['court_position'] ?? '').toString().trim(),
            checkinCount: userEvents.value.length,
            days: dates,
          ),
        );
      }
      entries.sort((a, b) {
        final count = b.checkinCount.compareTo(a.checkinCount);
        return count != 0 ? count : a.name.compareTo(b.name);
      });
      _setLoaded(entries, cacheKey);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Não foi possível carregar o ranking.\n$error';
      });
    }
  }

  void _setLoaded(List<_RankingEntry> entries, String cacheKey) {
    _cache[cacheKey] = _RankingCache(entries);
    if (!mounted) return;
    setState(() {
      _allEntries = entries;
      _loading = false;
      _error = null;
    });
  }

  List<_PositionedRankingEntry> get _visibleEntries {
    final filtered = _allEntries
        .where((entry) => _gender == 'todos' || entry.gender == _gender)
        .toList();
    var lastCount = -1;
    var position = 0;
    return filtered.indexed.map((indexed) {
      final entry = indexed.$2;
      if (entry.checkinCount != lastCount) {
        position = indexed.$1 + 1;
        lastCount = entry.checkinCount;
      }
      return _PositionedRankingEntry(position, entry);
    }).toList();
  }

  void _applyQuickPeriod(String value) {
    final now = DateTime.now();
    DateTime start;
    DateTime end;
    switch (value) {
      case 'mes_anterior':
        start = DateTime(now.year, now.month - 1);
        end = DateTime(now.year, now.month, 0);
        break;
      case 'ultimos_3':
        start = DateTime(now.year, now.month - 2);
        end = DateTime(now.year, now.month + 1, 0);
        break;
      case 'ultimos_6':
        start = DateTime(now.year, now.month - 5);
        end = DateTime(now.year, now.month + 1, 0);
        break;
      default:
        start = DateTime(now.year, now.month);
        end = DateTime(now.year, now.month + 1, 0);
    }
    setState(() {
      _period = value;
      _startDate = start;
      _endDate = end;
    });
    _loadRanking();
  }

  Future<void> _selectCustomPeriod() async {
    final start = await showDatePicker(
      context: context,
      locale: const Locale('pt', 'BR'),
      initialDate: _startDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 366)),
      helpText: 'Data inicial',
    );
    if (start == null || !mounted) return;
    final end = await showDatePicker(
      context: context,
      locale: const Locale('pt', 'BR'),
      initialDate: _endDate.isBefore(start) ? start : _endDate,
      firstDate: start,
      lastDate: DateTime.now().add(const Duration(days: 366)),
      helpText: 'Data final',
    );
    if (end == null || !mounted) return;
    setState(() {
      _period = 'personalizado';
      _startDate = DateTime(start.year, start.month, start.day);
      _endDate = DateTime(end.year, end.month, end.day);
    });
    _loadRanking();
  }

  Future<void> _selectMonth() async {
    final now = DateTime.now();
    final months = List<DateTime>.generate(
      36,
      (index) => DateTime(now.year, now.month - index),
    );
    final selected = await showModalBottomSheet<DateTime>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(sheetContext).height * .62,
          child: Column(
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(18, 4, 18, 12),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Escolha o mês do ranking',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                  ),
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView.builder(
                  itemCount: months.length,
                  itemBuilder: (_, index) {
                    final month = months[index];
                    final selectedMonth = month.year == _startDate.year &&
                        month.month == _startDate.month &&
                        _period == 'mes_escolhido';
                    final label = DateFormat(
                      'MMMM / yyyy',
                      'pt_BR',
                    ).format(month);
                    return ListTile(
                      leading: Icon(
                        selectedMonth
                            ? Icons.check_circle_rounded
                            : Icons.calendar_month_rounded,
                      ),
                      title: Text(
                        '${label.substring(0, 1).toUpperCase()}${label.substring(1)}',
                      ),
                      onTap: () => Navigator.pop(sheetContext, month),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (selected == null || !mounted) return;
    setState(() {
      _period = 'mes_escolhido';
      _startDate = DateTime(selected.year, selected.month);
      _endDate = DateTime(selected.year, selected.month + 1, 0);
    });
    _loadRanking();
  }

  Future<void> _exportPdf() async {
    final rows = _visibleEntries;
    if (rows.isEmpty || _exporting) return;
    setState(() => _exporting = true);
    try {
      final document = pw.Document();
      document.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4.landscape,
          margin: const pw.EdgeInsets.all(28),
          build: (_) => [
            pw.Text(
              'Ranking de check-ins',
              style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 5),
            pw.Text(
              '${_dayFormat.format(_startDate)} a ${_dayFormat.format(_endDate)} • ${_genderLabel(_gender)}',
            ),
            pw.SizedBox(height: 16),
            pw.Table.fromTextArray(
              headers: const [
                'Posição',
                'Atleta',
                'Gênero',
                'Posição em quadra',
                'Check-ins',
                'Dias',
              ],
              data: rows
                  .map(
                    (item) => [
                      '${item.position}º',
                      item.entry.name,
                      _genderLabel(item.entry.gender),
                      item.entry.courtPosition.isEmpty
                          ? '-'
                          : item.entry.courtPosition,
                      '${item.entry.checkinCount}',
                      item.entry.days.map(_dayFormat.format).join(', '),
                    ],
                  )
                  .toList(),
              headerDecoration: pw.BoxDecoration(color: PdfColors.blueGrey900),
              headerStyle: pw.TextStyle(
                color: PdfColors.white,
                fontWeight: pw.FontWeight.bold,
              ),
              cellStyle: const pw.TextStyle(fontSize: 8),
              cellPadding: const pw.EdgeInsets.all(5),
            ),
          ],
        ),
      );
      final Uint8List bytes = await document.save();
      await Printing.sharePdf(
        bytes: bytes,
        filename:
            'ranking_checkins_${_dateKey(_startDate)}_${_dateKey(_endDate)}.pdf',
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final branding = _branding;
    final entries = _visibleEntries;
    return Scaffold(
      backgroundColor: branding.backgroundColor,
      appBar: AppBar(
        title: const Text('Ranking de check-ins'),
        actions: [
          IconButton(
            tooltip: 'Atualizar',
            onPressed: _loading ? null : () => _loadRanking(force: true),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => _loadRanking(force: true),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
          children: [
            _buildFilters(branding),
            const SizedBox(height: 14),
            _buildSummary(entries, branding),
            const SizedBox(height: 14),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(50),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              _buildError()
            else if (entries.isEmpty)
              _buildEmpty()
            else
              ...entries.map((entry) => _buildAthleteCard(entry, branding)),
          ],
        ),
      ),
    );
  }

  Widget _buildFilters(OlympusBranding branding) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: branding.surfaceColor,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: branding.primaryColor.withValues(alpha: .12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Período do ranking',
            style: TextStyle(
              color: branding.textColor,
              fontWeight: FontWeight.w900,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _periodChip('mes_atual', 'Mês atual'),
              _periodChip('mes_anterior', 'Mês anterior'),
              _periodChip('ultimos_3', '3 meses'),
              _periodChip('ultimos_6', '6 meses'),
              ActionChip(
                avatar: const Icon(Icons.calendar_month_rounded, size: 17),
                label: Text(
                  _period == 'mes_escolhido'
                      ? DateFormat('MM/yyyy').format(_startDate)
                      : 'Escolher mês',
                ),
                onPressed: _selectMonth,
              ),
              ActionChip(
                avatar: const Icon(Icons.date_range_rounded, size: 17),
                label: Text(
                  _period == 'personalizado'
                      ? '${_dayFormat.format(_startDate)} – ${_dayFormat.format(_endDate)}'
                      : 'Escolher datas',
                ),
                onPressed: _selectCustomPeriod,
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            'Separar por gênero',
            style: TextStyle(
              color: branding.textColor,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'todos', label: Text('Todos')),
              ButtonSegment(value: 'feminino', label: Text('Feminino')),
              ButtonSegment(value: 'masculino', label: Text('Masculino')),
            ],
            selected: {_gender},
            onSelectionChanged: (value) {
              setState(() => _gender = value.first);
            },
          ),
        ],
      ),
    );
  }

  Widget _periodChip(String value, String label) {
    return ChoiceChip(
      label: Text(label),
      selected: _period == value,
      onSelected: (_) => _applyQuickPeriod(value),
    );
  }

  Widget _buildSummary(
    List<_PositionedRankingEntry> entries,
    OlympusBranding branding,
  ) {
    final total = entries.fold<int>(
      0,
      (sum, item) => sum + item.entry.checkinCount,
    );
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: branding.primaryColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          const Icon(Icons.emoji_events_rounded, color: Color(0xFFD4AF37)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '${entries.length} atletas • $total check-ins',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: branding.secondaryColor,
              foregroundColor: branding.primaryColor,
            ),
            onPressed: entries.isEmpty || _exporting ? null : _exportPdf,
            icon: _exporting
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.picture_as_pdf_rounded),
            label: const Text('Exportar'),
          ),
        ],
      ),
    );
  }

  Widget _buildAthleteCard(
    _PositionedRankingEntry item,
    OlympusBranding branding,
  ) {
    final entry = item.entry;
    final medalColor = item.position == 1
        ? const Color(0xFFD4AF37)
        : item.position == 2
            ? const Color(0xFF9CA3AF)
            : item.position == 3
                ? const Color(0xFFB7793E)
                : branding.primaryColor;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: branding.surfaceColor,
        borderRadius: BorderRadius.circular(19),
        border: Border.all(color: medalColor.withValues(alpha: .28)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 38,
            child: Center(
              child: Text(
                '${item.position}º',
                style: TextStyle(
                  color: medalColor,
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          _avatar(entry, branding),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.name,
                  style: TextStyle(
                    color: branding.textColor,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${_genderLabel(entry.gender)} • ${entry.courtPosition.isEmpty ? 'Posição não informada' : entry.courtPosition}',
                  style: TextStyle(
                    color: branding.textColor.withValues(alpha: .64),
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  entry.days.map(_dayFormat.format).join(' • '),
                  style: TextStyle(
                    color: branding.textColor.withValues(alpha: .78),
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
            decoration: BoxDecoration(
              color: branding.secondaryColor.withValues(alpha: .18),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Column(
              children: [
                Text(
                  '${entry.checkinCount}',
                  style: TextStyle(
                    color: branding.primaryColor,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  'check-ins',
                  style: TextStyle(
                    color: branding.primaryColor,
                    fontSize: 9,
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

  Widget _avatar(_RankingEntry entry, OlympusBranding branding) {
    final fallback = CircleAvatar(
      radius: 27,
      backgroundColor: branding.primaryColor.withValues(alpha: .10),
      child: Text(
        entry.name.isEmpty ? '?' : entry.name.substring(0, 1).toUpperCase(),
        style: TextStyle(
          color: branding.primaryColor,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
    if (entry.avatarUrl.isEmpty) return fallback;
    return ClipOval(
      child: CachedNetworkImage(
        imageUrl: entry.avatarUrl,
        width: 54,
        height: 54,
        fit: BoxFit.cover,
        errorWidget: (_, __, ___) => fallback,
        placeholder: (_, __) => fallback,
      ),
    );
  }

  Widget _buildError() => Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: _branding.surfaceColor,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          children: [
            const Icon(Icons.cloud_off_rounded, size: 42),
            const SizedBox(height: 10),
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => _loadRanking(force: true),
              child: const Text('Tentar novamente'),
            ),
          ],
        ),
      );

  Widget _buildEmpty() => Container(
        padding: const EdgeInsets.all(34),
        decoration: BoxDecoration(
          color: _branding.surfaceColor,
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Column(
          children: [
            Icon(Icons.event_available_rounded, size: 44),
            SizedBox(height: 10),
            Text(
              'Nenhum check-in encontrado neste período.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
}

class _RankingEntry {
  const _RankingEntry({
    required this.userId,
    required this.name,
    required this.avatarUrl,
    required this.gender,
    required this.courtPosition,
    required this.checkinCount,
    required this.days,
  });

  final String userId;
  final String name;
  final String avatarUrl;
  final String gender;
  final String courtPosition;
  final int checkinCount;
  final List<DateTime> days;
}

class _PositionedRankingEntry {
  const _PositionedRankingEntry(this.position, this.entry);
  final int position;
  final _RankingEntry entry;
}

class _RankingCache {
  _RankingCache(this.entries) : createdAt = DateTime.now();
  final List<_RankingEntry> entries;
  final DateTime createdAt;
  bool get isExpired =>
      DateTime.now().difference(createdAt) >
      _AdminCheckinRankingPageState._cacheDuration;
}
