import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AdminCompetitionsPage extends StatefulWidget {
  final bool canEdit;

  const AdminCompetitionsPage({super.key, required this.canEdit});

  @override
  State<AdminCompetitionsPage> createState() => _AdminCompetitionsPageState();
}

class _AdminCompetitionsPageState extends State<AdminCompetitionsPage>
    with SingleTickerProviderStateMixin {
  final SupabaseClient _supabase = Supabase.instance.client;

  static const Color olympusBlue = Color(0xFF1E3A5F);
  static const Color olympusLightBlue = Color(0xFF2C5F8D);
  static const Color olympusGold = Color(0xFFD4AF37);
  static const Color pageBackground = Color(0xFFF6F1FA);

  late final TabController _tabController;

  bool _loading = true;
  String? _error;

  List<_CompetitionGroup> _leagueGroups = [];
  List<_FriendlyYearGroup> _friendlyGroups = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadCompetitions();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadCompetitions() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final eventsResponse = await _supabase.from('events').select('''
            id,
            event_name,
            event_type,
            event_date,
            event_time,
            championship_name,
            street,
            street_number,
            neighborhood,
            city,
            state,
            gender,
            created_at,
            event_results (
              id,
              final_result_label,
              olympus_sets_won,
              opponent_sets_won,
              event_result_sets (
                id,
                set_number,
                olympus_score,
                opponent_score
              )
            )
          ''');

      final allEvents = eventsResponse
          .map(
            (row) =>
                _EventCompetitionCard.fromMap(Map<String, dynamic>.from(row)),
          )
          .toList();

      final leagueEvents = allEvents
          .where(
            (e) =>
                e.type == 'campeonato' && e.championshipName.trim().isNotEmpty,
          )
          .toList();

      final friendlyEvents =
          allEvents.where((e) => e.type == 'amistoso').toList();

      final Map<String, List<_EventCompetitionCard>> leagueMap = {};
      for (final event in leagueEvents) {
        leagueMap
            .putIfAbsent(event.championshipName.trim(), () => [])
            .add(event);
      }

      final leagueGroups = leagueMap.entries.map((entry) {
        final items = [...entry.value]..sort(_compareEventsAsc);
        return _CompetitionGroup(title: entry.key, items: items);
      }).toList()
        ..sort(
          (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
        );

      final Map<int, Map<String, List<_EventCompetitionCard>>> friendlyMap = {};
      for (final event in friendlyEvents) {
        final year = event.eventDate?.year ?? 0;
        final opponent = event.opponentName;
        friendlyMap.putIfAbsent(year, () => {});
        friendlyMap[year]!.putIfAbsent(opponent, () => []).add(event);
      }

      final friendlyGroups = friendlyMap.entries.map((yearEntry) {
        final opponentGroups = yearEntry.value.entries.map((opponentEntry) {
          final items = [...opponentEntry.value]..sort(_compareEventsAsc);
          return _CompetitionGroup(title: opponentEntry.key, items: items);
        }).toList()
          ..sort(
            (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
          );

        return _FriendlyYearGroup(year: yearEntry.key, groups: opponentGroups);
      }).toList()
        ..sort((a, b) => b.year.compareTo(a.year));

      if (!mounted) return;
      setState(() {
        _leagueGroups = leagueGroups;
        _friendlyGroups = friendlyGroups;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Erro ao carregar competições: $e';
        _loading = false;
      });
    }
  }

  int _compareEventsAsc(_EventCompetitionCard a, _EventCompetitionCard b) {
    final aDate = a.eventDate ?? DateTime(1900);
    final bDate = b.eventDate ?? DateTime(1900);
    final cmp = aDate.compareTo(bDate);
    if (cmp != 0) return cmp;
    return a.time.compareTo(b.time);
  }

  Future<void> _openResultEditor(_EventCompetitionCard event) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AdminCompetitionResultPage(event: event),
      ),
    );
    await _loadCompetitions();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: pageBackground,
      appBar: AppBar(
        backgroundColor: olympusBlue,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Competições',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: [
          IconButton(
            onPressed: _loadCompetitions,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: olympusGold,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(text: 'Liga / Campeonatos'),
            Tab(text: 'Amistosos'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _ErrorState(message: _error!, onRetry: _loadCompetitions)
              : RefreshIndicator(
                  onRefresh: _loadCompetitions,
                  child: TabBarView(
                    controller: _tabController,
                    children: [_buildLeagueTab(), _buildFriendlyTab()],
                  ),
                ),
    );
  }

  Widget _buildLeagueTab() {
    if (_leagueGroups.isEmpty) {
      return const _EmptyState(
        icon: Icons.emoji_events_outlined,
        title: 'Nenhuma liga encontrada',
        subtitle: 'Cadastre eventos com o nome preenchido em Campeonato/Liga.',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _leagueGroups.length,
      itemBuilder: (context, index) {
        final group = _leagueGroups[index];
        return _CompetitionSectionCard(
          title: group.title,
          subtitle:
              '${group.items.length} jogo${group.items.length == 1 ? '' : 's'}',
          children: group.items
              .map(
                (event) => Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: _CompetitionMatchCard(
                    event: event,
                    headerTitle: group.title,
                    canEdit: widget.canEdit,
                    onTapEdit: () => _openResultEditor(event),
                  ),
                ),
              )
              .toList(),
        );
      },
    );
  }

  Widget _buildFriendlyTab() {
    if (_friendlyGroups.isEmpty) {
      return const _EmptyState(
        icon: Icons.sports_volleyball_outlined,
        title: 'Nenhum amistoso encontrado',
        subtitle: 'Os amistosos aparecerão agrupados por ano e adversário.',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _friendlyGroups.length,
      itemBuilder: (context, index) {
        final yearGroup = _friendlyGroups[index];
        return _CompetitionSectionCard(
          title:
              'Amistosos ${yearGroup.year == 0 ? 'Sem ano' : yearGroup.year}',
          subtitle:
              '${yearGroup.groups.fold<int>(0, (acc, item) => acc + item.items.length)} jogo(s)',
          children: yearGroup.groups
              .map(
                (group) => Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: _CompetitionSubSection(
                    title: 'vs ${group.title}',
                    children: group.items
                        .map(
                          (event) => Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: _CompetitionMatchCard(
                              event: event,
                              headerTitle: 'Amistoso',
                              canEdit: widget.canEdit,
                              onTapEdit: () => _openResultEditor(event),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ),
              )
              .toList(),
        );
      },
    );
  }
}

class _CompetitionSectionCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<Widget> children;

  const _CompetitionSectionCard({
    required this.title,
    required this.children,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(color: const Color(0xFFDCD3EA)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: _AdminCompetitionsPageState.olympusBlue,
              fontSize: 19,
              fontWeight: FontWeight.w800,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle!,
              style: TextStyle(
                color: Colors.grey[700],
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          ...children,
        ],
      ),
    );
  }
}

class _CompetitionSubSection extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _CompetitionSubSection({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF9F4FF),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE0D4F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: _AdminCompetitionsPageState.olympusBlue,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
          ...children,
        ],
      ),
    );
  }
}

