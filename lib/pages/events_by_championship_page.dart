import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'championships_page.dart';

class EventsByChampionshipPage extends StatefulWidget {
  final String name;

  const EventsByChampionshipPage({
    super.key,
    required this.name,
  });

  @override
  State<EventsByChampionshipPage> createState() =>
      _EventsByChampionshipPageState();
}

class _EventsByChampionshipPageState extends State<EventsByChampionshipPage> {
  static const Color olympusBlue = Color(0xFF1E3A5F);
  static const Color olympusGold = Color(0xFFD4AF37);
  static const Color olympusLightBlue = Color(0xFF2C5F8D);
  static const Color futuristicDark = Color(0xFF0B1420);
  static const Color futuristicCard = Color(0xFF122235);

  Widget _buildOlympusBackground() {
    return IgnorePointer(
      child: Stack(
        children: [
          Positioned.fill(
            child: Opacity(
              opacity: 0.78,
              child: Image.asset(
                'assets/images/monte_olimpo.png',
                fit: BoxFit.cover,
                alignment: Alignment.topCenter,
              ),
            ),
          ),
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 0.8, sigmaY: 0.8),
              child: Container(color: Colors.transparent),
            ),
          ),
          Positioned.fill(
            child: Container(
              color: const Color(0xFF0B1420).withOpacity(0.46),
            ),
          ),
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color.fromRGBO(9, 17, 27, 0.26),
                    Color.fromRGBO(17, 37, 58, 0.14),
                    Color.fromRGBO(30, 58, 95, 0.28),
                  ],
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: CustomPaint(
              painter: _FuturisticBackgroundPainter(),
            ),
          ),
        ],
      ),
    );
  }

  final TextEditingController _searchController = TextEditingController();

  List<Map<String, dynamic>> _allEvents = [];
  List<Map<String, dynamic>> _filteredEvents = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadEvents();
    _searchController.addListener(_applyFilter);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadEvents() async {
    try {
      if (mounted) {
        setState(() => _isLoading = true);
      }

      final supabase = Supabase.instance.client;

      final response = await supabase
          .from('events')
          .select(
            'id, event_name, event_type, event_date, event_time, image_url, game_photo_url, '
            'gender, set_format, city, state, street, street_number, '
            'neighborhood, championship_name, created_at, allow_checkin, score',
          )
          .eq('championship_name', widget.name);

      final events = response.map<Map<String, dynamic>>((item) {
        return Map<String, dynamic>.from(item);
      }).toList();

      final ids = events
          .map((e) => e['id']?.toString())
          .whereType<String>()
          .where((id) => id.isNotEmpty)
          .toList();

      final Map<String, Map<String, int>> convocationStats = {};
      final Map<String, Map<String, int>> quantidadeConvocados = {};
      final Map<String, Map<String, int>> checkinInfo = {};

      if (ids.isNotEmpty) {
        try {
          final statsResp = await supabase
              .from('event_convocation_stats')
              .select(
                'event_id,total_convocados,total_aceitos,total_pendentes,total_recusados',
              )
              .inFilter('event_id', ids);

          for (final row in statsResp) {
            final rowMap = Map<String, dynamic>.from(row);
            final eventId = rowMap['event_id']?.toString();
            if (eventId == null || eventId.isEmpty) continue;

            int asInt(dynamic value) {
              if (value is int) return value;
              return int.tryParse(value?.toString() ?? '0') ?? 0;
            }

            convocationStats[eventId] = {
              'total_convocados': asInt(rowMap['total_convocados']),
              'total_aceitos': asInt(rowMap['total_aceitos']),
              'total_pendentes': asInt(rowMap['total_pendentes']),
              'total_recusados': asInt(rowMap['total_recusados']),
            };
          }
        } catch (_) {}

        for (final event in events) {
          final eventId = event['id']?.toString();
          if (eventId == null || eventId.isEmpty) continue;

          try {
            final convocationsResponse = await supabase
                .from('convocations')
                .select('user_id, profiles(user_type)')
                .eq('event_id', eventId);

            int atletas = 0;
            int tecnicos = 0;

            for (final item in convocationsResponse) {
              final convocation = Map<String, dynamic>.from(item);
              dynamic profile = convocation['profiles'];
              String? userType;

              if (profile is Map<String, dynamic>) {
                userType = profile['user_type']?.toString();
              } else if (profile is List && profile.isNotEmpty) {
                final first = profile.first;
                if (first is Map<String, dynamic>) {
                  userType = first['user_type']?.toString();
                }
              }

              if (userType == 'athlete') {
                atletas++;
              } else if (userType == 'coach') {
                tecnicos++;
              }
            }

            quantidadeConvocados[eventId] = {
              'athletes': atletas,
              'technicians': tecnicos,
            };
          } catch (_) {
            quantidadeConvocados[eventId] = {
              'athletes': 0,
              'technicians': 0,
            };
          }
        }

        for (final event in events) {
          final eventId = event['id']?.toString();
          if (eventId == null || eventId.isEmpty) continue;

          final allowCheckin = event['allow_checkin'] == true;
          if (!allowCheckin) continue;

          try {
            final checkinsResponse = await supabase
                .from('checkins')
                .select('user_id')
                .eq('event_id', eventId);

            final checkedIn = checkinsResponse.length;
            final stats = convocationStats[eventId];
            final totalAceitos = stats?['total_aceitos'] ?? 0;
            final pending = (totalAceitos - checkedIn).clamp(0, 999999);

            checkinInfo[eventId] = {
              'checked_in': checkedIn,
              'pending': pending,
            };
          } catch (_) {}
        }
      }

      for (final event in events) {
        final eventId = event['id']?.toString() ?? '';
        event['convocation_stats'] = convocationStats[eventId] ??
            {
              'total_convocados': 0,
              'total_aceitos': 0,
              'total_pendentes': 0,
              'total_recusados': 0,
            };
        event['quantidade_convocados'] = quantidadeConvocados[eventId] ??
            {
              'athletes': 0,
              'technicians': 0,
            };
        event['checkin_info'] = checkinInfo[eventId];
        event['score_expanded'] = false;
      }

      events.sort((a, b) {
        final bCreated = (b['created_at'] ?? '').toString();
        final aCreated = (a['created_at'] ?? '').toString();
        return bCreated.compareTo(aCreated);
      });

      if (!mounted) return;

      setState(() {
        _allEvents = events;
        _filteredEvents = events;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _allEvents = [];
        _filteredEvents = [];
        _isLoading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao carregar jogos: $e'),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _applyFilter() {
    final query = _searchController.text.trim().toLowerCase();

    setState(() {
      if (query.isEmpty) {
        _filteredEvents = List.from(_allEvents);
      } else {
        _filteredEvents = _allEvents.where((event) {
          final eventName =
              (event['event_name'] ?? '').toString().toLowerCase();
          final eventType =
              (event['event_type'] ?? '').toString().toLowerCase();
          final city = (event['city'] ?? '').toString().toLowerCase();
          final date = (event['event_date'] ?? '').toString().toLowerCase();
          final championship =
              (event['championship_name'] ?? '').toString().toLowerCase();

          return eventName.contains(query) ||
              eventType.contains(query) ||
              city.contains(query) ||
              date.contains(query) ||
              championship.contains(query);
        }).toList();
      }
    });
  }

  String _formatEventType(String type) {
    switch (type) {
      case 'treino':
        return 'TREINO';
      case 'amistoso':
        return 'AMISTOSO';
      case 'campeonato':
        return 'CAMPEONATO';
      default:
        return type.toUpperCase();
    }
  }

  String _formatGender(String gender) {
    switch (gender) {
      case 'masculino':
        return 'Masculino';
      case 'feminino':
        return 'Feminino';
      default:
        return gender;
    }
  }

  String _buildAddress(Map<String, dynamic> event) {
    final street = (event['street'] ?? '').toString();
    final number = (event['street_number'] ?? '').toString();
    final neighborhood = (event['neighborhood'] ?? '').toString();
    final city = (event['city'] ?? '').toString();
    final state = (event['state'] ?? '').toString();

    final parts = <String>[];

    if (street.isNotEmpty) {
      parts.add(number.isNotEmpty ? '$street, $number' : street);
    }
    if (neighborhood.isNotEmpty) parts.add(neighborhood);
    if (city.isNotEmpty && state.isNotEmpty) {
      parts.add('$city - $state');
    } else if (city.isNotEmpty) {
      parts.add(city);
    } else if (state.isNotEmpty) {
      parts.add(state);
    }

    return parts.join(' • ');
  }

  Color _getCorTipoEvento(String tipo) {
    switch (tipo.toLowerCase()) {
      case 'treino':
        return Colors.blue;
      case 'jogo':
      case 'partida':
      case 'amistoso':
        return Colors.green;
      case 'campeonato':
        return Colors.amber.shade700;
      case 'reuniao':
        return Colors.orange;
      default:
        return Colors.purple;
    }
  }

  void _togglePlacarExpandido(Map<String, dynamic> event) {
    final expanded = event['score_expanded'] == true;
    setState(() {
      event['score_expanded'] = !expanded;
    });
  }

  Widget _buildPlacarCard(Map<String, dynamic> event) {
    final rawScore = event['score'];
    if (rawScore == null || rawScore is! Map) {
      return const SizedBox.shrink();
    }

    final score = Map<String, dynamic>.from(rawScore);
    final olympusSets = List<dynamic>.from(score['olympus'] ?? []);
    final opponentSets = List<dynamic>.from(score['opponent'] ?? []);
    final winner = (score['winner'] ?? '').toString();
    final olympusSetsWon =
        int.tryParse(score['olympus_sets_won']?.toString() ?? '0') ?? 0;
    final opponentSetsWon =
        int.tryParse(score['opponent_sets_won']?.toString() ?? '0') ?? 0;

    final isVictory = winner == 'Olympus';
    final isExpandido = event['score_expanded'] == true;

    return GestureDetector(
      onTap: () => _togglePlacarExpandido(event),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isVictory
                ? [Colors.green.shade50, Colors.green.shade100]
                : [Colors.orange.shade50, Colors.orange.shade100],
          ),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isVictory ? Colors.green.shade700 : Colors.orange.shade700,
            width: 2,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isVictory ? Icons.emoji_events : Icons.sentiment_dissatisfied,
                  color: isVictory
                      ? Colors.green.shade700
                      : Colors.orange.shade700,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  isVictory ? 'VITÓRIA' : 'DERROTA',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: isVictory
                        ? Colors.green.shade700
                        : Colors.orange.shade700,
                    fontSize: 14,
                  ),
                ),
                const Spacer(),
                Row(
                  children: [
                    Text(
                      '$olympusSetsWon x $opponentSetsWon em Sets',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.grey.shade700,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      isExpandido
                          ? Icons.keyboard_arrow_up
                          : Icons.keyboard_arrow_down,
                      color: Colors.grey.shade600,
                      size: 20,
                    ),
                  ],
                ),
              ],
            ),
            if (isExpandido) ...[
              const SizedBox(height: 12),
              ...List.generate(olympusSets.length, (index) {
                final olympusScore =
                    int.tryParse(olympusSets[index].toString()) ?? 0;
                final opponentScore = index < opponentSets.length
                    ? int.tryParse(opponentSets[index].toString()) ?? 0
                    : 0;

                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '${index + 1}° Set',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.grey.shade700,
                          fontSize: 12,
                        ),
                      ),
                      Text(
                        '$olympusScore x $opponentScore',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ],
        ),
      ),
    );
  }

  Widget _infoChip(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: olympusBlue.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: olympusBlue.withOpacity(0.12),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: olympusGold),
          const SizedBox(width: 6),
          Text(
            text,
            style: const TextStyle(
              color: Colors.black87,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMiniStat({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: olympusGold.withOpacity(0.14),
            border: Border.all(
              color: olympusGold.withOpacity(0.28),
            ),
          ),
          child: Icon(
            icon,
            color: olympusGold,
            size: 20,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                label,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.62),
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildEventCard(Map<String, dynamic> event) {
    final imageUrl =
        ((event['image_url'] ?? event['game_photo_url'] ?? '').toString());

    final eventName = (event['event_name'] ?? '').toString();
    final eventType = _formatEventType((event['event_type'] ?? '').toString());
    final eventDate = (event['event_date'] ?? '').toString();
    final eventTime = (event['event_time'] ?? '').toString();
    final gender = _formatGender((event['gender'] ?? '').toString());
    final address = _buildAddress(event);
    final corTipo = _getCorTipoEvento((event['event_type'] ?? '').toString());

    final quantidades =
        Map<String, int>.from(event['quantidade_convocados'] ?? {});
    final stats = Map<String, int>.from(event['convocation_stats'] ?? {});

    final totalConvocados = stats['total_convocados'] ??
        ((quantidades['athletes'] ?? 0) + (quantidades['technicians'] ?? 0));

    final aceitos = stats['total_aceitos'] ?? 0;
    final pendentes = stats['total_pendentes'] ?? 0;
    final recusados = stats['total_recusados'] ?? 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [
            Color(0xFF122235),
            Color(0xFF18324D),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: olympusGold.withOpacity(0.25),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.35),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (imageUrl.isNotEmpty)
              Image.network(
                imageUrl,
                height: 180,
                width: double.infinity,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) {
                  return Container(
                    height: 180,
                    color: const Color(0xFF0B1420),
                    child: const Center(
                      child: Icon(
                        Icons.image_not_supported,
                        color: Colors.white38,
                      ),
                    ),
                  );
                },
              ),
            Container(
              width: double.infinity,
              color: const Color(0xFFEAF2F8),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: corTipo),
                        ),
                        child: Text(
                          eventType,
                          style: TextStyle(
                            color: corTipo,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade100,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          gender,
                          style: TextStyle(
                            color: Colors.blue.shade900,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    eventName,
                    style: const TextStyle(
                      color: Colors.black87,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(
                        Icons.emoji_events,
                        size: 16,
                        color: Colors.orange.shade700,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          widget.name,
                          style: TextStyle(
                            color: Colors.orange.shade700,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (eventDate.isNotEmpty)
                        _infoChip(Icons.calendar_today, eventDate),
                      if (eventTime.isNotEmpty)
                        _infoChip(Icons.access_time, eventTime),
                      _infoChip(Icons.people, gender),
                      if ((event['set_format'] ?? '').toString().isNotEmpty)
                        _infoChip(
                          Icons.format_list_numbered,
                          event['set_format'].toString(),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      const Icon(
                        Icons.location_on,
                        color: Colors.black54,
                        size: 16,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          address,
                          style: const TextStyle(
                            color: Colors.black54,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '$totalConvocados convocados (${quantidades['athletes'] ?? 0} atletas, ${quantidades['technicians'] ?? 0} técnicos)',
                    style: const TextStyle(
                      color: olympusBlue,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Text(
                        '✔ $aceitos aceitou',
                        style: const TextStyle(color: Colors.green),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        '⏳ $pendentes pendente${pendentes == 1 ? '' : 's'}',
                        style: const TextStyle(color: Colors.orange),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        '✖ $recusados recusou',
                        style: const TextStyle(color: Colors.red),
                      ),
                    ],
                  ),
                  if (event['score'] != null) ...[
                    const SizedBox(height: 12),
                    _buildPlacarCard(event),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopSummaryCard() {
    final totalGames = _allEvents.length;

    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.06),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: olympusGold.withOpacity(0.18),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: _buildMiniStat(
                  icon: Icons.emoji_events_rounded,
                  label: 'Liga',
                  value: widget.name,
                ),
              ),
              Container(
                width: 1,
                height: 42,
                color: Colors.white.withOpacity(0.12),
              ),
              Expanded(
                child: _buildMiniStat(
                  icon: Icons.sports_volleyball_rounded,
                  label: 'Jogos',
                  value: '$totalGames',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [
            Color(0xFF122235),
            Color(0xFF18324D),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: olympusGold.withOpacity(0.30)),
        boxShadow: [
          BoxShadow(
            color: olympusGold.withOpacity(0.08),
            blurRadius: 18,
            spreadRadius: 1,
          ),
          BoxShadow(
            color: Colors.black.withOpacity(0.35),
            blurRadius: 22,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: olympusGold.withOpacity(0.14),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: olympusGold.withOpacity(0.25),
              ),
            ),
            child: IconButton(
              padding: EdgeInsets.zero,
              onPressed: () {
                if (Navigator.canPop(context)) {
                  Navigator.pop(context);
                } else {
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const ChampionshipsPage(),
                    ),
                  );
                }
              },
              icon: const Icon(
                Icons.arrow_back_ios_new_rounded,
                color: Colors.white,
                size: 20,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Todos os jogos cadastrados neste campeonato',
                  style: TextStyle(
                    color: olympusGold.withOpacity(0.95),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: olympusGold.withOpacity(0.12),
              border: Border.all(
                color: olympusGold.withOpacity(0.25),
              ),
            ),
            child: const Icon(
              Icons.sports_volleyball_rounded,
              color: olympusGold,
              size: 24,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchField() {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [
            Color(0xFF122235),
            Color(0xFF18324D),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: olympusGold.withOpacity(0.22),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.24),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: TextField(
        controller: _searchController,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          hintText: 'Buscar jogo, cidade, data...',
          hintStyle: TextStyle(
            color: Colors.white.withOpacity(0.45),
          ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 16,
          ),
          prefixIcon: const Icon(
            Icons.search_rounded,
            color: olympusGold,
          ),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
                  onPressed: () {
                    _searchController.clear();
                    _applyFilter();
                  },
                  icon: const Icon(
                    Icons.close_rounded,
                    color: Colors.white70,
                  ),
                )
              : null,
        ),
      ),
    );
  }

  Widget _buildLoadingState() {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
      children: [
        _buildSearchField(),
        const SizedBox(height: 16),
        _buildTopSummaryCard(),
        const SizedBox(height: 18),
        ...List.generate(
          3,
          (index) => Container(
            height: 280,
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [
                  Color(0xFF122235),
                  Color(0xFF18324D),
                ],
              ),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: olympusGold.withOpacity(0.18),
              ),
            ),
            child: const Center(
              child: CircularProgressIndicator(
                color: olympusGold,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    final bool hasSearch = _searchController.text.trim().isNotEmpty;

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
      children: [
        _buildSearchField(),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [
                Color(0xFF122235),
                Color(0xFF18324D),
              ],
            ),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: olympusGold.withOpacity(0.22),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.28),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            children: [
              Container(
                width: 82,
                height: 82,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: olympusGold.withOpacity(0.12),
                  border: Border.all(
                    color: olympusGold.withOpacity(0.24),
                  ),
                ),
                child: Icon(
                  hasSearch
                      ? Icons.search_off_rounded
                      : Icons.sports_volleyball_outlined,
                  color: olympusGold,
                  size: 38,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                hasSearch ? 'Nenhum jogo encontrado' : 'Nenhum jogo cadastrado',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                hasSearch
                    ? 'Tente buscar com outro termo.'
                    : 'Ainda não existem jogos cadastrados para este campeonato.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.66),
                  fontSize: 13.5,
                  fontWeight: FontWeight.w500,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: futuristicDark,
      body: Stack(
        children: [
          _buildOlympusBackground(),
          SafeArea(
            child: Column(
              children: [
                _buildHeader(),
                Expanded(
                  child: RefreshIndicator(
                    color: olympusGold,
                    backgroundColor: futuristicCard,
                    onRefresh: _loadEvents,
                    child: _isLoading
                        ? _buildLoadingState()
                        : _filteredEvents.isEmpty
                            ? _buildEmptyState()
                            : ListView(
                                physics: const AlwaysScrollableScrollPhysics(),
                                padding:
                                    const EdgeInsets.fromLTRB(16, 8, 16, 20),
                                children: [
                                  _buildSearchField(),
                                  const SizedBox(height: 16),
                                  _buildTopSummaryCard(),
                                  const SizedBox(height: 18),
                                  ..._filteredEvents.asMap().entries.map(
                                    (entry) {
                                      final index = entry.key;
                                      final event = entry.value;

                                      return TweenAnimationBuilder<double>(
                                        tween: Tween(begin: 0, end: 1),
                                        duration: Duration(
                                          milliseconds: 260 + (index * 60),
                                        ),
                                        curve: Curves.easeOutCubic,
                                        builder: (context, value, child) {
                                          return Transform.translate(
                                            offset: Offset(
                                              0,
                                              20 * (1 - value),
                                            ),
                                            child: Opacity(
                                              opacity: value,
                                              child: child,
                                            ),
                                          );
                                        },
                                        child: _buildEventCard(event),
                                      );
                                    },
                                  ),
                                ],
                              ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FuturisticBackgroundPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final wavePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..color = const Color(0xFFD4AF37).withOpacity(0.07)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);

    final wavePaint2 = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..color = const Color(0xFF8FE8FF).withOpacity(0.06)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);

    final path1 = Path();
    path1.moveTo(0, size.height * 0.18);
    path1.cubicTo(
      size.width * 0.20,
      size.height * 0.10,
      size.width * 0.35,
      size.height * 0.28,
      size.width * 0.52,
      size.height * 0.18,
    );
    path1.cubicTo(
      size.width * 0.68,
      size.height * 0.08,
      size.width * 0.82,
      size.height * 0.23,
      size.width,
      size.height * 0.15,
    );
    canvas.drawPath(path1, wavePaint);

    final path2 = Path();
    path2.moveTo(0, size.height * 0.80);
    path2.cubicTo(
      size.width * 0.18,
      size.height * 0.70,
      size.width * 0.36,
      size.height * 0.90,
      size.width * 0.56,
      size.height * 0.80,
    );
    path2.cubicTo(
      size.width * 0.74,
      size.height * 0.72,
      size.width * 0.86,
      size.height * 0.86,
      size.width,
      size.height * 0.78,
    );
    canvas.drawPath(path2, wavePaint2);

    final nodePaint = Paint()
      ..color = const Color(0xFFE8FCFF).withOpacity(0.12)
      ..style = PaintingStyle.fill;

    final linePaint = Paint()
      ..color = const Color(0xFFC7F6FF).withOpacity(0.10)
      ..strokeWidth = 1;

    final points = <Offset>[
      Offset(size.width * 0.72, size.height * 0.34),
      Offset(size.width * 0.82, size.height * 0.38),
      Offset(size.width * 0.90, size.height * 0.33),
      Offset(size.width * 0.76, size.height * 0.44),
      Offset(size.width * 0.88, size.height * 0.47),
      Offset(size.width * 0.69, size.height * 0.52),
      Offset(size.width * 0.83, size.height * 0.56),
      Offset(size.width * 0.93, size.height * 0.52),
      Offset(size.width * 0.73, size.height * 0.64),
      Offset(size.width * 0.86, size.height * 0.67),
    ];

    for (int i = 0; i < points.length - 1; i++) {
      canvas.drawLine(points[i], points[i + 1], linePaint);
    }
    canvas.drawLine(points[0], points[3], linePaint);
    canvas.drawLine(points[1], points[4], linePaint);
    canvas.drawLine(points[3], points[5], linePaint);
    canvas.drawLine(points[4], points[6], linePaint);
    canvas.drawLine(points[6], points[8], linePaint);
    canvas.drawLine(points[7], points[9], linePaint);

    for (final point in points) {
      canvas.drawCircle(point, 1.8, nodePaint);
    }

    final glowPaint = Paint()
      ..color = const Color(0xFFD4AF37).withOpacity(0.05)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 26);

    canvas.drawCircle(
      Offset(size.width * 0.20, size.height * 0.25),
      70,
      glowPaint,
    );
    canvas.drawCircle(
      Offset(size.width * 0.78, size.height * 0.55),
      90,
      glowPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
