import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../theme/olympus_theme.dart';
import '../utils/checkin_ranking.dart';

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
  RealtimeChannel? _checkinsRealtimeChannel;
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
    _loadRanking(force: true);
    _listenForCheckinChanges();
  }

  void _listenForCheckinChanges() {
    if (_checkinsRealtimeChannel != null) return;
    _checkinsRealtimeChannel = _supabase
        .channel(
          'admin_checkin_ranking_${_supabase.auth.currentUser?.id ?? 'guest'}',
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'checkins',
          callback: (_) {
            _cache.clear();
            if (mounted) _loadRanking(force: true);
          },
        )
        .subscribe();
  }

  @override
  void dispose() {
    final channel = _checkinsRealtimeChannel;
    if (channel != null) _supabase.removeChannel(channel);
    super.dispose();
  }

  OlympusBranding get _branding => OlympusBrandingController.instance.branding;

  String _dateKey(DateTime value) => '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  int _asInt(dynamic value) => value is num
      ? value.toInt()
      : int.tryParse((value ?? '').toString()) ?? 0;

  DateTime? _parseTimestamp(dynamic value) {
    final parsed = DateTime.tryParse((value ?? '').toString());
    return parsed?.toLocal();
  }

  List<DateTime> _parseTrainingDays(dynamic value) {
    if (value is! List) return const [];
    final days = value
        .map((item) => DateTime.tryParse(item.toString()))
        .whereType<DateTime>()
        .map((date) => DateTime(date.year, date.month, date.day))
        .toList();
    days.sort();
    return days;
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
      final rankingRowsRaw = await _supabase.rpc(
        'get_admin_checkin_ranking_v1',
        params: {
          'p_start_date': _dateKey(_startDate),
          'p_end_date': _dateKey(_endDate),
        },
      );
      final rankingRows = List<Map<String, dynamic>>.from(
        rankingRowsRaw as List,
      );
      final entries = <_RankingEntry>[];
      for (final row in rankingRows) {
        final userId = (row['id'] ?? '').toString();
        final earliest = _parseTimestamp(row['earliest_checkin_at']);
        if (userId.isEmpty || earliest == null) continue;
        entries.add(
          _RankingEntry(
            userId: userId,
            name: (row['name'] ?? 'Atleta sem nome').toString(),
            avatarUrl: (row['avatar_url'] ?? '').toString().trim(),
            gender: _normalizeGender(row['gender']),
            courtPosition: (row['court_position'] ?? '').toString().trim(),
            score: CheckinRankingScore(
              totalPoints: _asInt(row['total_points']),
              presenceCount: _asInt(row['presence_count']),
              firstCheckins: _asInt(row['first_checkins']),
              earliestCheckInAt: earliest,
            ),
            days: _parseTrainingDays(row['training_days']),
          ),
        );
      }
      entries.sort((a, b) {
        return compareCheckinRanking(
          a: a.score,
          aId: a.userId,
          b: b.score,
          bId: b.userId,
        );
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
    return List.generate(
      filtered.length,
      (index) => _PositionedRankingEntry(index + 1, filtered[index]),
    );
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
                'Pontos',
                'Check-ins',
                'Primeiras chegadas',
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
                      '${item.entry.score.totalPoints}',
                      '${item.entry.checkinCount}',
                      '${item.entry.score.firstCheckins}',
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
                const SizedBox(height: 5),
                Text(
                  '${entry.checkinCount} treino(s) válido(s) • '
                  '${entry.score.firstCheckins} primeira(s) chegada(s)',
                  style: TextStyle(
                    color: branding.textColor.withValues(alpha: .64),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
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
                  '${entry.score.totalPoints}',
                  style: TextStyle(
                    color: branding.primaryColor,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  'pontos',
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
    required this.score,
    required this.days,
  });

  final String userId;
  final String name;
  final String avatarUrl;
  final String gender;
  final String courtPosition;
  final CheckinRankingScore score;
  int get checkinCount => score.presenceCount;
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