class _CompetitionMatchCard extends StatefulWidget {
  final _EventCompetitionCard event;
  final String headerTitle;
  final bool canEdit;
  final VoidCallback onTapEdit;

  const _CompetitionMatchCard({
    required this.event,
    required this.headerTitle,
    required this.canEdit,
    required this.onTapEdit,
  });

  @override
  State<_CompetitionMatchCard> createState() => _CompetitionMatchCardState();
}

class _CompetitionMatchCardState extends State<_CompetitionMatchCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final event = widget.event;
    final result = event.result;
    final hasResult = result != null;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF6EFFB),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE1D4EF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.headerTitle,
            style: const TextStyle(
              color: Colors.deepOrange,
              fontWeight: FontWeight.w800,
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Data: ${event.dateLabel} / Hora: ${event.time}',
            style: TextStyle(
              color: Colors.grey[800],
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            event.name,
            style: const TextStyle(
              color: _AdminCompetitionsPageState.olympusBlue,
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Endereço: ${event.addressLabel}',
            style: TextStyle(
              color: Colors.grey[700],
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 14),
          GestureDetector(
            onTap: hasResult
                ? () => setState(() => _expanded = !_expanded)
                : (widget.canEdit ? widget.onTapEdit : null),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: hasResult
                    ? _resultBackground(result!)
                    : const Color(0xFFFFF8E8),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: hasResult
                      ? _resultBorder(result!)
                      : const Color(0xFFD4AF37),
                  width: 1.6,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    hasResult ? _resultIcon(result!) : Icons.edit_note_rounded,
                    color: hasResult
                        ? _resultForeground(result!)
                        : const Color(0xFF8C6B10),
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      hasResult
                          ? result!.finalLabel
                          : 'Cadastrar resultado do jogo',
                      style: TextStyle(
                        color: hasResult
                            ? _resultForeground(result!)
                            : const Color(0xFF8C6B10),
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Text(
                    hasResult
                        ? '${result!.olympusSets} x ${result.opponentSets} em Sets'
                        : 'Abrir',
                    style: TextStyle(
                      color: hasResult
                          ? _resultForeground(result!)
                          : const Color(0xFF8C6B10),
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    hasResult
                        ? (_expanded
                            ? Icons.keyboard_arrow_up_rounded
                            : Icons.keyboard_arrow_down_rounded)
                        : Icons.chevron_right_rounded,
                    color: hasResult
                        ? _resultForeground(result!)
                        : const Color(0xFF8C6B10),
                  ),
                ],
              ),
            ),
          ),
          if (hasResult && _expanded) ...[
            const SizedBox(height: 10),
            ...result!.sets.map((setItem) {
              final olympusWon = setItem.olympusScore > setItem.opponentScore;
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: olympusWon
                      ? const Color(0xFFD9EBDD)
                      : const Color(0xFFF3F3F3),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: olympusWon
                        ? const Color(0xFF9DB4A5)
                        : const Color(0xFFE0E0E0),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${setItem.setNumber}º Set',
                        style: TextStyle(
                          color: Colors.grey[800],
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    _SetScoreBadge(
                      score: setItem.olympusScore,
                      highlighted: olympusWon,
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Text(
                        'x',
                        style: TextStyle(
                          color: Colors.grey[500],
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    _SetScoreBadge(
                      score: setItem.opponentScore,
                      highlighted: !olympusWon,
                      winnerUsesGold: true,
                    ),
                  ],
                ),
              );
            }),
          ],
          if (widget.canEdit) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: widget.onTapEdit,
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text('Editar'),
                style: TextButton.styleFrom(
                  foregroundColor: _AdminCompetitionsPageState.olympusBlue,
                ),
              ),
            ),
          ],
          if (widget.canEdit) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.photo_library_outlined, size: 18),
                label: const Text('Fotos'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Color _resultBackground(_EventResult result) {
    switch (result.outcome) {
      case _ResultOutcome.victory:
        return const Color(0xFFD6E6D6);
      case _ResultOutcome.defeat:
        return const Color(0xFFF3D8D8);
      case _ResultOutcome.draw:
        return const Color(0xFFE7E1D1);
      case _ResultOutcome.undefined:
        return const Color(0xFFECECEC);
    }
  }

  Color _resultBorder(_EventResult result) {
    switch (result.outcome) {
      case _ResultOutcome.victory:
        return const Color(0xFF329140);
      case _ResultOutcome.defeat:
        return const Color(0xFFCB4949);
      case _ResultOutcome.draw:
        return const Color(0xFFA6832D);
      case _ResultOutcome.undefined:
        return const Color(0xFFBDBDBD);
    }
  }

  Color _resultForeground(_EventResult result) {
    switch (result.outcome) {
      case _ResultOutcome.victory:
        return const Color(0xFF2D7F39);
      case _ResultOutcome.defeat:
        return const Color(0xFFB23838);
      case _ResultOutcome.draw:
        return const Color(0xFF8A6B1E);
      case _ResultOutcome.undefined:
        return const Color(0xFF616161);
    }
  }

  IconData _resultIcon(_EventResult result) {
    switch (result.outcome) {
      case _ResultOutcome.victory:
        return Icons.emoji_events_outlined;
      case _ResultOutcome.defeat:
        return Icons.cancel_outlined;
      case _ResultOutcome.draw:
        return Icons.remove_circle_outline;
      case _ResultOutcome.undefined:
        return Icons.info_outline;
    }
  }
}

