import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CoachReceivedEvaluationsPage extends StatefulWidget {
  const CoachReceivedEvaluationsPage({super.key});

  @override
  State<CoachReceivedEvaluationsPage> createState() =>
      _CoachReceivedEvaluationsPageState();
}

class _CoachReceivedEvaluationsPageState
    extends State<CoachReceivedEvaluationsPage> {
  final SupabaseClient _supabase = Supabase.instance.client;

  bool _loading = true;
  String? _error;

  List<Map<String, dynamic>> _evaluations = [];

  static const Color olympusBlue = Color(0xFF1E3A5F);
  static const Color olympusGold = Color(0xFFD4AF37);
  static const Color olympusBg = Color(0xFFF4F7FB);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final coachId = _supabase.auth.currentUser?.id;

      if (coachId == null) {
        throw Exception('Treinador não identificado.');
      }

      final rows = await _supabase
          .from('coach_evaluations')
          .select('''
id,
rating_general,
rating_clarity,
rating_respect,
rating_training_quality,
rating_motivation,
rating_organization,
rating_evolution,
rating_communication,
positive_point,
improvement_point,
comment,
communication_comment,
suggestion,
anonymous_to_coach,
created_at,
admin_review_status,
athlete:profiles!coach_evaluations_athlete_id_fkey (
  full_name
)
''')
          .eq('coach_id', coachId)
          .eq('visible_to_coach', true)
          .eq('admin_review_status', 'approved')
          .order('created_at', ascending: false);

      if (!mounted) return;

      setState(() {
        _evaluations = List<Map<String, dynamic>>.from(rows);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Widget _stars(int rating) {
    return Row(
      children: List.generate(
        5,
        (index) => Icon(
          index < rating ? Icons.star : Icons.star_border,
          color: olympusGold,
          size: 18,
        ),
      ),
    );
  }

  String _formatDate(dynamic value) {
    final parsed = DateTime.tryParse(
      (value ?? '').toString(),
    )?.toLocal();

    if (parsed == null) {
      return '';
    }

    return '${parsed.day.toString().padLeft(2, '0')}/'
        '${parsed.month.toString().padLeft(2, '0')}/'
        '${parsed.year}';
  }

  Widget _ratingRow(String title, dynamic value) {
    final rating = (value as num?)?.toInt() ?? 0;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 130,
            child: Text(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(child: _stars(rating)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: olympusBg,
      appBar: AppBar(
        title: const Text('Avaliações Recebidas'),
        backgroundColor: olympusBlue,
        foregroundColor: Colors.white,
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(),
            )
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text(
                      _error!,
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : _evaluations.isEmpty
                  ? const Center(
                      child: Text(
                        'Nenhuma avaliação aprovada foi liberada para você.',
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _evaluations.length,
                        itemBuilder: (context, index) {
                          final item = _evaluations[index];

                          final anonymous = item['anonymous_to_coach'] == true;

                          final athlete =
                              item['athlete'] as Map<String, dynamic>?;

                          final athleteName = anonymous
                              ? 'Anônimo'
                              : (athlete?['full_name'] ?? 'Atleta');

                          return Card(
                            elevation: 3,
                            margin: const EdgeInsets.only(bottom: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      const Icon(
                                        Icons.rate_review_outlined,
                                        color: olympusGold,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          athleteName,
                                          style: const TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.w900,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _formatDate(item['created_at']),
                                    style: const TextStyle(
                                      color: Colors.grey,
                                      fontSize: 12,
                                    ),
                                  ),
                                  const Divider(height: 24),
                                  _ratingRow(
                                    'Geral',
                                    item['rating_general'],
                                  ),
                                  _ratingRow(
                                    'Clareza',
                                    item['rating_clarity'],
                                  ),
                                  _ratingRow(
                                    'Respeito',
                                    item['rating_respect'],
                                  ),
                                  _ratingRow(
                                    'Treino',
                                    item['rating_training_quality'],
                                  ),
                                  _ratingRow(
                                    'Motivação',
                                    item['rating_motivation'],
                                  ),
                                  _ratingRow(
                                    'Organização',
                                    item['rating_organization'],
                                  ),
                                  _ratingRow(
                                    'Evolução',
                                    item['rating_evolution'],
                                  ),
                                  _ratingRow(
                                    'Comunicação',
                                    item['rating_communication'],
                                  ),
                                  if ((item['positive_point'] ?? '')
                                      .toString()
                                      .trim()
                                      .isNotEmpty) ...[
                                    const SizedBox(height: 16),
                                    const Text(
                                      'Ponto Positivo',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      item['positive_point'],
                                    ),
                                  ],
                                  if ((item['improvement_point'] ?? '')
                                      .toString()
                                      .trim()
                                      .isNotEmpty) ...[
                                    const SizedBox(height: 16),
                                    const Text(
                                      'Ponto de Melhoria',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      item['improvement_point'],
                                    ),
                                  ],
                                  if ((item['comment'] ?? '')
                                      .toString()
                                      .trim()
                                      .isNotEmpty) ...[
                                    const SizedBox(height: 16),
                                    const Text(
                                      'Comentário',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      item['comment'],
                                    ),
                                  ],
                                  if ((item['communication_comment'] ?? '')
                                      .toString()
                                      .trim()
                                      .isNotEmpty) ...[
                                    const SizedBox(height: 16),
                                    const Text(
                                      'Comentário sobre Comunicação',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      item['communication_comment'],
                                    ),
                                  ],
                                  if ((item['suggestion'] ?? '')
                                      .toString()
                                      .trim()
                                      .isNotEmpty) ...[
                                    const SizedBox(height: 16),
                                    const Text(
                                      'Sugestão',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      item['suggestion'],
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
    );
  }
}
