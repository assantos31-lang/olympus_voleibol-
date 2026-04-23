import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'athlete_training_history_page.dart';

class CoachRankingPage extends StatefulWidget {
  const CoachRankingPage({super.key});

  @override
  State<CoachRankingPage> createState() => _CoachRankingPageState();
}

class _CoachRankingPageState extends State<CoachRankingPage> {
  final SupabaseClient _supabase = Supabase.instance.client;

  static const Color olympusBlue = Color(0xFF1E3A5F);
  static const Color olympusGold = Color(0xFFD4AF37);

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _ranking = [];

  @override
  void initState() {
    super.initState();
    _carregarRanking();
  }

  bool _isMobile(BuildContext context) {
    return MediaQuery.of(context).size.width < 600;
  }

  Future<void> _carregarRanking() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final rows = await _supabase
          .from('training_evaluations')
          .select('athlete_id, tipo, score, created_at')
          .order('created_at', ascending: false);

      final evaluations = List<Map<String, dynamic>>.from(rows);
      final athleteIds = evaluations
          .map((e) => (e['athlete_id'] ?? '').toString())
          .where((e) => e.isNotEmpty)
          .toSet()
          .toList();

      final profilesById = <String, Map<String, dynamic>>{};
      if (athleteIds.isNotEmpty) {
        final profiles = await _supabase
            .from('profiles')
            .select('id, full_name, avatar_url')
            .inFilter('id', athleteIds);

        for (final row in profiles) {
          final map = Map<String, dynamic>.from(row);
          final id = (map['id'] ?? '').toString();
          if (id.isNotEmpty) {
            profilesById[id] = map;
          }
        }
      }

      final aggregated = <String, Map<String, dynamic>>{};
      for (final row in evaluations) {
        final athleteId = (row['athlete_id'] ?? '').toString();
        if (athleteId.isEmpty) continue;

        final tipo = (row['tipo'] ?? '').toString();
        final dbScore = row['score'];
        int pontos = 0;

        if (dbScore is int) {
          pontos = dbScore;
        } else if (dbScore is num) {
          pontos = dbScore.toInt();
        } else {
          pontos = tipo == 'destaque' ? 2 : -1;
        }

        if (pontos == 0) {
          pontos = tipo == 'destaque' ? 2 : -1;
        }

        aggregated.putIfAbsent(athleteId, () {
          final profile = profilesById[athleteId];
          return {
            'athlete_id': athleteId,
            'nome': (profile?['full_name'] ?? 'Atleta').toString(),
            'avatar_url': (profile?['avatar_url'] ?? '').toString(),
            'score': 0,
            'destaques': 0,
            'atencoes': 0,
            'avaliacoes': 0,
          };
        });

        aggregated[athleteId]!['score'] =
            (aggregated[athleteId]!['score'] as int) + pontos;
        aggregated[athleteId]!['avaliacoes'] =
            (aggregated[athleteId]!['avaliacoes'] as int) + 1;

        if (tipo == 'destaque') {
          aggregated[athleteId]!['destaques'] =
              (aggregated[athleteId]!['destaques'] as int) + 1;
        } else if (tipo == 'atencao') {
          aggregated[athleteId]!['atencoes'] =
              (aggregated[athleteId]!['atencoes'] as int) + 1;
        }
      }

      final ranking = aggregated.values.toList()
        ..sort((a, b) {
          final scoreCompare = (b['score'] as int).compareTo(a['score'] as int);
          if (scoreCompare != 0) return scoreCompare;
          return a['nome'].toString().compareTo(b['nome'].toString());
        });

      if (!mounted) return;
      setState(() {
        _ranking = ranking;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Erro ao carregar ranking: $e';
        _loading = false;
      });
    }
  }

  Widget _buildAvatar(String avatarUrl, String nome, int posicao) {
    if (avatarUrl.trim().isNotEmpty) {
      return CircleAvatar(
        radius: 24,
        backgroundImage: NetworkImage(avatarUrl),
      );
    }

    return CircleAvatar(
      radius: 24,
      backgroundColor: posicao <= 3
          ? olympusGold.withOpacity(0.18)
          : olympusBlue.withOpacity(0.10),
      child: Text(
        nome.isNotEmpty ? nome[0].toUpperCase() : '?',
        style: const TextStyle(
          color: olympusBlue,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Color _positionColor(int posicao) {
    if (posicao == 1) return const Color(0xFFD4AF37);
    if (posicao == 2) return const Color(0xFF94A3B8);
    if (posicao == 3) return const Color(0xFFB45309);
    return olympusBlue;
  }

  Widget _buildTopCard(Map<String, dynamic> item, int index, bool isMobile) {
    final posicao = index + 1;
    final nome = (item['nome'] ?? 'Atleta').toString();
    final avatarUrl = (item['avatar_url'] ?? '').toString();
    final athleteId = (item['athlete_id'] ?? '').toString();
    final score = (item['score'] ?? 0).toString();
    final destaques = (item['destaques'] ?? 0).toString();
    final atencoes = (item['atencoes'] ?? 0).toString();
    final color = _positionColor(posicao);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: athleteId.isEmpty
              ? null
              : () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => AthleteTrainingHistoryPage(
                        athleteId: athleteId,
                        athleteName: nome,
                        avatarUrl: avatarUrl,
                      ),
                    ),
                  );
                },
          child: Container(
            padding: EdgeInsets.all(isMobile ? 14 : 16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFE4EDF5)),
            ),
            child: Row(
              children: [
                Container(
                  width: 34,
                  alignment: Alignment.center,
                  child: Text(
                    '$posicao',
                    style: TextStyle(
                      color: color,
                      fontSize: isMobile ? 20 : 22,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                _buildAvatar(avatarUrl, nome, posicao),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        nome,
                        style: TextStyle(
                          color: olympusBlue,
                          fontSize: isMobile ? 14 : 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Destaques: $destaques • Pontos de atenção: $atencoes',
                        style: TextStyle(
                          color: const Color(0xFF6A7E94),
                          fontSize: isMobile ? 11 : 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '$score pts',
                        style: TextStyle(
                          color: color,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Icon(
                      Icons.chevron_right_rounded,
                      color: Colors.grey.shade500,
                      size: 20,
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

  @override
  Widget build(BuildContext context) {
    final isMobile = _isMobile(context);

    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FB),
      appBar: AppBar(
        title: const Text('Ranking dos atletas'),
        backgroundColor: olympusBlue,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            onPressed: _carregarRanking,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.all(isMobile ? 12 : 16),
        children: [
          Container(
            padding: EdgeInsets.all(isMobile ? 14 : 16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFE4EDF5)),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Ranking geral',
                  style: TextStyle(
                    color: olympusBlue,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  'Pontuação usada: destaque = +2 | ponto de atenção = -1',
                  style: TextStyle(
                    color: Color(0xFF53657B),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(30),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_error != null)
            Container(
              padding: EdgeInsets.all(isMobile ? 14 : 16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFFE4EDF5)),
              ),
              child: Text(
                _error!,
                style: const TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.w600,
                ),
              ),
            )
          else if (_ranking.isEmpty)
            Container(
              padding: EdgeInsets.all(isMobile ? 14 : 16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFFE4EDF5)),
              ),
              child: const Text(
                'Nenhuma avaliação encontrada para montar o ranking.',
                style: TextStyle(
                  color: Color(0xFF53657B),
                  fontWeight: FontWeight.w600,
                ),
              ),
            )
          else
            ...List.generate(
              _ranking.length,
              (index) => _buildTopCard(_ranking[index], index, isMobile),
            ),
        ],
      ),
    );
  }
}