class _SetScoreBadge extends StatelessWidget {
  final int score;
  final bool highlighted;
  final bool winnerUsesGold;

  const _SetScoreBadge({
    required this.score,
    required this.highlighted,
    this.winnerUsesGold = false,
  });

  @override
  Widget build(BuildContext context) {
    final bg = highlighted
        ? (winnerUsesGold ? const Color(0xFFF7C977) : const Color(0xFFA8C0B1))
        : Colors.white;
    final fg = highlighted ? const Color(0xFF1E3A5F) : const Color(0xFF6B6B6B);

    return Container(
      width: 42,
      height: 34,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        '$score',
        style: TextStyle(color: fg, fontWeight: FontWeight.w800, fontSize: 22),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _EmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        const SizedBox(height: 120),
        Icon(icon, size: 64, color: Colors.grey),
        const SizedBox(height: 14),
        Center(
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: _AdminCompetitionsPageState.olympusBlue,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Text(
            subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey[700], fontSize: 14),
          ),
        ),
      ],
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final Future<void> Function() onRetry;

  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        const SizedBox(height: 110),
        Icon(Icons.error_outline_rounded, size: 62, color: Colors.red[300]),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.red,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(height: 16),
        Center(
          child: ElevatedButton(
            onPressed: onRetry,
            style: ElevatedButton.styleFrom(
              backgroundColor: _AdminCompetitionsPageState.olympusBlue,
              foregroundColor: Colors.white,
            ),
            child: const Text('Tentar novamente'),
          ),
        ),
      ],
    );
  }
}

