import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import '../../theme/olympus_theme.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/technical_staff_service.dart';
import 'coach_training_category_detail_page.dart';
import 'coach_training_sessions_page.dart';

class CoachTrainingPlanningDashboardPage extends StatefulWidget {
  const CoachTrainingPlanningDashboardPage({super.key});

  @override
  State<CoachTrainingPlanningDashboardPage> createState() =>
      _CoachTrainingPlanningDashboardPageState();
}

class _CoachTrainingPlanningDashboardPageState
    extends State<CoachTrainingPlanningDashboardPage> {
  final SupabaseClient _supabase = Supabase.instance.client;

  static const Color olympusBg = Color(0xFFF4F7FB);
  static const Color olympusMuted = Color(0xFF53657B);
  static const Color olympusBorder = Color(0xFFE4EDF5);
  static const Color olympusSuccess = Color(0xFF16A34A);
  static const Color olympusWarning = Color(0xFFF59E0B);
  static const Color olympusDanger = Color(0xFFDC2626);
  static const Color olympusPurple = Color(0xFF7C3AED);

  bool _loading = true;
  String? _error;

  RealtimeChannel? _planningRealtimeChannel;
  Timer? _planningReloadDebounce;

  List<_TrainingSummaryItem> _allRows = [];
  bool _isCoordinator = false;
  int _scopeCoachCount = 1;
  final Map<String, int> _additionalPhysicalMinutesByMonth = {};
  DateTime _selectedMonth = DateTime(DateTime.now().year, DateTime.now().month);

  @override
  void initState() {
    super.initState();
    _listenToPlanningChanges();
    _loadDashboard();
  }

  void _listenToPlanningChanges() {
    final user = _supabase.auth.currentUser;
    if (user == null || _planningRealtimeChannel != null) return;

    _planningRealtimeChannel = _supabase
        .channel('coach-planning-dashboard-${user.id}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'training_plan_blocks',
          callback: (payload) {
            _planningReloadDebounce?.cancel();
            _planningReloadDebounce = Timer(
              const Duration(milliseconds: 450),
              () {
                if (mounted) {
                  _loadDashboard(showLoading: false);
                }
              },
            );
          },
        )
        .subscribe();
  }

  Future<void> _loadDashboard({bool showLoading = true}) async {
    if (showLoading && mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final user = _supabase.auth.currentUser;
      if (user == null) {
        throw Exception('Usuário não autenticado.');
      }

      final staffService = TechnicalStaffService(client: _supabase);
      final assignment = await staffService.loadCurrentAssignment();
      _isCoordinator = assignment?.isCoordinator == true;
      final scopedCoachIds = <String>{user.id};
      if (_isCoordinator) {
        final assignments = await staffService.loadAssignments();
        scopedCoachIds.addAll(
          assignments
              .where((item) => item.supervisorUserId == user.id)
              .map((item) => item.userId),
        );
      }
      _scopeCoachCount = scopedCoachIds.length;

      final summaryResponse = await _supabase
          .from('monthly_training_plan_summary')
          .select(
            'coach_id, month, category, type, total_minutes, total_hours, total_blocks',
          )
          .inFilter('coach_id', scopedCoachIds.toList())
          .order('month', ascending: false)
          .order('category', ascending: true);
      dynamic physicalResponse = <dynamic>[];
      try {
        physicalResponse =
            await _supabase.rpc('get_training_physical_summary_v1');
      } catch (_) {
        // Mantém o dashboard utilizável durante a atualização do banco.
        physicalResponse = <dynamic>[];
      }

      final rows = List<Map<String, dynamic>>.from(summaryResponse as List);
      final physicalRows =
          List<Map<String, dynamic>>.from(physicalResponse as List);
      _additionalPhysicalMinutesByMonth.clear();
      for (final row in physicalRows) {
        final month = DateTime.tryParse((row['month'] ?? '').toString());
        if (month == null) continue;
        final key = '${month.year}-${month.month}';
        _additionalPhysicalMinutesByMonth[key] =
            int.tryParse((row['physical_minutes'] ?? '0').toString()) ?? 0;
      }

      final parsedRows = rows.map(_TrainingSummaryItem.fromMap).toList();

      if (parsedRows.isNotEmpty) {
        final months = parsedRows.map((e) => e.month).toList()
          ..sort((a, b) => b.compareTo(a));

        final currentMonth =
            DateTime(DateTime.now().year, DateTime.now().month);
        final hasCurrent = months.any((m) => _sameMonth(m, currentMonth));

        _selectedMonth = hasCurrent ? currentMonth : months.first;
      }

      if (!mounted) return;
      setState(() {
        _allRows = parsedRows;
        _error = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Erro ao carregar dashboard de planejamento: $e';
        _loading = false;
      });
    }
  }

  @override
  void dispose() {
    _planningReloadDebounce?.cancel();
    final channel = _planningRealtimeChannel;
    if (channel != null) {
      _supabase.removeChannel(channel);
    }
    super.dispose();
  }

  bool _sameMonth(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month;
  }

  List<_TrainingSummaryItem> get _selectedRows {
    return _allRows
        .where((row) => _sameMonth(row.month, _selectedMonth))
        .toList();
  }

  List<DateTime> get _availableMonths {
    final months = <String, DateTime>{};

    for (final row in _allRows) {
      final key =
          '${row.month.year}-${row.month.month.toString().padLeft(2, '0')}';
      months[key] = row.month;
    }

    final list = months.values.toList()..sort((a, b) => b.compareTo(a));
    if (list.isEmpty) {
      return [DateTime(DateTime.now().year, DateTime.now().month)];
    }

    return list;
  }

  int get _totalMinutes {
    return _minutesByCategory.values.fold<int>(0, (sum, value) => sum + value);
  }

  int get _totalBlocks {
    return _selectedRows.fold<int>(0, (sum, item) => sum + item.totalBlocks);
  }

  Map<String, int> get _minutesByCategory {
    final map = <String, int>{
      'Fundamentos': 0,
      'Tático': 0,
      'Físico': 0,
    };

    for (final row in _selectedRows) {
      map[row.category] = (map[row.category] ?? 0) + row.totalMinutes;
    }
    final monthKey = '${_selectedMonth.year}-${_selectedMonth.month}';
    map['Físico'] = (map['Físico'] ?? 0) +
        (_additionalPhysicalMinutesByMonth[monthKey] ?? 0);

    return map;
  }

  Map<String, List<_TrainingSummaryItem>> get _rowsByCategory {
    final map = <String, List<_TrainingSummaryItem>>{
      'Fundamentos': [],
      'Tático': [],
      'Físico': [],
    };

    for (final row in _selectedRows) {
      map.putIfAbsent(row.category, () => []);
      map[row.category]!.add(row);
    }

    for (final entry in map.entries) {
      entry.value.sort((a, b) {
        final timeCompare = b.totalMinutes.compareTo(a.totalMinutes);
        if (timeCompare != 0) return timeCompare;
        return a.type.compareTo(b.type);
      });
    }

    return map;
  }

  List<_TrainingSummaryItem> get _ranking {
    final list = _selectedRows.toList()
      ..sort((a, b) {
        final timeCompare = b.totalMinutes.compareTo(a.totalMinutes);
        if (timeCompare != 0) return timeCompare;
        return a.type.compareTo(b.type);
      });

    return list;
  }

  String _monthLabel(DateTime month) {
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

    return '${labels[month.month]}/${month.year}';
  }

  String _shortMonthLabel(DateTime month) {
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

    return '${labels[month.month]}/${month.year}';
  }

  String _formatMinutes(int minutes) {
    final hours = minutes ~/ 60;
    final mins = minutes % 60;

    if (hours <= 0) return '${mins}min';
    if (mins == 0) return '${hours}h';
    return '${hours}h ${mins}min';
  }

  Color _categoryColor(String category) {
    switch (category) {
      case 'Fundamentos':
        return olympusSuccess;
      case 'Tático':
        return olympusPurple;
      case 'Físico':
        return olympusWarning;
      default:
        return olympusBlue;
    }
  }

  IconData _categoryIcon(String category) {
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

  List<String> get _insights {
    if (_selectedRows.isEmpty) {
      return [
        'Ainda não há blocos planejados neste mês.',
        'Abra um treino, crie blocos e salve categoria, tipo e horários para gerar esta visão.',
      ];
    }

    final categoryMinutes = _minutesByCategory;
    final total = math.max(1, _totalMinutes);
    final ranking = _ranking;

    final top = ranking.isEmpty ? null : ranking.first;

    final fundamentos = categoryMinutes['Fundamentos'] ?? 0;
    final tatico = categoryMinutes['Tático'] ?? 0;
    final fisico = categoryMinutes['Físico'] ?? 0;

    final items = <String>[];

    if (top != null) {
      items.add(
        '${top.type} foi o foco principal do mês com ${_formatMinutes(top.totalMinutes)} planejados.',
      );
    }

    final fundamentosPct = (fundamentos / total * 100).round();
    final taticoPct = (tatico / total * 100).round();
    final fisicoPct = (fisico / total * 100).round();

    if (fundamentosPct >= 55) {
      items.add(
          'O mês está muito concentrado em fundamentos ($fundamentosPct%).');
    } else if (fundamentosPct <= 20 && fundamentos > 0) {
      items.add(
          'Fundamentos estão com baixo volume relativo ($fundamentosPct%).');
    }

    if (taticoPct <= 15 && _totalMinutes >= 120) {
      items.add(
          'Volume tático baixo ($taticoPct%). Considere incluir leitura de jogo, transição ou sistema.');
    }

    if (fisicoPct <= 10 && _totalMinutes >= 120) {
      items.add(
          'Volume físico baixo ($fisicoPct%). Pode valer inserir mobilidade, força ou prevenção.');
    }

    if (items.length < 4) {
      items.add(
        'Distribuição atual: Fundamentos $fundamentosPct%, Tático $taticoPct%, Físico $fisicoPct%.',
      );
    }

    return items.take(5).toList();
  }

  Widget _background() {
    return Stack(
      children: [
        Positioned.fill(
          child: OlympusBrandBackgroundImage(
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) {
              return Container(color: olympusBlue);
            },
          ),
        ),
        Positioned.fill(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 2.5, sigmaY: 2.5),
            child: Container(color: Colors.transparent),
          ),
        ),
        Positioned.fill(
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  olympusBlue.withOpacity(0.78),
                  olympusBlue.withOpacity(0.46),
                  Colors.black.withOpacity(0.74),
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
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: LinearGradient(
          colors: [
            Color.lerp(olympusBlue, Colors.black, 0.36)!,
            Color.lerp(olympusBlue, Colors.black, 0.08)!,
            Color.lerp(olympusBlue, Colors.white, 0.18)!,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: olympusGold.withOpacity(0.72), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: olympusGold.withOpacity(0.20),
            blurRadius: 24,
            spreadRadius: 1,
            offset: const Offset(0, 10),
          ),
          BoxShadow(
            color: Colors.black.withOpacity(0.24),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            top: -36,
            right: -26,
            child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.06),
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
                          color: olympusGold.withOpacity(0.34),
                          blurRadius: 14,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                    child: Icon(
                      Icons.analytics_rounded,
                      color: olympusBlue,
                      size: 30,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _isCoordinator
                          ? 'Dashboard da Equipe Técnica'
                          : 'Dashboard do Treinador',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Atualizar',
                    onPressed: _loadDashboard,
                    icon: const Icon(Icons.refresh_rounded),
                    color: Colors.white,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                _isCoordinator
                    ? 'Planejamentos consolidados de $_scopeCoachCount profissionais'
                    : 'Planejamento mensal por Fundamentos, Tático e Físico',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.78),
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 14),
              _monthSelector(),
            ],
          ),
        ],
      ),
    );
  }

  Widget _monthSelector() {
    final months = _availableMonths;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: months.map((month) {
          final selected = _sameMonth(month, _selectedMonth);

          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(_shortMonthLabel(month)),
              selected: selected,
              onSelected: (_) {
                setState(() {
                  _selectedMonth = month;
                });
              },
              showCheckmark: false,
              selectedColor: olympusGold,
              backgroundColor: const Color(0xFF315A82),
              side: BorderSide(
                color: selected ? olympusGold : Colors.white.withOpacity(0.20),
              ),
              labelStyle: TextStyle(
                color: selected ? olympusBlue : Colors.white,
                fontWeight: FontWeight.w900,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          );
        }).toList(),
      ),
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
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: Container(
            padding: padding ?? const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.94),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white.withOpacity(0.50)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.13),
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

  Widget _overviewCard() {
    final categoryMinutes = _minutesByCategory;
    final total = math.max(1, _totalMinutes);

    return _glassCard(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      children: [
        Row(
          children: [
            Icon(Icons.timer_rounded, color: olympusGold, size: 26),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _monthLabel(_selectedMonth),
                style: TextStyle(
                  color: olympusBlue,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            Text(
              _formatMinutes(_totalMinutes),
              style: TextStyle(
                color: olympusBlue,
                fontSize: 22,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
        const SizedBox(height: 5),
        Text(
          '$_totalBlocks bloco(s) planejado(s) no mês',
          style: const TextStyle(
            color: olympusMuted,
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 172,
          child: _totalMinutes == 0
              ? const Center(
                  child: Text(
                    'Sem tempo planejado neste mês.',
                    style: TextStyle(
                      color: olympusMuted,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                )
              : CustomPaint(
                  painter: _CategoryDistributionPainter(
                    data: categoryMinutes,
                    colors: {
                      'Fundamentos': olympusSuccess,
                      'Tático': olympusPurple,
                      'Físico': olympusWarning,
                    },
                    labelColor: olympusMuted,
                    total: total,
                  ),
                  child: const SizedBox.expand(),
                ),
        ),
        const SizedBox(height: 12),
        _categoryProgressRow(
          category: 'Fundamentos',
          minutes: categoryMinutes['Fundamentos'] ?? 0,
          total: total,
        ),
        const SizedBox(height: 9),
        _categoryProgressRow(
          category: 'Tático',
          minutes: categoryMinutes['Tático'] ?? 0,
          total: total,
        ),
        const SizedBox(height: 9),
        _categoryProgressRow(
          category: 'Físico',
          minutes: categoryMinutes['Físico'] ?? 0,
          total: total,
        ),
      ],
    );
  }

  Widget _categoryProgressRow({
    required String category,
    required int minutes,
    required int total,
  }) {
    final color = _categoryColor(category);
    final percent = total == 0 ? 0.0 : minutes / total;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(_categoryIcon(category), color: color, size: 18),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                category,
                style: TextStyle(
                  color: olympusBlue,
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            Text(
              '${_formatMinutes(minutes)} • ${(percent * 100).round()}%',
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: percent.clamp(0, 1),
            minHeight: 9,
            backgroundColor: olympusBorder,
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
      ],
    );
  }

  Widget _categoryCards() {
    final grouped = _rowsByCategory;
    final categories = ['Fundamentos', 'Tático', 'Físico'];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isNarrow = constraints.maxWidth < 680;

          if (isNarrow) {
            return Column(
              children: categories.map((category) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _categoryCard(
                    category: category,
                    rows: grouped[category] ?? [],
                  ),
                );
              }).toList(),
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: categories.map((category) {
              final isLast = category == categories.last;
              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(right: isLast ? 0 : 10),
                  child: _categoryCard(
                    category: category,
                    rows: grouped[category] ?? [],
                  ),
                ),
              );
            }).toList(),
          );
        },
      ),
    );
  }

  Widget _categoryCard({
    required String category,
    required List<_TrainingSummaryItem> rows,
  }) {
    final color = _categoryColor(category);
    final directTotal = rows.fold<int>(0, (sum, row) => sum + row.totalMinutes);
    final total = category == 'Físico'
        ? (_minutesByCategory['Físico'] ?? directTotal)
        : directTotal;
    final indirectPhysicalMinutes = math.max(0, total - directTotal);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _openCategoryDetail(category, rows),
        borderRadius: BorderRadius.circular(22),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.95),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: color.withOpacity(0.22)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.10),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child:
                        Icon(_categoryIcon(category), color: color, size: 22),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      category,
                      style: TextStyle(
                        color: olympusBlue,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  Text(
                    _formatMinutes(total),
                    style: TextStyle(
                      color: color,
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    Icons.arrow_forward_ios_rounded,
                    color: color,
                    size: 15,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (category == 'Físico' && indirectPhysicalMinutes > 0) ...[
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: olympusWarning.withOpacity(0.09),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '+ ${_formatMinutes(indirectPhysicalMinutes)} de esforço físico em blocos de Fundamentos e Tático',
                    style: const TextStyle(
                      color: olympusMuted,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
              if (rows.isEmpty)
                const Text(
                  'Sem blocos neste mês.',
                  style: TextStyle(
                    color: olympusMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                )
              else
                ...rows.take(5).map((row) {
                  final max = math.max(1, rows.first.totalMinutes);
                  final percent = row.totalMinutes / max;

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                row.type,
                                style: TextStyle(
                                  color: olympusBlue,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            Text(
                              _formatMinutes(row.totalMinutes),
                              style: TextStyle(
                                color: color,
                                fontSize: 12,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ],
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
                  );
                }),
            ],
          ),
        ),
      ),
    );
  }

  void _openCategoryDetail(
    String category,
    List<_TrainingSummaryItem> rows,
  ) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CoachTrainingCategoryDetailPage(
          category: category,
          monthLabel: _monthLabel(_selectedMonth),
          rows: rows
              .map(
                (row) => {
                  'type': row.type,
                  'minutes': row.totalMinutes,
                  'blocks': row.totalBlocks,
                },
              )
              .toList(),
        ),
      ),
    );
  }

  Widget _rankingSection() {
    final ranking = _ranking.take(10).toList();

    return _glassCard(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      children: [
        Row(
          children: [
            Icon(Icons.leaderboard_rounded, color: olympusGold, size: 24),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Ranking de foco do mês',
                style: TextStyle(
                  color: olympusBlue,
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (ranking.isEmpty)
          const Text(
            'Sem dados para montar ranking.',
            style: TextStyle(
              color: olympusMuted,
              fontWeight: FontWeight.w700,
            ),
          )
        else
          ...ranking.asMap().entries.map((entry) {
            final index = entry.key;
            final row = entry.value;
            final color = _categoryColor(row.category);

            return Container(
              margin: const EdgeInsets.only(bottom: 9),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withOpacity(0.08),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: color.withOpacity(0.16)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.16),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${index + 1}',
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          row.type,
                          style: TextStyle(
                            color: olympusBlue,
                            fontSize: 13,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${row.category} • ${row.totalBlocks} bloco(s)',
                          style: const TextStyle(
                            color: olympusMuted,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    _formatMinutes(row.totalMinutes),
                    style: TextStyle(
                      color: color,
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            );
          }),
      ],
    );
  }

  Widget _insightsSection() {
    return _glassCard(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 28),
      children: [
        Row(
          children: [
            Icon(Icons.lightbulb_outline_rounded, color: olympusGold, size: 24),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Insights do planejamento',
                style: TextStyle(
                  color: olympusBlue,
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ..._insights.map((text) {
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
                Icon(Icons.bolt_rounded, color: olympusGold, size: 21),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    text,
                    style: const TextStyle(
                      color: olympusMuted,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      height: 1.32,
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

  void _openTrainingPlanner() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const CoachTrainingSessionsPage(
          initialTipoEvento: 'treino',
          lockTipoEvento: true,
          pageTitle: 'Planejamento de treinos',
        ),
      ),
    );
  }

  Widget _planningAccessMenu() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 4, 16, 10),
          child: Text(
            'Escolha onde deseja trabalhar',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        _trainingPlannerAccessCard(),
      ],
    );
  }

  Widget _trainingPlannerAccessCard() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _openTrainingPlanner,
          borderRadius: BorderRadius.circular(22),
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 15, 14, 15),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFF7D95E), Color(0xFFD4AF37)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: const Color(0xFFFFE98F), width: 1.2),
              boxShadow: [
                BoxShadow(
                  color: olympusGold.withOpacity(0.34),
                  blurRadius: 22,
                  offset: const Offset(0, 9),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: olympusBlue,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(
                    Icons.edit_calendar_rounded,
                    color: Colors.white,
                    size: 26,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Planejamento de Treinos',
                        style: TextStyle(
                          color: olympusBlue,
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: olympusBlue.withOpacity(.10),
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: Text(
                          'CRIAR • EDITAR • AVALIAR',
                          style: TextStyle(
                            color: olympusBlue,
                            fontSize: 10,
                            letterSpacing: .5,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: olympusBlue,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.arrow_forward_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Container(
        margin: const EdgeInsets.all(20),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.96),
          borderRadius: BorderRadius.circular(22),
        ),
        child: Text(
          'Ainda não há planejamento salvo no Supabase.\n\nAbra um treino, crie os blocos e salve categoria, tipo e horários.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: olympusBlue,
            fontSize: 14,
            fontWeight: FontWeight.w800,
            height: 1.35,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasAnyData = _allRows.isNotEmpty;

    return Scaffold(
      backgroundColor: olympusBg,
      appBar: AppBar(
        title: const Text('Planejamento'),
        backgroundColor: olympusBlue,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Atualizar',
            onPressed: _loadDashboard,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: Stack(
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
          else if (!hasAnyData)
            RefreshIndicator(
              onRefresh: _loadDashboard,
              child: ListView(
                children: [
                  const SizedBox(height: 16),
                  _planningAccessMenu(),
                  SizedBox(height: MediaQuery.of(context).size.height * 0.18),
                  _emptyState(),
                ],
              ),
            )
          else
            RefreshIndicator(
              onRefresh: _loadDashboard,
              child: ListView(
                padding: const EdgeInsets.only(bottom: 8),
                children: [
                  _header(),
                  _planningAccessMenu(),
                  _overviewCard(),
                  _categoryCards(),
                  _rankingSection(),
                  _insightsSection(),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _TrainingSummaryItem {
  const _TrainingSummaryItem({
    required this.coachId,
    required this.month,
    required this.category,
    required this.type,
    required this.totalMinutes,
    required this.totalHours,
    required this.totalBlocks,
  });

  final String coachId;
  final DateTime month;
  final String category;
  final String type;
  final int totalMinutes;
  final double totalHours;
  final int totalBlocks;

  factory _TrainingSummaryItem.fromMap(Map<String, dynamic> map) {
    final monthRaw = (map['month'] ?? '').toString();
    final parsedMonth = DateTime.tryParse(monthRaw) ?? DateTime.now();

    return _TrainingSummaryItem(
      coachId: (map['coach_id'] ?? '').toString(),
      month: DateTime(parsedMonth.year, parsedMonth.month),
      category: (map['category'] ?? 'Sem categoria').toString(),
      type: (map['type'] ?? 'Sem tipo').toString(),
      totalMinutes: _toInt(map['total_minutes']),
      totalHours: _toDouble(map['total_hours']),
      totalBlocks: _toInt(map['total_blocks']),
    );
  }

  static int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse((value ?? '0').toString()) ?? 0;
  }

  static double _toDouble(dynamic value) {
    if (value is double) return value;
    if (value is num) return value.toDouble();
    return double.tryParse((value ?? '0').toString()) ?? 0;
  }
}

class _CategoryDistributionPainter extends CustomPainter {
  _CategoryDistributionPainter({
    required this.data,
    required this.colors,
    required this.labelColor,
    required this.total,
  });

  final Map<String, int> data;
  final Map<String, Color> colors;
  final Color labelColor;
  final int total;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width * 0.30, size.height / 2);
    final radius = math.min(size.height * 0.38, size.width * 0.22);

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 18
      ..strokeCap = StrokeCap.round;

    double startAngle = -math.pi / 2;
    final categories = ['Fundamentos', 'Tático', 'Físico'];

    for (final category in categories) {
      final value = data[category] ?? 0;
      if (value <= 0) continue;

      final sweep = (value / math.max(1, total)) * math.pi * 2;
      paint.color = (colors[category] ?? Colors.blue);

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweep,
        false,
        paint,
      );

      startAngle += sweep;
    }

    final innerPaint = Paint()..color = Colors.white.withOpacity(0.92);
    canvas.drawCircle(center, radius - 18, innerPaint);

    final totalPainter = TextPainter(
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
      text: const TextSpan(
        text: 'Total',
        style: TextStyle(
          color: Color(0xFF53657B),
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    )..layout();

    totalPainter.paint(
      canvas,
      Offset(center.dx - totalPainter.width / 2, center.dy - 20),
    );

    final minutesText = '${total}min';
    final minutesPainter = TextPainter(
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
      text: TextSpan(
        text: minutesText,
        style: const TextStyle(
          color: Color(0xFF1E3A5F),
          fontSize: 16,
          fontWeight: FontWeight.w900,
        ),
      ),
    )..layout(maxWidth: radius * 1.6);

    minutesPainter.paint(
      canvas,
      Offset(center.dx - minutesPainter.width / 2, center.dy - 2),
    );

    final legendX = size.width * 0.58;
    double legendY = size.height * 0.24;

    for (final category in categories) {
      final value = data[category] ?? 0;
      final percent = total == 0 ? 0 : (value / total * 100).round();
      final color = colors[category] ?? Colors.blue;

      canvas.drawCircle(
        Offset(legendX, legendY + 6),
        5,
        Paint()..color = color,
      );

      final legendPainter = TextPainter(
        textDirection: TextDirection.ltr,
        text: TextSpan(
          children: [
            TextSpan(
              text: '$category\n',
              style: const TextStyle(
                color: Color(0xFF1E3A5F),
                fontSize: 12,
                fontWeight: FontWeight.w900,
                height: 1.2,
              ),
            ),
            TextSpan(
              text: '$value min • $percent%',
              style: TextStyle(
                color: labelColor,
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
  bool shouldRepaint(covariant _CategoryDistributionPainter oldDelegate) {
    return oldDelegate.data != data ||
        oldDelegate.total != total ||
        oldDelegate.colors != colors;
  }
}
