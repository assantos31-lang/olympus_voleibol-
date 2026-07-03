import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/coach_evaluation_service.dart';

class AthleteCoachEvaluationHistoryPage extends StatefulWidget {
  const AthleteCoachEvaluationHistoryPage({super.key});

  @override
  State<AthleteCoachEvaluationHistoryPage> createState() =>
      _AthleteCoachEvaluationHistoryPageState();
}

class _AthleteCoachEvaluationHistoryPageState
    extends State<AthleteCoachEvaluationHistoryPage> {
  static const Color olympusBlue = Color(0xFF1E3A5F);
  static const Color olympusGold = Color(0xFFD4AF37);
  static const Color olympusMuted = Color(0xFF53657B);

  final CoachEvaluationService _service = CoachEvaluationService();
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _rows = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) throw Exception('Usuário não autenticado.');
      final rows = await _service.loadCompletedEvaluationsForAthlete(
        athleteId: user.id,
      );
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Erro ao carregar avaliações: $e';
        _loading = false;
      });
    }
  }

  String _monthName(int month) => const [
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
      ][month.clamp(1, 12)];

  String _monthKey(Map<String, dynamic> row) {
    final created =
        DateTime.tryParse((row['created_at'] ?? '').toString())?.toLocal();
    final month = (row['reference_month'] as num?)?.toInt() ?? created?.month;
    final year = (row['reference_year'] as num?)?.toInt() ?? created?.year;
    if (month == null || year == null) return 'Sem período';
    return '${_monthName(month)} / $year';
  }

  Map<String, List<Map<String, dynamic>>> get _grouped {
    final result = <String, List<Map<String, dynamic>>>{};
    for (final row in _rows) {
      result.putIfAbsent(_monthKey(row), () => []).add(row);
    }
    return result;
  }

  String _coachName(Map<String, dynamic> row) {
    final coach = row['coach'];
    if (coach is Map) {
      final name = (coach['full_name'] ?? '').toString().trim();
      if (name.isNotEmpty) return name;
    }
    return 'Treinador';
  }

  Widget _background() => Stack(
        children: [
          Positioned.fill(
            child: Image.asset(
              'assets/images/monte_olimpo_v2.png',
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(color: olympusBlue),
            ),
          ),
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 2.5, sigmaY: 2.5),
              child: Container(color: const Color(0xFF071A30).withOpacity(.72)),
            ),
          ),
        ],
      );

  Widget _evaluationCard(Map<String, dynamic> row) {
    final event = row['events'];
    final eventMap = event is Map ? event : const <String, dynamic>{};
    final eventName = (eventMap['event_name'] ?? '').toString();
    final eventDate = (eventMap['event_date'] ?? '').toString();
    final isMonthly = row['evaluation_type'] == 'monthly';
    final status = (row['admin_review_status'] ?? 'pending').toString();

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(.96),
        borderRadius: BorderRadius.circular(19),
        border: Border.all(color: Colors.white.withOpacity(.50)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color:
                      (isMonthly ? olympusGold : olympusBlue).withOpacity(.12),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  isMonthly ? 'MENSAL' : 'TREINO',
                  style: TextStyle(
                    color: isMonthly ? const Color(0xFF8A6500) : olympusBlue,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const Spacer(),
              Icon(
                status == 'approved'
                    ? Icons.verified_rounded
                    : Icons.schedule_rounded,
                color: status == 'approved'
                    ? const Color(0xFF16A34A)
                    : const Color(0xFFF59E0B),
                size: 18,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            _coachName(row),
            style: const TextStyle(
              color: olympusBlue,
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
          if (!isMonthly && (eventName.isNotEmpty || eventDate.isNotEmpty)) ...[
            const SizedBox(height: 4),
            Text(
              [eventName, eventDate]
                  .where((value) => value.isNotEmpty)
                  .join(' • '),
              style: const TextStyle(
                color: olympusMuted,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          const SizedBox(height: 9),
          Row(
            children: [
              const Icon(Icons.star_rounded, color: olympusGold, size: 19),
              const SizedBox(width: 5),
              Text(
                'Nota geral: ${row['rating_general'] ?? '-'} / 5',
                style: const TextStyle(
                  color: olympusBlue,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          if ((row['positive_point'] ?? '').toString().trim().isNotEmpty) ...[
            const SizedBox(height: 7),
            Text(
              '💙 ${(row['positive_point']).toString()}',
              style: const TextStyle(color: olympusMuted, height: 1.3),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: olympusBlue,
      appBar: AppBar(
        title: const Text('Avaliações realizadas'),
        backgroundColor: olympusBlue,
        foregroundColor: Colors.white,
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded)),
        ],
      ),
      body: Stack(
        children: [
          Positioned.fill(child: _background()),
          if (_loading)
            const Center(child: CircularProgressIndicator(color: Colors.white))
          else if (_error != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
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
          else if (_rows.isEmpty)
            const Center(
              child: Text(
                'Você ainda não realizou avaliações.',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
            )
          else
            ListView(
              padding: const EdgeInsets.all(14),
              children: _grouped.entries.expand((entry) sync* {
                yield Padding(
                  padding: const EdgeInsets.fromLTRB(3, 8, 3, 9),
                  child: Text(
                    entry.key,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                );
                yield* entry.value.map(_evaluationCard);
              }).toList(),
            ),
        ],
      ),
    );
  }
}