class AdminCompetitionResultPage extends StatefulWidget {
  final _EventCompetitionCard event;

  const AdminCompetitionResultPage({super.key, required this.event});

  @override
  State<AdminCompetitionResultPage> createState() =>
      _AdminCompetitionResultPageState();
}

class _AdminCompetitionResultPageState
    extends State<AdminCompetitionResultPage> {
  final SupabaseClient _supabase = Supabase.instance.client;
  static const Color olympusBlue = Color(0xFF1E3A5F);
  static const Color olympusGold = Color(0xFFD4AF37);

  bool _saving = false;
  late final TextEditingController _finalLabelController;
  late final TextEditingController _olympusSetsController;
  late final TextEditingController _opponentSetsController;
  late final List<_EditableSetRow> _sets;

  @override
  void initState() {
    super.initState();
    final result = widget.event.result;
    _finalLabelController = TextEditingController(
      text: result?.finalLabel ?? 'VITÓRIA',
    );
    _olympusSetsController = TextEditingController(
      text: '${result?.olympusSets ?? 0}',
    );
    _opponentSetsController = TextEditingController(
      text: '${result?.opponentSets ?? 0}',
    );

    final existingSets = result?.sets ?? [];
    _sets = List.generate(5, (index) {
      final number = index + 1;
      _EventSet? match;
      for (final item in existingSets) {
        if (item.setNumber == number) {
          match = item;
          break;
        }
      }
      return _EditableSetRow(
        setNumber: number,
        olympusController: TextEditingController(
          text: '${match?.olympusScore ?? 0}',
        ),
        opponentController: TextEditingController(
          text: '${match?.opponentScore ?? 0}',
        ),
      );
    });
  }

  @override
  void dispose() {
    _finalLabelController.dispose();
    _olympusSetsController.dispose();
    _opponentSetsController.dispose();
    for (final row in _sets) {
      row.olympusController.dispose();
      row.opponentController.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);

    try {
      final resultLabel = _finalLabelController.text.trim();
      final olympusSets = int.tryParse(_olympusSetsController.text.trim()) ?? 0;
      final opponentSets =
          int.tryParse(_opponentSetsController.text.trim()) ?? 0;

      final resultResponse = await _supabase
          .from('event_results')
          .upsert({
            'event_id': widget.event.id,
            'final_result_label': resultLabel,
            'olympus_sets_won': olympusSets,
            'opponent_sets_won': opponentSets,
          }, onConflict: 'event_id')
          .select()
          .single();

      final resultId = resultResponse['id'].toString();

      await _supabase
          .from('event_result_sets')
          .delete()
          .eq('event_result_id', resultId);

      final setsPayload = _sets.map((row) {
        return {
          'event_result_id': resultId,
          'set_number': row.setNumber,
          'olympus_score': int.tryParse(row.olympusController.text.trim()) ?? 0,
          'opponent_score':
              int.tryParse(row.opponentController.text.trim()) ?? 0,
        };
      }).toList();

      await _supabase.from('event_result_sets').insert(setsPayload);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Resultado salvo com sucesso!'),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao salvar resultado: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final event = widget.event;

    return Scaffold(
      backgroundColor: const Color(0xFFF6F1FA),
      appBar: AppBar(
        backgroundColor: olympusBlue,
        foregroundColor: Colors.white,
        title: const Text(
          'Resultado do jogo',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE1D4EF)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  event.championshipName.isEmpty
                      ? event.typeLabel
                      : event.championshipName,
                  style: const TextStyle(
                    color: olympusBlue,
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  event.name,
                  style: TextStyle(
                    color: Colors.grey[800],
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Data: ${event.dateLabel} / Hora: ${event.time}',
                  style: TextStyle(color: Colors.grey[700]),
                ),
                const SizedBox(height: 4),
                Text(
                  'Endereço: ${event.addressLabel}',
                  style: TextStyle(color: Colors.grey[700]),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _buildField(
            controller: _finalLabelController,
            label: 'Resultado final',
            hint: 'Ex: VITÓRIA, DERROTA, EMPATE',
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildField(
                  controller: _olympusSetsController,
                  label: 'Sets Olympus',
                  keyboardType: TextInputType.number,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildField(
                  controller: _opponentSetsController,
                  label: 'Sets adversário',
                  keyboardType: TextInputType.number,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          const Text(
            'Placares parciais',
            style: TextStyle(
              color: olympusBlue,
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          ..._sets.map((row) {
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFE1D4EF)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${row.setNumber}º Set',
                    style: const TextStyle(
                      color: olympusBlue,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _buildField(
                          controller: row.olympusController,
                          label: 'Olympus',
                          keyboardType: TextInputType.number,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildField(
                          controller: row.opponentController,
                          label: 'Adversário',
                          keyboardType: TextInputType.number,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          }),
          const SizedBox(height: 16),
          SizedBox(
            height: 50,
            child: ElevatedButton(
              onPressed: _saving ? null : _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: olympusGold,
                foregroundColor: olympusBlue,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: _saving
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text(
                      'Salvar resultado',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    String? hint,
    TextInputType? keyboardType,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }
}

class _EditableSetRow {
  final int setNumber;
  final TextEditingController olympusController;
  final TextEditingController opponentController;

  _EditableSetRow({
    required this.setNumber,
    required this.olympusController,
    required this.opponentController,
  });
}

class _CompetitionGroup {
  final String title;
  final List<_EventCompetitionCard> items;

  _CompetitionGroup({required this.title, required this.items});
}

class _FriendlyYearGroup {
  final int year;
  final List<_CompetitionGroup> groups;

  _FriendlyYearGroup({required this.year, required this.groups});
}

class _EventCompetitionCard {
  final String id;
  final String name;
  final String type;
  final String championshipName;
  final String time;
  final String addressLabel;
  final DateTime? eventDate;
  final _EventResult? result;

  _EventCompetitionCard({
    required this.id,
    required this.name,
    required this.type,
    required this.championshipName,
    required this.time,
    required this.addressLabel,
    required this.eventDate,
    required this.result,
  });

  factory _EventCompetitionCard.fromMap(Map<String, dynamic> map) {
    final resultsRaw = map['event_results'];
    Map<String, dynamic>? resultMap;
    if (resultsRaw is List && resultsRaw.isNotEmpty) {
      resultMap = Map<String, dynamic>.from(resultsRaw.first);
    } else if (resultsRaw is Map<String, dynamic>) {
      resultMap = resultsRaw;
    }

    final street = (map['street'] ?? '').toString().trim();
    final number = (map['street_number'] ?? '').toString().trim();
    final neighborhood = (map['neighborhood'] ?? '').toString().trim();
    final city = (map['city'] ?? '').toString().trim();
    final state = (map['state'] ?? '').toString().trim();

    final address = street.isEmpty
        ? '-'
        : '$street'
            '${number.isNotEmpty ? ', $number' : ''}'
            '${neighborhood.isNotEmpty ? ' - $neighborhood' : ''}'
            '${city.isNotEmpty ? ' - $city' : ''}'
            '${state.isNotEmpty ? '/$state' : ''}';

    return _EventCompetitionCard(
      id: (map['id'] ?? '').toString(),
      name: (map['event_name'] ?? '-').toString(),
      type: (map['event_type'] ?? '').toString().toLowerCase().trim(),
      championshipName: (map['championship_name'] ?? '').toString(),
      time: (map['event_time'] ?? '-').toString(),
      addressLabel: address,
      eventDate: _parseDate((map['event_date'] ?? '').toString()),
      result: resultMap == null ? null : _EventResult.fromMap(resultMap),
    );
  }

  String get dateLabel {
    if (eventDate == null) return '-';
    final d = eventDate!;
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
  }

  String get opponentName {
    final upper = name.toUpperCase();
    if (upper.startsWith('OLYMPUS VS ')) {
      return name.substring(11).trim();
    }
    return name;
  }

  String get typeLabel {
    switch (type) {
      case 'campeonato':
        return 'Campeonato';
      case 'amistoso':
        return 'Amistoso';
      default:
        return type;
    }
  }

  static DateTime? _parseDate(String value) {
    try {
      final parts = value.split('/');
      if (parts.length != 3) return null;
      return DateTime(
        int.parse(parts[2]),
        int.parse(parts[1]),
        int.parse(parts[0]),
      );
    } catch (_) {
      return null;
    }
  }
}

class _EventResult {
  final String id;
  final String finalLabel;
  final int olympusSets;
  final int opponentSets;
  final List<_EventSet> sets;

  _EventResult({
    required this.id,
    required this.finalLabel,
    required this.olympusSets,
    required this.opponentSets,
    required this.sets,
  });

  factory _EventResult.fromMap(Map<String, dynamic> map) {
    final setsRaw = (map['event_result_sets'] as List? ?? [])
        .map((item) => _EventSet.fromMap(Map<String, dynamic>.from(item)))
        .toList()
      ..sort((a, b) => a.setNumber.compareTo(b.setNumber));

    return _EventResult(
      id: (map['id'] ?? '').toString(),
      finalLabel: (map['final_result_label'] ?? 'Resultado').toString(),
      olympusSets: (map['olympus_sets_won'] as num?)?.toInt() ?? 0,
      opponentSets: (map['opponent_sets_won'] as num?)?.toInt() ?? 0,
      sets: setsRaw,
    );
  }

  _ResultOutcome get outcome {
    final label = finalLabel.toLowerCase();
    if (label.contains('vit')) return _ResultOutcome.victory;
    if (label.contains('der')) return _ResultOutcome.defeat;
    if (label.contains('emp')) return _ResultOutcome.draw;
    if (olympusSets > opponentSets) return _ResultOutcome.victory;
    if (olympusSets < opponentSets) return _ResultOutcome.defeat;
    if (olympusSets == opponentSets && olympusSets != 0) {
      return _ResultOutcome.draw;
    }
    return _ResultOutcome.undefined;
  }
}

class _EventSet {
  final String id;
  final int setNumber;
  final int olympusScore;
  final int opponentScore;

  _EventSet({
    required this.id,
    required this.setNumber,
    required this.olympusScore,
    required this.opponentScore,
  });

  factory _EventSet.fromMap(Map<String, dynamic> map) {
    return _EventSet(
      id: (map['id'] ?? '').toString(),
      setNumber: (map['set_number'] as num?)?.toInt() ?? 0,
      olympusScore: (map['olympus_score'] as num?)?.toInt() ?? 0,
      opponentScore: (map['opponent_score'] as num?)?.toInt() ?? 0,
    );
  }
}

enum _ResultOutcome { victory, defeat, draw, undefined }
