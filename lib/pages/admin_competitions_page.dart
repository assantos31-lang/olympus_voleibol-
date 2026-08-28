import 'dart:async';

import 'package:flutter/material.dart';
import '../theme/olympus_theme.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'dart:ui';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';

import '../services/organization_storage_service.dart';

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

  late final TabController _tabController;
  bool _loading = true;
  String? _error;
  List<_CompetitionGroup> _leagueGroups = [];
  List<_FriendlyYearGroup> _friendlyGroups = [];
  List<_HallAchievement> _hallAchievements = [];
  Map<String, String> _championshipImages = {};
  Map<String, String> _friendlyCardImages = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadCompetitions();
  }

  String _parseAchievementType(String label) {
    final value = label.toLowerCase();
    if (value.contains('campe')) return 'champion';
    if (value.contains('vice')) return 'runner_up';
    if (value.contains('3º') ||
        value.contains('3o') ||
        value.contains('terceiro')) {
      return 'third';
    }
    return 'none';
  }

  String _buildFinalResultLabel(String baseResult, String achievementType) {
    switch (achievementType) {
      case 'champion':
        return 'CAMPEÃO';
      case 'runner_up':
        return 'VICE-CAMPEÃO';
      case 'third':
        return '3º LUGAR';
      default:
        return baseResult;
    }
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
        set_format,
        championship_name,
        championship_image_url,
        is_featured,
        featured_image_url,
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
        ),
        event_photos (
          id,
          image_url,
          created_at
        )
      ''').timeout(const Duration(seconds: 20));

      final allEvents = eventsResponse
          .map(
            (row) =>
                _EventCompetitionCard.fromMap(Map<String, dynamic>.from(row)),
          )
          .toList();

      final championshipNames = allEvents
          .where((e) => e.type == 'campeonato' && e.championshipName.isNotEmpty)
          .map((e) => e.championshipName)
          .toSet();

      for (final champName in championshipNames) {
        final champEvent = allEvents.firstWhere(
          (e) => e.championshipName == champName,
          orElse: () => allEvents.first,
        );
        if (champEvent.championshipImageUrl != null &&
            champEvent.championshipImageUrl!.isNotEmpty) {
          _championshipImages[champName] = champEvent.championshipImageUrl!;
        }
      }

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

      final Map<int, Map<String, Map<String, List<_EventCompetitionCard>>>>
          friendlyMap = {};
      for (final event in friendlyEvents) {
        final year = event.eventDate?.year ?? 0;
        final gender = event.genderLabel;
        final opponent = event.opponentName;
        friendlyMap.putIfAbsent(year, () => {});
        friendlyMap[year]!.putIfAbsent(gender, () => {});
        friendlyMap[year]![gender]!.putIfAbsent(opponent, () => []).add(event);
      }

      final friendlyGroups = friendlyMap.entries.map((yearEntry) {
        final genderGroups = yearEntry.value.entries.map((genderEntry) {
          final opponentGroups = genderEntry.value.entries.map((opponentEntry) {
            final items = [...opponentEntry.value]..sort(_compareEventsAsc);
            return _CompetitionGroup(
              title: opponentEntry.key,
              items: items,
            );
          }).toList()
            ..sort(
              (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
            );

          final flatItems = opponentGroups
              .expand((group) => group.items)
              .toList()
            ..sort(_compareEventsAsc);

          final imageUrl = flatItems.isNotEmpty
              ? flatItems.first.championshipImageUrl?.trim() ?? ''
              : '';

          return _FriendlyGenderGroup(
            title: genderEntry.key,
            groups: opponentGroups,
            items: flatItems,
            imageUrl: imageUrl.isEmpty ? null : imageUrl,
          );
        }).toList()
          ..sort((a, b) {
            const order = {'Masculino': 0, 'Feminino': 1};
            final aOrder = order[a.title] ?? 99;
            final bOrder = order[b.title] ?? 99;
            if (aOrder != bOrder) return aOrder.compareTo(bOrder);
            return a.title.toLowerCase().compareTo(b.title.toLowerCase());
          });

        return _FriendlyYearGroup(year: yearEntry.key, groups: genderGroups);
      }).toList()
        ..sort((a, b) => b.year.compareTo(a.year));

      if (!mounted) return;

      final friendlyCardImages = <String, String>{};
      for (final yearGroup in friendlyGroups) {
        for (final genderGroup in yearGroup.groups) {
          final imageUrl = genderGroup.imageUrl;
          if (imageUrl != null && imageUrl.isNotEmpty) {
            friendlyCardImages['${yearGroup.year}_${genderGroup.title}'] =
                imageUrl;
          }
        }
      }

      final hallAchievements = <_HallAchievement>[];
      for (final group in leagueGroups) {
        if (group.items.isEmpty) continue;
        final sortedItems = [...group.items]..sort(_compareEventsAsc);
        final decisiveEvent = sortedItems.last;
        final result = decisiveEvent.result;
        final finalLabel = (result?.displayFinalLabel ?? '').toLowerCase();

        final hasAchievement = finalLabel.contains('campe') ||
            finalLabel.contains('vice') ||
            finalLabel.contains('3º') ||
            finalLabel.contains('3o') ||
            finalLabel.contains('terceiro');

        if (hasAchievement) {
          hallAchievements.add(
            _HallAchievement(
              title: group.title,
              eventName: decisiveEvent.name,
              year: decisiveEvent.eventDate?.year ?? 0,
              dateLabel: decisiveEvent.dateLabel,
              imageUrl: _championshipImages[group.title] ??
                  decisiveEvent.championshipImageUrl,
              resultLabel: result?.displayFinalLabel ?? 'CONQUISTA',
            ),
          );
        }
      }

      hallAchievements.sort((a, b) {
        if (a.year != b.year) return b.year.compareTo(a.year);
        return a.title.toLowerCase().compareTo(b.title.toLowerCase());
      });

      setState(() {
        _leagueGroups = leagueGroups;
        _friendlyGroups = friendlyGroups;
        _hallAchievements = hallAchievements;
        _friendlyCardImages = friendlyCardImages;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is TimeoutException
            ? 'A conexão demorou mais que o esperado. Tente atualizar novamente.'
            : 'Não foi possível carregar as competições agora. Verifique sua conexão e tente novamente.';
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

  int _getTotalPointsForGroup(_CompetitionGroup group) {
    int total = 0;
    for (final event in group.items) {
      total += event.result?.points ?? 0;
    }
    return total;
  }

  int? _getClassificationPointsForGroup(_CompetitionGroup group) {
    if (group.items.isEmpty) return null;
    final sortedItems = [...group.items]..sort(_compareEventsAsc);
    final decisiveEvent = sortedItems.last;
    return decisiveEvent.result?.classificationPoints;
  }

  int? _getQualifyingGamesForGroup(_CompetitionGroup group) {
    if (group.items.isEmpty) return null;
    final sortedItems = [...group.items]..sort(_compareEventsAsc);
    final decisiveEvent = sortedItems.last;
    return decisiveEvent.result?.qualifyingGames;
  }

  String? _getClassificationStageForGroup(_CompetitionGroup group) {
    if (group.items.isEmpty) return null;
    final sortedItems = [...group.items]..sort(_compareEventsAsc);
    final decisiveEvent = sortedItems.last;
    return decisiveEvent.result?.classificationStage;
  }

  String _extractDisplayLabel(String rawLabel) {
    final clean = rawLabel.trim();
    if (clean.isEmpty) return 'RESULTADO';
    final index = clean.indexOf('||');
    if (index == -1) return clean;
    return clean.substring(0, index).trim();
  }

  Map<String, String> _parseResultMetadata(String rawLabel) {
    final meta = <String, String>{};
    final index = rawLabel.indexOf('||');
    if (index == -1) return meta;

    final rawMeta = rawLabel.substring(index + 2);
    for (final part in rawMeta.split('|')) {
      final item = part.trim();
      if (item.isEmpty || !item.contains('=')) continue;
      final eq = item.indexOf('=');
      meta[item.substring(0, eq).trim()] = item.substring(eq + 1).trim();
    }
    return meta;
  }

  String _composeResultLabel(
    String displayLabel,
    Map<String, String> metadata,
  ) {
    final filtered = Map<String, String>.from(metadata)
      ..removeWhere((key, value) => value.trim().isEmpty);
    if (filtered.isEmpty) return displayLabel.trim();
    return '${displayLabel.trim()}||${filtered.entries.map((e) => '${e.key}=${e.value}').join('|')}';
  }

  String? _getAchievementLabelForGroup(_CompetitionGroup group) {
    for (final achievement in _hallAchievements) {
      if (achievement.title == group.title) {
        return achievement.resultLabel;
      }
    }
    return null;
  }

  Future<void> _openChampionshipClassificationEditor(
    _CompetitionGroup group,
  ) async {
    if (group.items.isEmpty) return;

    final currentPoints = _getClassificationPointsForGroup(group);
    final currentGames = _getQualifyingGamesForGroup(group);
    String selectedStage = _getClassificationStageForGroup(group) ?? '';
    final pointsController = TextEditingController(
      text: currentPoints != null ? '$currentPoints' : '',
    );
    final gamesController = TextEditingController(
      text: currentGames != null ? '$currentGames' : '',
    );

    final shouldSave = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
              ),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: const BoxDecoration(
                  color: Color(0xFFF6F1FA),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                ),
                child: SafeArea(
                  top: false,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 42,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.grey,
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Classificação da fase classificatória',
                        style: TextStyle(
                          color: olympusBlue,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        group.title,
                        style: TextStyle(
                          color: Colors.grey[700],
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: gamesController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Total de jogos',
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        value: selectedStage,
                        decoration: const InputDecoration(
                          labelText: 'Fase',
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: '',
                            child: Text('Sem classificação'),
                          ),
                          DropdownMenuItem(
                            value: 'Classificado para Oitavas de Finais',
                            child: Text('Classificado para Oitavas de Finais'),
                          ),
                          DropdownMenuItem(
                            value: 'Classificado para Quartas de Finais',
                            child: Text('Classificado para Quartas de Finais'),
                          ),
                          DropdownMenuItem(
                            value: 'Classificado para Semifinal',
                            child: Text('Classificado para Semifinal'),
                          ),
                          DropdownMenuItem(
                            value: 'Classificado para a Final',
                            child: Text('Classificado para a Final'),
                          ),
                        ],
                        onChanged: (value) {
                          setModalState(() {
                            selectedStage = value ?? '';
                          });
                        },
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: pointsController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Pontuação para classificação',
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => Navigator.of(context).pop(),
                              child: const Text('Cancelar'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () => Navigator.of(context).pop(true),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: olympusGold,
                                foregroundColor: olympusBlue,
                              ),
                              child: const Text(
                                'Salvar',
                                style: TextStyle(fontWeight: FontWeight.w800),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    if (shouldSave != true) return;

    await _saveChampionshipClassificationData(
      group,
      classificationPointsText: pointsController.text.trim(),
      qualifyingGamesText: gamesController.text.trim(),
      classificationStageText: selectedStage.trim(),
    );
  }

  Future<void> _saveChampionshipClassificationData(
    _CompetitionGroup group, {
    required String classificationPointsText,
    required String qualifyingGamesText,
    required String classificationStageText,
  }) async {
    try {
      if (group.items.isEmpty) return;
      final sortedItems = [...group.items]..sort(_compareEventsAsc);
      final decisiveEvent = sortedItems.last;
      final existingResult = decisiveEvent.result;
      final displayLabel = _extractDisplayLabel(
        existingResult?.finalLabel ?? 'RESULTADO',
      );
      final metadata = _parseResultMetadata(existingResult?.finalLabel ?? '');

      if (classificationPointsText.isEmpty) {
        metadata.remove('CLASSPTS');
      } else {
        metadata['CLASSPTS'] = classificationPointsText;
      }

      if (qualifyingGamesText.isEmpty) {
        metadata.remove('CLASSGAMES');
      } else {
        metadata['CLASSGAMES'] = qualifyingGamesText;
      }

      if (classificationStageText.isEmpty) {
        metadata.remove('CLASSSTAGE');
      } else {
        metadata['CLASSSTAGE'] = classificationStageText;
      }

      await _supabase.from('event_results').upsert({
        'event_id': decisiveEvent.id,
        'final_result_label': _composeResultLabel(displayLabel, metadata),
        'olympus_sets_won': existingResult?.olympusSets ?? 0,
        'opponent_sets_won': existingResult?.opponentSets ?? 0,
      }, onConflict: 'event_id');

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Dados de classificação salvos com sucesso!'),
          backgroundColor: Colors.green,
        ),
      );
      await _loadCompetitions();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Erro ao salvar dados de classificação: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _openChampionshipAchievementEditor(
    _CompetitionGroup group,
  ) async {
    String selectedType = 'none';
    final currentLabel = _getAchievementLabelForGroup(group) ?? '';
    if (currentLabel.isNotEmpty) {
      selectedType = _parseAchievementType(currentLabel);
    }

    final result = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                color: Color(0xFFF6F1FA),
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 42,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.grey,
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Editar Conquista',
                      style: const TextStyle(
                        color: olympusBlue,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      group.title,
                      style: TextStyle(
                        color: Colors.grey[700],
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      value: selectedType,
                      decoration: const InputDecoration(
                        labelText: 'Hall de Conquistas',
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'none',
                          child: Text('Sem conquista'),
                        ),
                        DropdownMenuItem(
                          value: 'third',
                          child: Text('3º lugar'),
                        ),
                        DropdownMenuItem(
                          value: 'runner_up',
                          child: Text('Vice-campeão'),
                        ),
                        DropdownMenuItem(
                          value: 'champion',
                          child: Text('Campeão'),
                        ),
                      ],
                      onChanged: (value) {
                        setModalState(() {
                          selectedType = value ?? 'none';
                        });
                      },
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: const Text('Cancelar'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () =>
                                Navigator.of(context).pop(selectedType),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: olympusGold,
                              foregroundColor: olympusBlue,
                            ),
                            child: const Text(
                              'Salvar',
                              style: TextStyle(fontWeight: FontWeight.w800),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (result == null) return;
    await _saveChampionshipAchievement(group, result);
  }

  Future<void> _removeChampionshipAchievement(_CompetitionGroup group) async {
    await _saveChampionshipAchievement(group, 'none');
  }

  Future<void> _saveChampionshipAchievement(
    _CompetitionGroup group,
    String achievementType,
  ) async {
    try {
      if (group.items.isEmpty) return;
      final sortedItems = [...group.items]..sort(_compareEventsAsc);
      final decisiveEvent = sortedItems.last;
      final existingResult = decisiveEvent.result;

      String baseResult = 'RESULTADO';
      if (existingResult != null) {
        switch (existingResult.outcome) {
          case _ResultOutcome.victory:
            baseResult = 'VITÓRIA';
            break;
          case _ResultOutcome.defeat:
            baseResult = 'DERROTA';
            break;
          case _ResultOutcome.draw:
            baseResult = 'EMPATE';
            break;
          case _ResultOutcome.undefined:
            baseResult = 'RESULTADO';
            break;
        }
      }

      final finalLabel = _composeResultLabel(
        _buildFinalResultLabel(baseResult, achievementType),
        _parseResultMetadata(existingResult?.finalLabel ?? ''),
      );

      await _supabase.from('event_results').upsert({
        'event_id': decisiveEvent.id,
        'final_result_label': finalLabel,
        'olympus_sets_won': existingResult?.olympusSets ?? 0,
        'opponent_sets_won': existingResult?.opponentSets ?? 0,
      }, onConflict: 'event_id');

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            achievementType == 'none'
                ? '✅ Conquista removida com sucesso!'
                : '✅ Conquista salva com sucesso!',
          ),
          backgroundColor: Colors.green,
        ),
      );
      await _loadCompetitions();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Erro ao salvar conquista: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _openResultEditor(_EventCompetitionCard event) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AdminCompetitionResultPage(event: event),
      ),
    );
    await _loadCompetitions();
  }

  Future<void> _openChampionshipGames(_CompetitionGroup group) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChampionshipGamesPage(
          championshipName: group.title,
          events: group.items,
          canEdit: widget.canEdit,
          imageUrl: _championshipImages[group.title],
        ),
      ),
    );
    await _loadCompetitions();
  }

  Future<void> _openFriendlyGenderGames(
    _FriendlyYearGroup yearGroup,
    _FriendlyGenderGroup genderGroup,
  ) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChampionshipGamesPage(
          championshipName:
              'Amistoso ${genderGroup.title} ${yearGroup.year == 0 ? '' : yearGroup.year}',
          events: genderGroup.items,
          canEdit: widget.canEdit,
          imageUrl:
              _friendlyCardImages['${yearGroup.year}_${genderGroup.title}'],
        ),
      ),
    );
    await _loadCompetitions();
  }

  Future<void> _openHallOfAchievements() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => HallOfAchievementsPage(
          achievements: _hallAchievements,
          championshipGroups: _leagueGroups,
          canEdit: widget.canEdit,
        ),
      ),
    );
    await _loadCompetitions();
  }

  Future<void> _uploadFriendlyCardImage(
    _FriendlyYearGroup yearGroup,
    _FriendlyGenderGroup genderGroup,
  ) async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);
    if (image == null) return;

    try {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('📤 Enviando imagem...'),
            backgroundColor: Colors.blue,
          ),
        );
      }

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final cleanName = '${yearGroup.year}_${genderGroup.title}'.replaceAll(
        RegExp(r'[^a-zA-Z0-9]'),
        '_',
      );
      final fileName = OrganizationStorageService.scopedPath(
        'friendlies/${cleanName}_$timestamp.jpg',
      );

      if (kIsWeb) {
        final bytes = await image.readAsBytes();
        await _supabase.storage.from('event-images').uploadBinary(
              fileName,
              bytes,
              fileOptions: const FileOptions(upsert: true),
            );
      } else {
        final file = File(image.path);
        await _supabase.storage.from('event-images').upload(
              fileName,
              file,
              fileOptions: const FileOptions(upsert: true),
            );
      }

      final imageUrl =
          _supabase.storage.from('event-images').getPublicUrl(fileName);

      for (final event in genderGroup.items) {
        await _supabase
            .from('events')
            .update({'championship_image_url': imageUrl}).eq('id', event.id);
      }

      if (mounted) {
        setState(() {
          _friendlyCardImages['${yearGroup.year}_${genderGroup.title}'] =
              imageUrl;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Imagem salva com sucesso!'),
            backgroundColor: Colors.green,
          ),
        );
        await _loadCompetitions();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Erro ao enviar imagem: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _openEventPhotos(_EventCompetitionCard event) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => EventPhotosPage(
          eventId: event.id,
          eventName: event.name,
          canEdit: widget.canEdit,
        ),
      ),
    );
    await _loadCompetitions();
  }

  Future<void> _openFeaturedMatch(_EventCompetitionCard event) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FeaturedMatchPage(
          eventId: event.id,
          eventName: event.name,
          isFeatured: event.isFeatured ?? false,
          featuredImageUrl: event.featuredImageUrl,
          canEdit: widget.canEdit,
        ),
      ),
    );
    await _loadCompetitions();
  }

  Widget _buildPremiumBackground() {
    return Stack(
      children: [
        Positioned.fill(
          child: OlympusBrandBackgroundImage(
            fit: BoxFit.cover,
            alignment: Alignment.center,
            errorBuilder: (context, error, stackTrace) {
              return Container(color: const Color(0xFF102845));
            },
          ),
        ),
        Positioned.fill(
          child: Container(color: Colors.black.withOpacity(0.14)),
        ),
        Positioned.fill(
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  olympusBlue.withOpacity(0.56),
                  olympusLightBlue.withOpacity(0.26),
                  Colors.black.withOpacity(0.62),
                ],
              ),
            ),
          ),
        ),
        Positioned.fill(
          child: Container(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(0, -0.78),
                radius: 1.08,
                colors: [
                  olympusGold.withOpacity(0.12),
                  Colors.transparent,
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildGlassTabShell({required Widget child}) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 420;
        final horizontal = isCompact ? 10.0 : 14.0;
        final top = isCompact ? 10.0 : 14.0;
        return Padding(
          padding: EdgeInsets.fromLTRB(horizontal, top, horizontal, 18),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.white.withOpacity(0.14),
                      Colors.white.withOpacity(0.08),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.20),
                    width: 1.1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.16),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: child,
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _uploadChampionshipImage(String championshipName) async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);
    if (image == null) return;

    try {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('📤 Enviando imagem...'),
            backgroundColor: Colors.blue,
          ),
        );
      }

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final cleanName = championshipName.replaceAll(
        RegExp(r'[^a-zA-Z0-9]'),
        '_',
      );
      final fileName = OrganizationStorageService.scopedPath(
        'championships/${cleanName}_$timestamp.jpg',
      );

      if (kIsWeb) {
        final bytes = await image.readAsBytes();
        await _supabase.storage.from('event-images').uploadBinary(
              fileName,
              bytes,
              fileOptions: const FileOptions(upsert: true),
            );
      } else {
        final file = File(image.path);
        await _supabase.storage.from('event-images').upload(
              fileName,
              file,
              fileOptions: const FileOptions(upsert: true),
            );
      }

      final imageUrl =
          _supabase.storage.from('event-images').getPublicUrl(fileName);

      final eventsToUpdate =
          _leagueGroups.firstWhere((g) => g.title == championshipName).items;
      for (final event in eventsToUpdate) {
        await _supabase
            .from('events')
            .update({'championship_image_url': imageUrl}).eq('id', event.id);
      }

      if (mounted) {
        setState(() {
          _championshipImages[championshipName] = imageUrl;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Imagem salva com sucesso!'),
            backgroundColor: Colors.green,
          ),
        );
        await _loadCompetitions();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Erro ao enviar imagem: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: false,
      appBar: AppBar(
        backgroundColor: olympusBlue.withOpacity(0.96),
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
      ),
      body: Stack(
        children: [
          Positioned.fill(child: _buildPremiumBackground()),
          _loading
              ? const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                )
              : _error != null
                  ? _ErrorState(message: _error!, onRetry: _loadCompetitions)
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        final isCompact = constraints.maxWidth < 380;
                        final horizontalPadding = isCompact ? 12.0 : 14.0;
                        final topPadding = isCompact ? 8.0 : 10.0;
                        final buttonRadius = isCompact ? 16.0 : 18.0;
                        final buttonVertical = isCompact ? 10.0 : 12.0;
                        final iconBoxSize = isCompact ? 34.0 : 42.0;
                        final titleFontSize = isCompact ? 14.0 : 16.0;
                        final subtitleFontSize = isCompact ? 10.0 : 11.5;
                        final trailingIconSize = isCompact ? 16.0 : 18.0;

                        return Column(
                          children: [
                            Padding(
                              padding: EdgeInsets.fromLTRB(
                                horizontalPadding,
                                topPadding,
                                horizontalPadding,
                                8,
                              ),
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [Color(0xFFFFE28A), olympusGold],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                  borderRadius:
                                      BorderRadius.circular(buttonRadius),
                                  boxShadow: [
                                    BoxShadow(
                                      color: olympusGold.withOpacity(0.22),
                                      blurRadius: isCompact ? 10 : 14,
                                      offset: Offset(0, isCompact ? 4 : 6),
                                    ),
                                  ],
                                ),
                                child: Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(
                                      buttonRadius,
                                    ),
                                    onTap: _openHallOfAchievements,
                                    child: Padding(
                                      padding: EdgeInsets.symmetric(
                                        horizontal: isCompact ? 12 : 16,
                                        vertical: buttonVertical,
                                      ),
                                      child: Row(
                                        children: [
                                          Container(
                                            width: iconBoxSize,
                                            height: iconBoxSize,
                                            decoration: BoxDecoration(
                                              color: Colors.white
                                                  .withOpacity(0.22),
                                              shape: BoxShape.circle,
                                            ),
                                            child: Icon(
                                              Icons.workspace_premium_rounded,
                                              color: olympusBlue,
                                              size: isCompact ? 20 : 24,
                                            ),
                                          ),
                                          SizedBox(width: isCompact ? 10 : 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Text(
                                                  'Hall de Conquistas',
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: TextStyle(
                                                    color: olympusBlue,
                                                    fontWeight: FontWeight.w900,
                                                    fontSize: titleFontSize,
                                                    height: 1.0,
                                                  ),
                                                ),
                                                const SizedBox(height: 2),
                                                Text(
                                                  _hallAchievements.isEmpty
                                                      ? 'Toque para ver títulos'
                                                      : '${_hallAchievements.length} conquista${_hallAchievements.length == 1 ? '' : 's'} registrada${_hallAchievements.length == 1 ? '' : 's'}',
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: TextStyle(
                                                    color:
                                                        olympusBlue.withOpacity(
                                                      0.78,
                                                    ),
                                                    fontWeight: FontWeight.w700,
                                                    fontSize: subtitleFontSize,
                                                    height: 1.0,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          SizedBox(width: isCompact ? 6 : 8),
                                          Icon(
                                            Icons.arrow_forward_ios_rounded,
                                            color: olympusBlue,
                                            size: trailingIconSize,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            TabBar(
                              controller: _tabController,
                              indicatorColor: olympusGold,
                              indicatorWeight: 3,
                              labelColor: Colors.white,
                              unselectedLabelColor: Colors.white70,
                              labelStyle: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: isCompact ? 13 : 14,
                              ),
                              tabs: const [
                                Tab(text: 'Liga / Campeonatos'),
                                Tab(text: 'Amistosos'),
                              ],
                            ),
                            Expanded(
                              child: RefreshIndicator(
                                color: olympusBlue,
                                onRefresh: _loadCompetitions,
                                child: TabBarView(
                                  controller: _tabController,
                                  children: [
                                    _buildGlassTabShell(
                                        child: _buildLeagueTab()),
                                    _buildGlassTabShell(
                                        child: _buildFriendlyTab()),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
        ],
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
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 18),
      itemCount: _leagueGroups.length,
      itemBuilder: (context, index) {
        final group = _leagueGroups[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: _ChampionshipCard(
            title: group.title,
            itemCount: group.items.length,
            imageUrl: _championshipImages[group.title],
            onImageTap: widget.canEdit
                ? () => _uploadChampionshipImage(group.title)
                : null,
            onTap: () => _openChampionshipGames(group),
            canEdit: widget.canEdit,
            achievementLabel: _getAchievementLabelForGroup(group),
            totalPoints: _getTotalPointsForGroup(group),
            classificationPoints: _getClassificationPointsForGroup(group),
            qualifyingGames: _getQualifyingGamesForGroup(group),
            classificationStage: _getClassificationStageForGroup(group),
            onEditClassification: widget.canEdit
                ? () => _openChampionshipClassificationEditor(group)
                : null,
            onEditAchievement: widget.canEdit
                ? () => _openChampionshipAchievementEditor(group)
                : null,
            onRemoveAchievement:
                widget.canEdit && _getAchievementLabelForGroup(group) != null
                    ? () => _removeChampionshipAchievement(group)
                    : null,
          ),
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
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 18),
      itemCount: _friendlyGroups.length,
      itemBuilder: (context, index) {
        final yearGroup = _friendlyGroups[index];
        final totalGames = yearGroup.groups.fold<int>(
          0,
          (acc, genderGroup) => acc + genderGroup.items.length,
        );

        return _CompetitionSectionCard(
          title:
              'Amistosos ${yearGroup.year == 0 ? 'Sem ano' : yearGroup.year}',
          subtitle: '$totalGames jogo(s)',
          children: [
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                final isMobile = constraints.maxWidth < 600;

                final cards = yearGroup.groups
                    .map(
                      (genderGroup) => Padding(
                        padding: EdgeInsets.only(bottom: isMobile ? 12 : 14),
                        child: _FriendlyCategoryCard(
                          title: 'Amistoso ${genderGroup.title}',
                          itemCount: genderGroup.items.length,
                          imageUrl: _friendlyCardImages[
                              '${yearGroup.year}_${genderGroup.title}'],
                          onImageTap: widget.canEdit
                              ? () => _uploadFriendlyCardImage(
                                    yearGroup,
                                    genderGroup,
                                  )
                              : null,
                          onTap: () =>
                              _openFriendlyGenderGames(yearGroup, genderGroup),
                          canEdit: widget.canEdit,
                        ),
                      ),
                    )
                    .toList();

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: cards,
                );
              },
            ),
          ],
        );
      },
    );
  }
}

class _FriendlyCategoryCard extends StatelessWidget {
  final String title;
  final int itemCount;
  final String? imageUrl;
  final VoidCallback? onImageTap;
  final VoidCallback onTap;
  final bool canEdit;

  const _FriendlyCategoryCard({
    required this.title,
    required this.itemCount,
    required this.imageUrl,
    this.onImageTap,
    required this.onTap,
    required this.canEdit,
  });

  @override
  Widget build(BuildContext context) {
    return _ChampionshipCard(
      title: title,
      itemCount: itemCount,
      imageUrl: imageUrl,
      onImageTap: onImageTap,
      onTap: onTap,
      canEdit: canEdit,
    );
  }
}

class _ChampionshipCard extends StatelessWidget {
  final String title;
  final int itemCount;
  final String? imageUrl;
  final VoidCallback? onImageTap;
  final VoidCallback onTap;
  final bool canEdit;
  final String? achievementLabel;
  final int totalPoints;
  final int? classificationPoints;
  final int? qualifyingGames;
  final String? classificationStage;
  final VoidCallback? onEditClassification;
  final VoidCallback? onEditAchievement;
  final VoidCallback? onRemoveAchievement;

  const _ChampionshipCard({
    required this.title,
    required this.itemCount,
    required this.imageUrl,
    this.onImageTap,
    required this.onTap,
    required this.canEdit,
    this.achievementLabel,
    this.totalPoints = 0,
    this.classificationPoints,
    this.qualifyingGames,
    this.classificationStage,
    this.onEditClassification,
    this.onEditAchievement,
    this.onRemoveAchievement,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 420;
        final imageSize = isCompact ? 68.0 : 80.0;
        final titleSize = isCompact ? 17.0 : 20.0;

        Widget imageWidget;
        if (canEdit) {
          imageWidget = GestureDetector(
            onTap: onImageTap,
            child: Container(
              width: imageSize,
              height: imageSize,
              decoration: BoxDecoration(
                color: _AdminCompetitionsPageState.olympusGold.withOpacity(
                  0.18,
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: _AdminCompetitionsPageState.olympusGold.withOpacity(
                    0.85,
                  ),
                  width: 1.8,
                ),
                image: imageUrl != null && imageUrl!.isNotEmpty
                    ? DecorationImage(
                        image: CachedNetworkImageProvider(imageUrl!),
                        fit: BoxFit.cover,
                      )
                    : null,
              ),
              child: imageUrl == null || imageUrl!.isEmpty
                  ? const Icon(
                      Icons.add_photo_alternate_outlined,
                      size: 34,
                      color: _AdminCompetitionsPageState.olympusGold,
                    )
                  : null,
            ),
          );
        } else {
          imageWidget = Container(
            width: imageSize,
            height: imageSize,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.10),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: Colors.white.withOpacity(0.16),
                width: 1.4,
              ),
              image: imageUrl != null && imageUrl!.isNotEmpty
                  ? DecorationImage(
                      image: CachedNetworkImageProvider(imageUrl!),
                      fit: BoxFit.cover,
                    )
                  : null,
            ),
            child: imageUrl == null || imageUrl!.isEmpty
                ? Icon(
                    Icons.emoji_events_outlined,
                    size: 32,
                    color: Colors.white.withOpacity(0.80),
                  )
                : null,
          );
        }

        final hasClassificationData = classificationPoints != null ||
            qualifyingGames != null ||
            (classificationStage != null &&
                classificationStage!.trim().isNotEmpty);
        final showAdminMenu = canEdit &&
            (onEditClassification != null || onEditAchievement != null);

        return Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(22),
            onTap: onTap,
            child: Ink(
              padding: EdgeInsets.all(isCompact ? 12 : 14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                gradient: LinearGradient(
                  colors: [
                    Colors.white.withOpacity(0.18),
                    Colors.white.withOpacity(0.10),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                border: Border.all(color: Colors.white.withOpacity(0.22)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.16),
                    blurRadius: 14,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: Row(
                children: [
                  imageWidget,
                  SizedBox(width: isCompact ? 12 : 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(
                                title,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: titleSize,
                                  fontWeight: FontWeight.w800,
                                  height: 1.1,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (showAdminMenu)
                              PopupMenuButton<String>(
                                onSelected: (value) {
                                  if (value == 'classification') {
                                    onEditClassification?.call();
                                  } else if (value == 'edit') {
                                    onEditAchievement?.call();
                                  } else if (value == 'remove') {
                                    onRemoveAchievement?.call();
                                  }
                                },
                                itemBuilder: (context) => [
                                  if (onEditClassification != null)
                                    const PopupMenuItem(
                                      value: 'classification',
                                      child: Text(
                                        'Inserir dados da classificação',
                                      ),
                                    ),
                                  if (onEditAchievement != null)
                                    const PopupMenuItem(
                                      value: 'edit',
                                      child: Text('Editar Conquista'),
                                    ),
                                  if (achievementLabel != null)
                                    const PopupMenuItem(
                                      value: 'remove',
                                      child: Text('Remover Conquista'),
                                    ),
                                ],
                                icon: const Icon(
                                  Icons.more_vert,
                                  color: Colors.white,
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: _AdminCompetitionsPageState.olympusGold
                                .withOpacity(0.18),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: _AdminCompetitionsPageState.olympusGold
                                  .withOpacity(0.28),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.sports_volleyball,
                                size: 16,
                                color: Colors.white,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                '$itemCount jogo${itemCount == 1 ? '' : 's'} • $totalPoints ponto${totalPoints == 1 ? '' : 's'}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        if (hasClassificationData) ...[
                          if (qualifyingGames != null)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Text(
                                'Total de jogos: $qualifyingGames',
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.92),
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          if (classificationStage != null &&
                              classificationStage!.trim().isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Text(
                                classificationStage!,
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.92),
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          if (classificationPoints != null)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Text(
                                'Pontuação para classificação: $classificationPoints',
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.92),
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                        ],
                        if (achievementLabel != null) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: _AdminCompetitionsPageState.olympusGold,
                              borderRadius: BorderRadius.circular(999),
                              boxShadow: [
                                BoxShadow(
                                  color: _AdminCompetitionsPageState.olympusGold
                                      .withOpacity(0.30),
                                  blurRadius: 8,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.emoji_events,
                                  size: 15,
                                  color: Colors.white,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  achievementLabel!,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),
                        ],
                        Row(
                          children: [
                            Text(
                              canEdit
                                  ? 'Toque para ver e editar jogos'
                                  : 'Toque para ver jogos',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.78),
                                fontSize: isCompact ? 11.5 : 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Icon(
                              Icons.chevron_right_rounded,
                              size: 18,
                              color: Colors.white.withOpacity(0.74),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class HallOfAchievementsPage extends StatelessWidget {
  final List<_HallAchievement> achievements;
  final List<_CompetitionGroup> championshipGroups;
  final bool canEdit;

  const HallOfAchievementsPage({
    super.key,
    required this.achievements,
    required this.championshipGroups,
    required this.canEdit,
  });

  static const Color olympusBlue = _AdminCompetitionsPageState.olympusBlue;
  static const Color olympusLightBlue =
      _AdminCompetitionsPageState.olympusLightBlue;
  static const Color olympusGold = _AdminCompetitionsPageState.olympusGold;

  Widget _buildPremiumBackground() {
    return Stack(
      children: [
        Positioned.fill(
          child: OlympusBrandBackgroundImage(
            fit: BoxFit.cover,
            alignment: Alignment.center,
            errorBuilder: (context, error, stackTrace) {
              return Container(color: const Color(0xFF102845));
            },
          ),
        ),
        Positioned.fill(
          child: Container(color: Colors.black.withOpacity(0.14)),
        ),
        Positioned.fill(
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  olympusBlue.withOpacity(0.56),
                  olympusLightBlue.withOpacity(0.26),
                  Colors.black.withOpacity(0.62),
                ],
              ),
            ),
          ),
        ),
        Positioned.fill(
          child: Container(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(0, -0.78),
                radius: 1.08,
                colors: [
                  olympusGold.withOpacity(0.12),
                  Colors.transparent,
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  _CompetitionGroup? _findGroup(String title) {
    for (final group in championshipGroups) {
      if (group.title == title) return group;
    }
    return null;
  }

  Future<void> _openTournamentPhotos(
    BuildContext context,
    _HallAchievement achievement,
  ) async {
    final group = _findGroup(achievement.title);
    if (group == null) return;

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TournamentPhotosGalleryPage(
          championshipTitle: achievement.title,
          events: group.items,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isCompact = MediaQuery.of(context).size.width < 380;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: olympusBlue.withOpacity(0.96),
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Hall de Conquistas',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: Stack(
        children: [
          Positioned.fill(child: _buildPremiumBackground()),
          achievements.isEmpty
              ? const _EmptyState(
                  icon: Icons.workspace_premium_outlined,
                  title: 'Nenhuma conquista cadastrada',
                  subtitle:
                      'As conquistas aparecerão aqui quando forem marcadas.',
                )
              : ListView.builder(
                  padding: EdgeInsets.fromLTRB(
                    isCompact ? 12 : 16,
                    16,
                    isCompact ? 12 : 16,
                    20,
                  ),
                  itemCount: achievements.length,
                  itemBuilder: (context, index) {
                    final achievement = achievements[index];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(22),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                          child: Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(22),
                              gradient: LinearGradient(
                                colors: [
                                  const Color(0xFFFFF1BF).withOpacity(0.96),
                                  const Color(0xFFFFE08A).withOpacity(0.92),
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              border: Border.all(
                                color: olympusGold.withOpacity(0.95),
                                width: 1.5,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: olympusGold.withOpacity(0.22),
                                  blurRadius: 16,
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
                                      width: 78,
                                      height: 78,
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(16),
                                        color: Colors.white.withOpacity(0.40),
                                        image: achievement.imageUrl != null &&
                                                achievement.imageUrl!.isNotEmpty
                                            ? DecorationImage(
                                                image:
                                                    CachedNetworkImageProvider(
                                                  achievement.imageUrl!,
                                                ),
                                                fit: BoxFit.cover,
                                              )
                                            : null,
                                      ),
                                      child: achievement.imageUrl == null ||
                                              achievement.imageUrl!.isEmpty
                                          ? const Icon(
                                              Icons.workspace_premium,
                                              size: 34,
                                              color: olympusBlue,
                                            )
                                          : null,
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 10,
                                              vertical: 6,
                                            ),
                                            decoration: BoxDecoration(
                                              color: olympusBlue,
                                              borderRadius:
                                                  BorderRadius.circular(999),
                                            ),
                                            child: Text(
                                              achievement.resultLabel,
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.w800,
                                                fontSize: 11,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          Text(
                                            achievement.title,
                                            style: const TextStyle(
                                              color: olympusBlue,
                                              fontSize: 18,
                                              fontWeight: FontWeight.w900,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            achievement.eventName,
                                            style: TextStyle(
                                              color: Colors.brown[700],
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          const SizedBox(height: 6),
                                          Text(
                                            '${achievement.dateLabel}${achievement.year == 0 ? '' : ' • ${achievement.year}'}',
                                            style: const TextStyle(
                                              color: olympusBlue,
                                              fontWeight: FontWeight.w700,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 14),
                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton.icon(
                                    onPressed: () => _openTournamentPhotos(
                                      context,
                                      achievement,
                                    ),
                                    icon: const Icon(
                                      Icons.photo_library_outlined,
                                      size: 18,
                                    ),
                                    label: const Text(
                                      'Ver todas as fotos do torneio',
                                    ),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: olympusBlue,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
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
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ],
      ),
    );
  }
}

class TournamentPhotosGalleryPage extends StatelessWidget {
  final String championshipTitle;
  final List<_EventCompetitionCard> events;

  const TournamentPhotosGalleryPage({
    super.key,
    required this.championshipTitle,
    required this.events,
  });

  static const Color olympusBlue = _AdminCompetitionsPageState.olympusBlue;
  static const Color olympusLightBlue =
      _AdminCompetitionsPageState.olympusLightBlue;

  Widget _buildPremiumBackground() {
    return Stack(
      children: [
        Positioned.fill(
          child: OlympusBrandBackgroundImage(
            fit: BoxFit.cover,
            alignment: Alignment.center,
            errorBuilder: (context, error, stackTrace) {
              return Container(color: const Color(0xFF102845));
            },
          ),
        ),
        Positioned.fill(
          child: Container(color: Colors.black.withOpacity(0.16)),
        ),
        Positioned.fill(
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  olympusBlue.withOpacity(0.52),
                  olympusLightBlue.withOpacity(0.24),
                  Colors.black.withOpacity(0.58),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  List<Map<String, dynamic>> _allPhotos() {
    final photos = <Map<String, dynamic>>[];

    for (final event in events) {
      final rawPhotos = event.eventPhotos;
      if (rawPhotos == null) continue;

      for (final item in rawPhotos) {
        if (item is Map) {
          final photo = Map<String, dynamic>.from(item);
          final imageUrl = (photo['image_url'] ?? '').toString().trim();
          if (imageUrl.isEmpty) continue;
          photo['event_name_ref'] = event.name;
          photo['event_date_ref'] = event.dateLabel;
          photos.add(photo);
        }
      }
    }

    photos.sort((a, b) {
      final aDate = DateTime.tryParse((a['created_at'] ?? '').toString()) ??
          DateTime.fromMillisecondsSinceEpoch(0);
      final bDate = DateTime.tryParse((b['created_at'] ?? '').toString()) ??
          DateTime.fromMillisecondsSinceEpoch(0);
      return bDate.compareTo(aDate);
    });

    return photos;
  }

  void _viewPhoto(BuildContext context, String imageUrl) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black.withOpacity(0.8),
            foregroundColor: Colors.white,
          ),
          body: Center(
            child: InteractiveViewer(
              child: Image(
                image: CachedNetworkImageProvider(imageUrl),
                fit: BoxFit.contain,
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final photos = _allPhotos();

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: olympusBlue.withOpacity(0.96),
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Fotos do Torneio',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: Stack(
        children: [
          Positioned.fill(child: _buildPremiumBackground()),
          photos.isEmpty
              ? const _EmptyState(
                  icon: Icons.photo_library_outlined,
                  title: 'Nenhuma foto encontrada',
                  subtitle:
                      'Ainda não existem fotos carregadas nos jogos deste torneio.',
                )
              : GridView.builder(
                  padding: const EdgeInsets.all(12),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                  ),
                  itemCount: photos.length,
                  itemBuilder: (context, index) {
                    final photo = photos[index];
                    final imageUrl = (photo['image_url'] ?? '').toString();

                    return GestureDetector(
                      onTap: () => _viewPhoto(context, imageUrl),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            Image(
                              image: CachedNetworkImageProvider(imageUrl),
                              fit: BoxFit.cover,
                              loadingBuilder: (context, child, progress) {
                                if (progress == null) return child;
                                return Container(
                                  color: Colors.white.withOpacity(0.10),
                                  child: const Center(
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                    ),
                                  ),
                                );
                              },
                              errorBuilder: (context, error, stackTrace) {
                                return Container(
                                  color: Colors.white.withOpacity(0.10),
                                  child: const Center(
                                    child: Icon(
                                      Icons.broken_image_outlined,
                                      color: Colors.white,
                                      size: 32,
                                    ),
                                  ),
                                );
                              },
                            ),
                            Positioned(
                              left: 8,
                              right: 8,
                              bottom: 8,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.black.withOpacity(0.52),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      (photo['event_name_ref'] ?? '')
                                          .toString(),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 11,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      (photo['event_date_ref'] ?? '')
                                          .toString(),
                                      style: const TextStyle(
                                        color: Colors.white70,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 10,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ],
      ),
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
    final isCompact = MediaQuery.of(context).size.width < 380;

    return Container(
      margin: EdgeInsets.only(bottom: isCompact ? 12 : 14),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            padding: EdgeInsets.all(isCompact ? 12 : 14),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.white.withOpacity(0.12),
                  Colors.white.withOpacity(0.06),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white.withOpacity(0.18)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.12),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: _AdminCompetitionsPageState.olympusBlue,
                    fontSize: isCompact ? 17 : 19,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    subtitle!,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.75),
                      fontSize: isCompact ? 11.5 : 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                ...children,
              ],
            ),
          ),
        ),
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
    final isCompact = MediaQuery.of(context).size.width < 380;

    return Container(
      padding: EdgeInsets.all(isCompact ? 10 : 12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE0D4F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: _AdminCompetitionsPageState.olympusBlue,
              fontSize: isCompact ? 14 : 15,
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
  final VoidCallback? onTapPhotos;
  final VoidCallback? onTapPoints;
  final VoidCallback? onTapFeatured;

  const _CompetitionMatchCard({
    super.key,
    required this.event,
    required this.headerTitle,
    required this.canEdit,
    required this.onTapEdit,
    this.onTapPhotos,
    this.onTapPoints,
    this.onTapFeatured,
  });

  @override
  State<_CompetitionMatchCard> createState() => _CompetitionMatchCardState();
}

class _CompetitionMatchCardState extends State<_CompetitionMatchCard> {
  bool _expanded = false;

  void _viewFeaturedImage(String? imageUrl) {
    if (imageUrl == null || imageUrl.isEmpty) return;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black.withOpacity(0.8),
            foregroundColor: Colors.white,
            title: const Text('Imagem de Destaque'),
            actions: [
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          body: Center(
            child: InteractiveViewer(
              child: Image(
                image: CachedNetworkImageProvider(imageUrl),
                fit: BoxFit.contain,
                loadingBuilder: (context, child, progress) {
                  if (progress == null) return child;
                  return const Center(
                    child: CircularProgressIndicator(
                      color: _AdminCompetitionsPageState.olympusGold,
                    ),
                  );
                },
                errorBuilder: (context, error, stackTrace) {
                  return const Icon(
                    Icons.error_outline,
                    color: Colors.white,
                    size: 48,
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final event = widget.event;
    final result = event.result;
    final hasResult = result != null;
    final isVictory = result?.outcome == _ResultOutcome.victory;
    final hasPhotos =
        event.eventPhotos != null && event.eventPhotos!.isNotEmpty;
    final previewImageUrl = event.firstPhotoUrl;
    final hasPreviewImage =
        previewImageUrl != null && previewImageUrl.isNotEmpty;
    final isFeatured = event.isFeatured == true;
    final isCompact = MediaQuery.of(context).size.width < 380;

    return Container(
      padding: EdgeInsets.all(isCompact ? 12 : 14),
      decoration: BoxDecoration(
        color: const Color(0xFFF6EFFB),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE1D4EF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (hasPreviewImage) ...[
            _EventCardPhotoPreview(imageUrl: previewImageUrl),
            const SizedBox(height: 12),
          ],
          if (isFeatured || hasPhotos || (event.result?.points ?? 0) > 0)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (isFeatured)
                  GestureDetector(
                    onTap: () => _viewFeaturedImage(event.featuredImageUrl),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: _AdminCompetitionsPageState.olympusGold,
                        borderRadius: BorderRadius.circular(8),
                        boxShadow: [
                          BoxShadow(
                            color: _AdminCompetitionsPageState.olympusGold
                                .withOpacity(0.4),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.star, size: 16, color: Colors.white),
                          SizedBox(width: 4),
                          Text(
                            'DESTAQUE',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (hasPhotos)
                  GestureDetector(
                    onTap: widget.onTapPhotos,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: _AdminCompetitionsPageState.olympusBlue,
                        borderRadius: BorderRadius.circular(8),
                        boxShadow: [
                          BoxShadow(
                            color: _AdminCompetitionsPageState.olympusBlue
                                .withOpacity(0.4),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.photo_library,
                            size: 16,
                            color: Colors.white,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${event.eventPhotos!.length} FOTO${event.eventPhotos!.length > 1 ? 'S' : ''}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                if ((event.result?.points ?? 0) > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: _AdminCompetitionsPageState.olympusGold,
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: [
                        BoxShadow(
                          color: _AdminCompetitionsPageState.olympusGold
                              .withOpacity(0.35),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.stacked_line_chart_rounded,
                          size: 16,
                          color: Colors.white,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${event.result!.points} PONTO${event.result!.points == 1 ? '' : 'S'}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          if (isFeatured || hasPhotos || (event.result?.points ?? 0) > 0)
            const SizedBox(height: 10),
          Text(
            widget.headerTitle,
            style: TextStyle(
              color: Colors.deepOrange,
              fontWeight: FontWeight.w800,
              fontSize: isCompact ? 16 : 18,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Data: ${event.dateLabel} / Hora: ${event.time}',
            style: TextStyle(
              color: Colors.grey[800],
              fontSize: isCompact ? 13 : 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            event.name,
            style: TextStyle(
              color: _AdminCompetitionsPageState.olympusBlue,
              fontSize: isCompact ? 15.5 : 17,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Endereço: ${event.addressLabel}',
            style: TextStyle(
              color: Colors.grey[700],
              fontSize: isCompact ? 12 : 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 10),
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: isCompact ? 12 : 14,
              vertical: 10,
            ),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF8E8),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _AdminCompetitionsPageState.olympusGold.withOpacity(0.7),
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.stacked_line_chart_rounded,
                  color: _AdminCompetitionsPageState.olympusGold,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Pontuação do jogo: ${event.result?.points ?? 0}',
                    style: TextStyle(
                      color: Colors.brown[800],
                      fontSize: isCompact ? 13 : 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          GestureDetector(
            onTap: hasResult
                ? () => setState(() => _expanded = !_expanded)
                : (widget.canEdit ? widget.onTapEdit : null),
            child: Container(
              padding: EdgeInsets.symmetric(
                horizontal: isCompact ? 12 : 14,
                vertical: isCompact ? 10 : 12,
              ),
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
              child: isCompact
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              hasResult
                                  ? _resultIcon(result!)
                                  : Icons.edit_note_rounded,
                              color: hasResult
                                  ? _resultForeground(result!)
                                  : const Color(0xFF8C6B10),
                              size: 20,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                hasResult
                                    ? result!.displayFinalLabel
                                    : (widget.canEdit
                                        ? 'Cadastrar resultado do jogo'
                                        : 'Resultado pendente'),
                                style: TextStyle(
                                  color: hasResult
                                      ? _resultForeground(result!)
                                      : const Color(0xFF8C6B10),
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
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
                        if (hasResult) ...[
                          const SizedBox(height: 8),
                          Text(
                            '${result!.olympusSets} x ${result.opponentSets} em Sets',
                            style: TextStyle(
                              color: _resultForeground(result),
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ],
                    )
                  : Row(
                      children: [
                        Icon(
                          hasResult
                              ? _resultIcon(result!)
                              : Icons.edit_note_rounded,
                          color: hasResult
                              ? _resultForeground(result!)
                              : const Color(0xFF8C6B10),
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            hasResult
                                ? result!.displayFinalLabel
                                : (widget.canEdit
                                    ? 'Cadastrar resultado do jogo'
                                    : 'Resultado pendente'),
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
                              : '',
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
                padding: EdgeInsets.symmetric(
                  horizontal: isCompact ? 10 : 12,
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
                          fontSize: isCompact ? 12.5 : 14,
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
                          fontSize: isCompact ? 14 : 16,
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
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 4,
              children: [
                if (isVictory && widget.onTapFeatured != null)
                  TextButton.icon(
                    onPressed: widget.onTapFeatured,
                    icon: Icon(
                      event.isFeatured == true ? Icons.star : Icons.star_border,
                      size: 18,
                    ),
                    label: Text(
                      event.isFeatured == true ? 'Destaque' : 'Destacar',
                    ),
                    style: TextButton.styleFrom(
                      foregroundColor: _AdminCompetitionsPageState.olympusGold,
                    ),
                  ),
                TextButton.icon(
                  onPressed: widget.onTapPhotos,
                  icon: const Icon(Icons.photo_library_outlined, size: 18),
                  label: const Text('Fotos'),
                  style: TextButton.styleFrom(
                    foregroundColor: _AdminCompetitionsPageState.olympusBlue,
                  ),
                ),
                if (widget.onTapPoints != null)
                  TextButton.icon(
                    onPressed: widget.onTapPoints,
                    icon: const Icon(
                      Icons.stacked_line_chart_rounded,
                      size: 18,
                    ),
                    label: const Text('Pontos'),
                    style: TextButton.styleFrom(
                      foregroundColor: _AdminCompetitionsPageState.olympusGold,
                    ),
                  ),
                TextButton.icon(
                  onPressed: widget.onTapEdit,
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: const Text('Editar'),
                  style: TextButton.styleFrom(
                    foregroundColor: _AdminCompetitionsPageState.olympusBlue,
                  ),
                ),
              ],
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

class _EventCardPhotoPreview extends StatelessWidget {
  final String imageUrl;

  const _EventCardPhotoPreview({required this.imageUrl});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image(
              image: CachedNetworkImageProvider(imageUrl),
              fit: BoxFit.cover,
              loadingBuilder: (context, child, progress) {
                if (progress == null) return child;
                return Container(
                  color: const Color(0xFFEDE7F3),
                  child: const Center(
                    child: CircularProgressIndicator(
                      color: _AdminCompetitionsPageState.olympusBlue,
                    ),
                  ),
                );
              },
              errorBuilder: (context, error, stackTrace) {
                return Container(
                  color: const Color(0xFFEDE7F3),
                  alignment: Alignment.center,
                  child: const Icon(
                    Icons.image_not_supported_outlined,
                    color: _AdminCompetitionsPageState.olympusBlue,
                    size: 34,
                  ),
                );
              },
            ),
            Positioned(
              left: 10,
              top: 10,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.48),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.photo_library_outlined,
                      size: 14,
                      color: Colors.white,
                    ),
                    SizedBox(width: 5),
                    Text(
                      'Foto do jogo',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
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
    final isCompact = MediaQuery.of(context).size.width < 380;
    final bg = highlighted
        ? (winnerUsesGold ? const Color(0xFFF7C977) : const Color(0xFFA8C0B1))
        : Colors.white;
    final fg = highlighted ? const Color(0xFF1E3A5F) : const Color(0xFF6B6B6B);
    return Container(
      width: isCompact ? 38 : 42,
      height: isCompact ? 32 : 34,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        '$score',
        style: TextStyle(
          color: fg,
          fontWeight: FontWeight.w800,
          fontSize: isCompact ? 19 : 22,
        ),
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
        Icon(icon, size: 64, color: Colors.white70),
        const SizedBox(height: 14),
        Center(
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Text(
            subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withOpacity(0.82),
              fontSize: 14,
            ),
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
        const Icon(
          Icons.error_outline_rounded,
          size: 62,
          color: Colors.white70,
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withOpacity(0.90),
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

class ChampionshipGamesPage extends StatefulWidget {
  final String championshipName;
  final List<_EventCompetitionCard> events;
  final bool canEdit;
  final String? imageUrl;

  const ChampionshipGamesPage({
    super.key,
    required this.championshipName,
    required this.events,
    required this.canEdit,
    this.imageUrl,
  });

  @override
  State<ChampionshipGamesPage> createState() => _ChampionshipGamesPageState();
}

class _ChampionshipGamesPageState extends State<ChampionshipGamesPage> {
  final SupabaseClient _supabase = Supabase.instance.client;
  static const Color olympusBlue = Color(0xFF1E3A5F);
  static const Color olympusLightBlue = Color(0xFF2C5F8D);
  static const Color olympusGold = Color(0xFFD4AF37);

  late List<_EventCompetitionCard> _events;

  @override
  void initState() {
    super.initState();
    _events = [...widget.events];
  }

  Future<void> _refreshSingleEvent(String eventId) async {
    final response = await _supabase.from('events').select('''
      id,
      event_name,
      event_type,
      event_date,
      event_time,
      set_format,
      championship_name,
      championship_image_url,
      is_featured,
      featured_image_url,
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
      ),
      event_photos (
        id,
        image_url,
        created_at
      )
    ''').eq('id', eventId).single();

    final refreshed = _EventCompetitionCard.fromMap(
      Map<String, dynamic>.from(response),
    );

    if (!mounted) return;

    setState(() {
      final index = _events.indexWhere((item) => item.id == eventId);
      if (index != -1) {
        _events[index] = refreshed;
      }
    });
  }

  Widget _buildPremiumBackground() {
    return Stack(
      children: [
        Positioned.fill(
          child: OlympusBrandBackgroundImage(
            fit: BoxFit.cover,
            alignment: Alignment.center,
            errorBuilder: (context, error, stackTrace) {
              return Container(color: const Color(0xFF102845));
            },
          ),
        ),
        Positioned.fill(
          child: Container(color: Colors.black.withOpacity(0.16)),
        ),
        Positioned.fill(
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  olympusBlue.withOpacity(0.52),
                  olympusLightBlue.withOpacity(0.24),
                  Colors.black.withOpacity(0.58),
                ],
              ),
            ),
          ),
        ),
        Positioned.fill(
          child: Container(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(0, -0.80),
                radius: 1.08,
                colors: [
                  olympusGold.withOpacity(0.10),
                  Colors.transparent,
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _openResultEditor(_EventCompetitionCard event) async {
    final changed = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AdminCompetitionResultPage(event: event),
      ),
    );
    if (changed == true && mounted) {
      Navigator.of(context).pop(true);
    }
  }

  Future<void> _openEventPhotos(_EventCompetitionCard event) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => EventPhotosPage(
          eventId: event.id,
          eventName: event.name,
          canEdit: widget.canEdit,
        ),
      ),
    );
  }

  Future<void> _openFeaturedMatch(_EventCompetitionCard event) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FeaturedMatchPage(
          eventId: event.id,
          eventName: event.name,
          isFeatured: event.isFeatured ?? false,
          featuredImageUrl: event.featuredImageUrl,
          canEdit: widget.canEdit,
        ),
      ),
    );
  }

  String _extractDisplayLabel(String rawLabel) {
    final clean = rawLabel.trim();
    if (clean.isEmpty) return 'RESULTADO';
    final index = clean.indexOf('||');
    if (index == -1) return clean;
    return clean.substring(0, index).trim();
  }

  Map<String, String> _parseResultMetadata(String rawLabel) {
    final meta = <String, String>{};
    final index = rawLabel.indexOf('||');
    if (index == -1) return meta;

    final rawMeta = rawLabel.substring(index + 2);
    for (final part in rawMeta.split('|')) {
      final item = part.trim();
      if (item.isEmpty || !item.contains('=')) continue;
      final eq = item.indexOf('=');
      meta[item.substring(0, eq).trim()] = item.substring(eq + 1).trim();
    }
    return meta;
  }

  String _composeResultLabel(
    String displayLabel,
    Map<String, String> metadata,
  ) {
    final filtered = Map<String, String>.from(metadata)
      ..removeWhere((key, value) => value.trim().isEmpty);
    if (filtered.isEmpty) return displayLabel.trim();
    return '${displayLabel.trim()}||${filtered.entries.map((e) => '${e.key}=${e.value}').join('|')}';
  }

  Future<void> _openPointsEditor(_EventCompetitionCard event) async {
    final controller = TextEditingController(
      text: event.result != null && event.result!.points > 0
          ? '${event.result!.points}'
          : '',
    );

    final shouldSave = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              color: Color(0xFFF6F1FA),
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 42,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Pontuação do jogo',
                    style: TextStyle(
                      color: olympusBlue,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    event.name,
                    style: TextStyle(
                      color: Colors.grey[700],
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: controller,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Pontos conquistados',
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => Navigator.of(context).pop(true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: olympusGold,
                        foregroundColor: olympusBlue,
                      ),
                      child: const Text(
                        'Salvar pontuação',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    if (shouldSave != true) return;

    try {
      final existingResult = event.result;
      final displayLabel = _extractDisplayLabel(
        existingResult?.finalLabel ?? 'RESULTADO',
      );
      final metadata = _parseResultMetadata(existingResult?.finalLabel ?? '')
        ..['PTS'] = controller.text.trim();

      await _supabase.from('event_results').upsert({
        'event_id': event.id,
        'final_result_label': _composeResultLabel(displayLabel, metadata),
        'olympus_sets_won': existingResult?.olympusSets ?? 0,
        'opponent_sets_won': existingResult?.opponentSets ?? 0,
      }, onConflict: 'event_id');

      await _refreshSingleEvent(event.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Pontuação salva com sucesso!'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Erro ao salvar pontuação: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isCompact = MediaQuery.of(context).size.width < 380;

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(
          widget.championshipName,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: Stack(
        children: [
          Positioned.fill(child: _buildPremiumBackground()),
          SafeArea(
            child: ListView.builder(
              padding: EdgeInsets.fromLTRB(
                isCompact ? 12 : 16,
                12,
                isCompact ? 12 : 16,
                20,
              ),
              itemCount: _events.length,
              itemBuilder: (context, index) {
                final event = _events[index];
                final isVictory =
                    event.result?.outcome == _ResultOutcome.victory;

                return Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Colors.white.withOpacity(0.16),
                              Colors.white.withOpacity(0.08),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.18),
                            width: 1.0,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.14),
                              blurRadius: 14,
                              offset: const Offset(0, 5),
                            ),
                          ],
                        ),
                        child: _CompetitionMatchCard(
                          key: ValueKey(
                            '${event.id}_${event.result?.finalLabel ?? 'sem_resultado'}_${event.result?.points ?? 0}',
                          ),
                          event: event,
                          headerTitle: widget.championshipName,
                          canEdit: widget.canEdit,
                          onTapEdit: () => _openResultEditor(event),
                          onTapPhotos: () => _openEventPhotos(event),
                          onTapPoints: widget.canEdit
                              ? () => _openPointsEditor(event)
                              : null,
                          onTapFeatured: widget.canEdit && isVictory
                              ? () => _openFeaturedMatch(event)
                              : null,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// Página de Gerenciamento de Destaque
class FeaturedMatchPage extends StatefulWidget {
  final String eventId;
  final String eventName;
  final bool isFeatured;
  final String? featuredImageUrl;
  final bool canEdit;

  const FeaturedMatchPage({
    super.key,
    required this.eventId,
    required this.eventName,
    required this.isFeatured,
    this.featuredImageUrl,
    required this.canEdit,
  });

  @override
  State<FeaturedMatchPage> createState() => _FeaturedMatchPageState();
}

class _FeaturedMatchPageState extends State<FeaturedMatchPage> {
  final SupabaseClient _supabase = Supabase.instance.client;
  static const Color olympusBlue = Color(0xFF1E3A5F);
  static const Color olympusGold = Color(0xFFD4AF37);
  bool _saving = false;
  late bool _isFeatured;
  String? _imageUrl;

  @override
  void initState() {
    super.initState();
    _isFeatured = widget.isFeatured;
    _imageUrl = widget.featuredImageUrl;
  }

  Future<void> _uploadFeaturedImage() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);
    if (image == null) return;

    try {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('📤 Enviando imagem de destaque...'),
            backgroundColor: Colors.blue,
          ),
        );
      }

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = OrganizationStorageService.scopedPath(
        'featured/${widget.eventId}_$timestamp.jpg',
      );

      if (kIsWeb) {
        final bytes = await image.readAsBytes();
        await _supabase.storage.from('event-images').uploadBinary(
              fileName,
              bytes,
              fileOptions: const FileOptions(upsert: true),
            );
      } else {
        final file = File(image.path);
        await _supabase.storage.from('event-images').upload(
              fileName,
              file,
              fileOptions: const FileOptions(upsert: true),
            );
      }

      final imageUrl =
          _supabase.storage.from('event-images').getPublicUrl(fileName);

      setState(() {
        _imageUrl = imageUrl;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Imagem de destaque enviada!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Erro ao enviar imagem: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await _supabase.from('events').update({
        'is_featured': _isFeatured,
        'featured_image_url': _isFeatured ? _imageUrl : null,
      }).eq('id', widget.eventId);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Destaque salvo com sucesso!'),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Erro ao salvar: $e'),
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
    return Scaffold(
      backgroundColor: const Color(0xFFF6F1FA),
      appBar: AppBar(
        backgroundColor: olympusBlue,
        foregroundColor: Colors.white,
        title: const Text(
          'Destacar Partida',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE1D4EF)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Configurar Destaque',
                  style: TextStyle(
                    color: olympusBlue,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  widget.eventName,
                  style: TextStyle(color: Colors.grey[700], fontSize: 14),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE1D4EF)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.star, color: olympusGold, size: 24),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Habilitar Destaque',
                            style: TextStyle(
                              color: olympusBlue,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            'Exibir esta partida em destaque para os usuários',
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: _isFeatured,
                      onChanged: (value) {
                        setState(() {
                          _isFeatured = value;
                        });
                      },
                      activeColor: olympusGold,
                    ),
                  ],
                ),
                if (_isFeatured) ...[
                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 16),
                  const Text(
                    'Imagem de Destaque',
                    style: TextStyle(
                      color: olympusBlue,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  GestureDetector(
                    onTap: _uploadFeaturedImage,
                    child: Container(
                      height: 200,
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: olympusGold,
                          width: 2,
                          style: BorderStyle.solid,
                        ),
                        image: _imageUrl != null && _imageUrl!.isNotEmpty
                            ? DecorationImage(
                                image: CachedNetworkImageProvider(_imageUrl!),
                                fit: BoxFit.cover,
                              )
                            : null,
                      ),
                      child: _imageUrl == null || _imageUrl!.isEmpty
                          ? Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.add_photo_alternate_outlined,
                                  size: 48,
                                  color: olympusGold,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Toque para adicionar foto',
                                  style: TextStyle(
                                    color: olympusGold,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            )
                          : null,
                    ),
                  ),
                  if (_imageUrl != null && _imageUrl!.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: () {
                          setState(() {
                            _imageUrl = null;
                          });
                        },
                        icon: const Icon(Icons.delete_outline, size: 18),
                        label: const Text('Remover foto'),
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.red,
                        ),
                      ),
                    ),
                  ],
                ],
              ],
            ),
          ),
          const SizedBox(height: 24),
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
                      'Salvar Destaque',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

// Página de Fotos do Jogo - ADMIN e USUÁRIO
class EventPhotosPage extends StatefulWidget {
  final String eventId;
  final String eventName;
  final bool canEdit;

  const EventPhotosPage({
    super.key,
    required this.eventId,
    required this.eventName,
    required this.canEdit,
  });

  @override
  State<EventPhotosPage> createState() => _EventPhotosPageState();
}

class _EventPhotosPageState extends State<EventPhotosPage> {
  final SupabaseClient _supabase = Supabase.instance.client;
  static const Color olympusBlue = Color(0xFF1E3A5F);
  static const Color olympusGold = Color(0xFFD4AF37);
  bool _loading = true;
  List<Map<String, dynamic>> _photos = [];

  @override
  void initState() {
    super.initState();
    _loadPhotos();
  }

  Future<void> _loadPhotos() async {
    setState(() => _loading = true);
    try {
      final response = await _supabase
          .from('event_photos')
          .select()
          .eq('event_id', widget.eventId)
          .order('created_at', ascending: true);

      if (mounted) {
        final loadedPhotos = List<Map<String, dynamic>>.from(response);
        loadedPhotos.sort((a, b) {
          final aDate = DateTime.tryParse((a['created_at'] ?? '').toString()) ??
              DateTime.fromMillisecondsSinceEpoch(0);
          final bDate = DateTime.tryParse((b['created_at'] ?? '').toString()) ??
              DateTime.fromMillisecondsSinceEpoch(0);
          return bDate.compareTo(aDate);
        });

        setState(() {
          _photos = loadedPhotos;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao carregar fotos: $e'),
            backgroundColor: Colors.red,
          ),
        );
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _uploadPhoto() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);
    if (image == null) return;

    try {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('📤 Enviando foto...'),
            backgroundColor: Colors.blue,
          ),
        );
      }

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = OrganizationStorageService.scopedPath(
        'events/${widget.eventId}/$timestamp.jpg',
      );

      if (kIsWeb) {
        final bytes = await image.readAsBytes();
        await _supabase.storage.from('event-images').uploadBinary(
              fileName,
              bytes,
              fileOptions: const FileOptions(upsert: true),
            );
      } else {
        final file = File(image.path);
        await _supabase.storage.from('event-images').upload(
              fileName,
              file,
              fileOptions: const FileOptions(upsert: true),
            );
      }

      final imageUrl =
          _supabase.storage.from('event-images').getPublicUrl(fileName);

      await _supabase.from('event_photos').insert({
        'event_id': widget.eventId,
        'image_url': imageUrl,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Foto enviada com sucesso!'),
            backgroundColor: Colors.green,
          ),
        );
        await _loadPhotos();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Erro ao enviar foto: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _deletePhoto(String photoId, String imageUrl) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Excluir foto?'),
        content: const Text('Esta ação não pode ser desfeita.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final uri = Uri.parse(imageUrl);
      final pathSegments = uri.pathSegments;
      final filePath =
          pathSegments.skipWhile((s) => s != 'event-images').skip(1).join('/');

      await _supabase.storage.from('event-images').remove([filePath]);
      await _supabase.from('event_photos').delete().eq('id', photoId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Foto excluída com sucesso!'),
            backgroundColor: Colors.green,
          ),
        );
        await _loadPhotos();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Erro ao excluir foto: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F1FA),
      appBar: AppBar(
        backgroundColor: olympusBlue,
        foregroundColor: Colors.white,
        title: const Text(
          'Fotos do Jogo',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: widget.canEdit
            ? [
                IconButton(
                  onPressed: _uploadPhoto,
                  icon: const Icon(Icons.add_a_photo),
                ),
              ]
            : null,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _photos.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.photo_library_outlined,
                        size: 80,
                        color: Colors.grey[400],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        widget.canEdit
                            ? 'Nenhuma foto ainda\nToque no + para adicionar'
                            : 'Nenhuma foto disponível',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey[600], fontSize: 16),
                      ),
                    ],
                  ),
                )
              : GridView.builder(
                  padding: const EdgeInsets.all(8),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                  ),
                  itemCount: _photos.length,
                  itemBuilder: (context, index) {
                    final photo = _photos[index];
                    return Stack(
                      fit: StackFit.expand,
                      children: [
                        GestureDetector(
                          onTap: () => _viewPhoto(photo['image_url']),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image(
                              image: CachedNetworkImageProvider(
                                photo['image_url'].toString(),
                              ),
                              fit: BoxFit.cover,
                              loadingBuilder: (context, child, progress) {
                                if (progress == null) return child;
                                return Container(
                                  color: Colors.grey[300],
                                  child: const Center(
                                    child: CircularProgressIndicator(),
                                  ),
                                );
                              },
                              errorBuilder: (context, error, stackTrace) {
                                return Container(
                                  color: Colors.grey[300],
                                  child: const Icon(Icons.error),
                                );
                              },
                            ),
                          ),
                        ),
                        if (widget.canEdit)
                          Positioned(
                            top: 8,
                            right: 8,
                            child: GestureDetector(
                              onTap: () =>
                                  _deletePhoto(photo['id'], photo['image_url']),
                              child: Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: Colors.red.withOpacity(0.8),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(
                                  Icons.delete_outline,
                                  color: Colors.white,
                                  size: 20,
                                ),
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                ),
    );
  }

  void _viewPhoto(String imageUrl) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black.withOpacity(0.8),
            foregroundColor: Colors.white,
            actions: [
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          body: Center(
            child: InteractiveViewer(
              child: Image(
                image: CachedNetworkImageProvider(imageUrl),
                fit: BoxFit.contain,
              ),
            ),
          ),
        ),
      ),
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
  late final int _totalSets;
  late final int _setsNeededToWin;
  String _achievementType = 'none';

  @override
  void initState() {
    super.initState();
    final setFormat = widget.event.setFormat ?? 'Melhor de 5';
    if (setFormat.contains('3')) {
      _totalSets = 3;
      _setsNeededToWin = 2;
    } else if (setFormat.contains('5')) {
      _totalSets = 5;
      _setsNeededToWin = 3;
    } else {
      _totalSets = 5;
      _setsNeededToWin = 3;
    }

    final result = widget.event.result;
    _finalLabelController = TextEditingController(
      text: result?.displayFinalLabel ?? 'VITÓRIA',
    );
    _olympusSetsController = TextEditingController(
      text: '${result?.olympusSets ?? 0}',
    );
    _opponentSetsController = TextEditingController(
      text: '${result?.opponentSets ?? 0}',
    );
    _achievementType = _parseAchievementType(result?.displayFinalLabel ?? '');

    final existingSets = result?.sets ?? [];
    _sets = List.generate(_totalSets, (index) {
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

    _calculateSetsWon();
    for (var set in _sets) {
      set.olympusController.addListener(_calculateSetsWon);
      set.opponentController.addListener(_calculateSetsWon);
    }
  }

  void _calculateSetsWon() {
    int olympusWins = 0;
    int opponentWins = 0;

    for (var set in _sets) {
      final olympusScore = int.tryParse(set.olympusController.text.trim()) ?? 0;
      final opponentScore =
          int.tryParse(set.opponentController.text.trim()) ?? 0;
      if (olympusScore > opponentScore && olympusScore > 0) {
        olympusWins++;
      } else if (opponentScore > olympusScore && opponentScore > 0) {
        opponentWins++;
      }
    }

    _olympusSetsController.removeListener(_calculateSetsWon);
    _opponentSetsController.removeListener(_calculateSetsWon);
    _olympusSetsController.text = olympusWins.toString();
    _opponentSetsController.text = opponentWins.toString();

    String finalResult;
    if (olympusWins > opponentWins) {
      finalResult = 'VITÓRIA';
    } else if (opponentWins > olympusWins) {
      finalResult = 'DERROTA';
    } else {
      finalResult = 'EMPATE';
    }
    if (_finalLabelController.text != finalResult) {
      _finalLabelController.text = finalResult;
    }

    _olympusSetsController.addListener(_calculateSetsWon);
    _opponentSetsController.addListener(_calculateSetsWon);
  }

  String _parseAchievementType(String label) {
    final value = label.toLowerCase();
    if (value.contains('campe')) return 'champion';
    if (value.contains('vice')) return 'runner_up';
    if (value.contains('3º') ||
        value.contains('3o') ||
        value.contains('terceiro')) {
      return 'third';
    }
    return 'none';
  }

  String _buildFinalResultLabel(String baseResult, String achievementType) {
    switch (achievementType) {
      case 'champion':
        return 'CAMPEÃO';
      case 'runner_up':
        return 'VICE-CAMPEÃO';
      case 'third':
        return '3º LUGAR';
      default:
        return baseResult;
    }
  }

  Map<String, String> _parseResultMetadata(String rawLabel) {
    final meta = <String, String>{};
    final index = rawLabel.indexOf('||');
    if (index == -1) return meta;

    final rawMeta = rawLabel.substring(index + 2);
    for (final part in rawMeta.split('|')) {
      final item = part.trim();
      if (item.isEmpty || !item.contains('=')) continue;
      final eq = item.indexOf('=');
      meta[item.substring(0, eq).trim()] = item.substring(eq + 1).trim();
    }
    return meta;
  }

  String _composeResultLabel(
    String displayLabel,
    Map<String, String> metadata,
  ) {
    final filtered = Map<String, String>.from(metadata)
      ..removeWhere((key, value) => value.trim().isEmpty);
    if (filtered.isEmpty) return displayLabel.trim();
    return '${displayLabel.trim()}||${filtered.entries.map((e) => '${e.key}=${e.value}').join('|')}';
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
      int setsPlayed = 0;
      int olympusWins = 0;
      int opponentWins = 0;

      for (var set in _sets) {
        final olympusScore =
            int.tryParse(set.olympusController.text.trim()) ?? 0;
        final opponentScore =
            int.tryParse(set.opponentController.text.trim()) ?? 0;
        if (olympusScore > 0 || opponentScore > 0) {
          setsPlayed++;
          if (olympusScore > opponentScore) {
            olympusWins++;
          } else if (opponentScore > olympusScore) {
            opponentWins++;
          }
        }
      }

      String finalResult = resultLabel;
      if (resultLabel.trim().isEmpty) {
        if (olympusWins > opponentWins) {
          finalResult = 'VITÓRIA';
        } else if (opponentWins > olympusWins) {
          finalResult = 'DERROTA';
        } else {
          finalResult = 'EMPATE';
        }
      }

      finalResult = _buildFinalResultLabel(finalResult, _achievementType);
      final existingMeta = _parseResultMetadata(
        widget.event.result?.finalLabel ?? '',
      );

      final resultResponse = await _supabase
          .from('event_results')
          .upsert({
            'event_id': widget.event.id,
            'final_result_label': _composeResultLabel(
              finalResult,
              existingMeta,
            ),
            'olympus_sets_won': olympusWins,
            'opponent_sets_won': opponentWins,
          }, onConflict: 'event_id')
          .select()
          .single();

      final resultId = resultResponse['id'].toString();

      await _supabase
          .from('event_result_sets')
          .delete()
          .eq('event_result_id', resultId);

      final setsPayload = <Map<String, dynamic>>[];
      for (int i = 0; i < setsPlayed && i < _sets.length; i++) {
        final row = _sets[i];
        final olympusScore =
            int.tryParse(row.olympusController.text.trim()) ?? 0;
        final opponentScore =
            int.tryParse(row.opponentController.text.trim()) ?? 0;
        setsPayload.add({
          'event_result_id': resultId,
          'set_number': row.setNumber,
          'olympus_score': olympusScore,
          'opponent_score': opponentScore,
        });
      }

      if (setsPayload.isNotEmpty) {
        await _supabase.from('event_result_sets').insert(setsPayload);
      }

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

    int setsToShow = _totalSets;
    int olympusWins = 0;
    int opponentWins = 0;

    for (int i = 0; i < _sets.length; i++) {
      final olympusScore =
          int.tryParse(_sets[i].olympusController.text.trim()) ?? 0;
      final opponentScore =
          int.tryParse(_sets[i].opponentController.text.trim()) ?? 0;

      if (olympusScore > 0 || opponentScore > 0) {
        if (olympusScore > opponentScore) {
          olympusWins++;
        } else if (opponentScore > olympusScore) {
          opponentWins++;
        }
      }

      if (olympusWins >= _setsNeededToWin || opponentWins >= _setsNeededToWin) {
        setsToShow = i + 1;
        break;
      }

      if (i == _sets.length - 1 && (olympusScore > 0 || opponentScore > 0)) {
        setsToShow = i + 1;
      }
    }

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
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: olympusGold.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: olympusGold.withOpacity(0.5)),
                  ),
                  child: Text(
                    'Formato: Melhor de $_totalSets sets',
                    style: TextStyle(
                      color: olympusGold,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
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
                  enabled: false,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildField(
                  controller: _opponentSetsController,
                  label: 'Sets adversário',
                  keyboardType: TextInputType.number,
                  enabled: false,
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
          ...List.generate(setsToShow, (index) {
            final row = _sets[index];
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
    bool enabled = true,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      enabled: enabled,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        filled: true,
        fillColor: enabled ? Colors.white : Colors.grey[100],
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

class _HallAchievement {
  final String title;
  final String eventName;
  final int year;
  final String dateLabel;
  final String? imageUrl;
  final String resultLabel;

  _HallAchievement({
    required this.title,
    required this.eventName,
    required this.year,
    required this.dateLabel,
    this.imageUrl,
    required this.resultLabel,
  });
}

class _CompetitionGroup {
  final String title;
  final List<_EventCompetitionCard> items;

  _CompetitionGroup({required this.title, required this.items});
}

class _FriendlyGenderGroup {
  final String title;
  final List<_CompetitionGroup> groups;
  final List<_EventCompetitionCard> items;
  final String? imageUrl;

  _FriendlyGenderGroup({
    required this.title,
    required this.groups,
    required this.items,
    this.imageUrl,
  });
}

class _FriendlyYearGroup {
  final int year;
  final List<_FriendlyGenderGroup> groups;

  _FriendlyYearGroup({required this.year, required this.groups});
}

class _EventCompetitionCard {
  final String id;
  final String name;
  final String type;
  final String championshipName;
  final String time;
  final String gender;
  final String addressLabel;
  final DateTime? eventDate;
  final _EventResult? result;
  final String? setFormat;
  final String? championshipImageUrl;
  final bool? isFeatured;
  final String? featuredImageUrl;
  final List<dynamic>? eventPhotos;

  _EventCompetitionCard({
    required this.id,
    required this.name,
    required this.type,
    required this.championshipName,
    required this.time,
    required this.gender,
    required this.addressLabel,
    required this.eventDate,
    required this.result,
    this.setFormat,
    this.championshipImageUrl,
    this.isFeatured,
    this.featuredImageUrl,
    this.eventPhotos,
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
      gender: (map['gender'] ?? '').toString().trim(),
      addressLabel: address,
      eventDate: _parseDate((map['event_date'] ?? '').toString()),
      result: resultMap == null ? null : _EventResult.fromMap(resultMap),
      setFormat: (map['set_format'] ?? 'Melhor de 5').toString(),
      championshipImageUrl: (map['championship_image_url'] ?? '').toString(),
      isFeatured: map['is_featured'] as bool?,
      featuredImageUrl: (map['featured_image_url'] ?? '').toString(),
      eventPhotos: map['event_photos'] as List?,
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

  String? get firstPhotoUrl {
    final photos = eventPhotos;
    if (photos == null || photos.isEmpty) return null;

    final photoMaps = photos
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();

    if (photoMaps.isEmpty) return null;

    photoMaps.sort((a, b) {
      final aDate = DateTime.tryParse((a['created_at'] ?? '').toString()) ??
          DateTime.fromMillisecondsSinceEpoch(0);
      final bDate = DateTime.tryParse((b['created_at'] ?? '').toString()) ??
          DateTime.fromMillisecondsSinceEpoch(0);
      return aDate.compareTo(bDate);
    });

    final imageUrl = (photoMaps.first['image_url'] ?? '').toString().trim();
    return imageUrl.isEmpty ? null : imageUrl;
  }

  String get genderLabel {
    final value = gender.toLowerCase().trim();
    if (value.contains('masc')) return 'Masculino';
    if (value.contains('fem')) return 'Feminino';
    return gender.isEmpty ? 'Sem gênero' : gender;
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

  String get displayFinalLabel {
    final index = finalLabel.indexOf('||');
    if (index == -1) return finalLabel;
    return finalLabel.substring(0, index).trim();
  }

  int get points {
    final marker = 'PTS=';
    final index = finalLabel.indexOf(marker);
    if (index == -1) return 0;
    final rest = finalLabel.substring(index + marker.length);
    final end = rest.indexOf('|');
    final raw = end == -1 ? rest : rest.substring(0, end);
    return int.tryParse(raw.trim()) ?? 0;
  }

  int? get classificationPoints {
    final marker = 'CLASSPTS=';
    final index = finalLabel.indexOf(marker);
    if (index == -1) return null;
    final rest = finalLabel.substring(index + marker.length);
    final end = rest.indexOf('|');
    final raw = end == -1 ? rest : rest.substring(0, end);
    return int.tryParse(raw.trim());
  }

  int? get qualifyingGames {
    final marker = 'CLASSGAMES=';
    final index = finalLabel.indexOf(marker);
    if (index == -1) return null;
    final rest = finalLabel.substring(index + marker.length);
    final end = rest.indexOf('|');
    final raw = end == -1 ? rest : rest.substring(0, end);
    return int.tryParse(raw.trim());
  }

  String? get classificationStage {
    final marker = 'CLASSSTAGE=';
    final index = finalLabel.indexOf(marker);
    if (index == -1) return null;
    final rest = finalLabel.substring(index + marker.length);
    final end = rest.indexOf('|');
    final raw = end == -1 ? rest : rest.substring(0, end);
    final value = raw.trim();
    return value.isEmpty ? null : value;
  }

  _ResultOutcome get outcome {
    final label = displayFinalLabel.toLowerCase();
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
