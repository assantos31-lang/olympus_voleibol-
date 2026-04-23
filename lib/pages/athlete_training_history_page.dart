import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AthleteTrainingHistoryPage extends StatefulWidget {
  const AthleteTrainingHistoryPage({
    super.key,
    required this.athleteId,
    this.athleteName,
    this.avatarUrl,
  });

  final String athleteId;
  final String? athleteName;
  final String? avatarUrl;

  @override
  State<AthleteTrainingHistoryPage> createState() =>
      _AthleteTrainingHistoryPageState();
}

class _AthleteTrainingHistoryPageState
    extends State<AthleteTrainingHistoryPage> {
  final SupabaseClient _supabase = Supabase.instance.client;

  static const Color olympusBlue = Color(0xFF1E3A5F);
  static const Color olympusGold = Color(0xFFD4AF37);

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _historico = [];

  @override
  void initState() {
    super.initState();
    _carregarHistorico();
  }

  bool _isMobile(BuildContext context) {
    return MediaQuery.of(context).size.width < 600;
  }

  Future<void> _carregarHistorico() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final rows = await _supabase
          .from('training_evaluations')
          .select(
              'id, event_id, coach_id, athlete_id, tipo, slot, motivo, fundamento, observacao, created_at')
          .eq('athlete_id', widget.athleteId)
          .order('created_at', ascending: false);

      final historico = List<Map<String, dynamic>>.from(rows);

      final eventIds = historico
          .map((e) => (e['event_id'] ?? '').toString())
          .where((e) => e.isNotEmpty)
          .toSet()
          .toList();

      final coachIds = historico
          .map((e) => (e['coach_id'] ?? '').toString())
          .where((e) => e.isNotEmpty)
          .toSet()
          .toList();

      final Map<String, Map<String, dynamic>> eventsById = {};
      final Map<String, String> coachNamesById = {};

      if (eventIds.isNotEmpty) {
        final eventRows = await _supabase
            .from('events')
            .select('id, event_name, event_date, event_time')
            .inFilter('id', eventIds);

        for (final row in eventRows) {
          final map = Map<String, dynamic>.from(row);
          final id = (map['id'] ?? '').toString();
          if (id.isNotEmpty) {
            eventsById[id] = map;
          }
        }
      }

      if (coachIds.isNotEmpty) {
        final coachRows = await _supabase
            .from('profiles')
            .select('id, full_name')
            .inFilter('id', coachIds);

        for (final row in coachRows) {
          final map = Map<String, dynamic>.from(row);
          final id = (map['id'] ?? '').toString();
          if (id.isNotEmpty) {
            coachNamesById[id] = (map['full_name'] ?? 'Técnico').toString();
          }
        }
      }

      for (final item in historico) {
        final eventId = (item['event_id'] ?? '').toString();
        final coachId = (item['coach_id'] ?? '').toString();
        final event = eventsById[eventId];

        item['event_name'] = (event?['event_name'] ?? 'Treino').toString();
        item['event_date'] = (event?['event_date'] ?? '').toString();
        item['event_time'] = (event?['event_time'] ?? '').toString();
        item['coach_name'] = coachNamesById[coachId] ?? 'Técnico';
      }

      if (!mounted) return;
      setState(() {
        _historico = historico;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Erro ao carregar histórico: $e';
        _loading = false;
      });
    }
  }

  String _formatSlotLabel(String slot) {
    if (slot.startsWith('destaque_')) {
      final numero = slot.replaceFirst('destaque_', '');
      return 'Destaque #$numero';
    }
    if (slot.startsWith('atencao_')) {
      final numero = slot.replaceFirst('atencao_', '');
      return 'Ponto de atenção #$numero';
    }
    return slot;
  }

  String _formatCreatedAt(String value) {
    try {
      final dt = DateTime.parse(value).toLocal();
      final dia = dt.day.toString().padLeft(2, '0');
      final mes = dt.month.toString().padLeft(2, '0');
      final hora = dt.hour.toString().padLeft(2, '0');
      final minuto = dt.minute.toString().padLeft(2, '0');
      return '$dia/$mes às $hora:$minuto';
    } catch (_) {
      return value;
    }
  }

  Widget _buildAvatar() {
    final avatarUrl = (widget.avatarUrl ?? '').trim();
    final athleteName = (widget.athleteName ?? 'Atleta').trim();

    return CircleAvatar(
      radius: 28,
      backgroundColor: olympusGold.withOpacity(0.18),
      backgroundImage: avatarUrl.isNotEmpty ? NetworkImage(avatarUrl) : null,
      child: avatarUrl.isEmpty
          ? Text(
              athleteName.isNotEmpty ? athleteName[0].toUpperCase() : '?',
              style: const TextStyle(
                color: olympusBlue,
                fontWeight: FontWeight.w800,
              ),
            )
          : null,
    );
  }

  Color _tipoColor(String tipo) {
    return tipo == 'destaque' ? Colors.green : Colors.orange;
  }

  IconData _tipoIcon(String tipo) {
    return tipo == 'destaque'
        ? Icons.star_rounded
        : Icons.warning_amber_rounded;
  }

  String _tipoLabel(String tipo) {
    return tipo == 'destaque' ? 'Destaque' : 'Ponto de atenção';
  }

  Widget _buildHeaderCard(bool isMobile) {
    final athleteName = (widget.athleteName ?? 'Histórico do atleta').trim();

    return Container(
      padding: EdgeInsets.all(isMobile ? 14 : 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE4EDF5)),
      ),
      child: Row(
        children: [
          _buildAvatar(),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  athleteName.isEmpty ? 'Atleta' : athleteName,
                  style: TextStyle(
                    color: olympusBlue,
                    fontSize: isMobile ? 18 : 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Histórico de avaliações por treino',
                  style: TextStyle(
                    color: const Color(0xFF53657B),
                    fontSize: isMobile ? 12 : 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Registros salvos em training_evaluations',
                  style: TextStyle(
                    color: const Color(0xFF6A7E94),
                    fontSize: isMobile ? 11 : 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryCard(Map<String, dynamic> item, bool isMobile) {
    final tipo = (item['tipo'] ?? '').toString();
    final color = _tipoColor(tipo);
    final icon = _tipoIcon(tipo);
    final label = _tipoLabel(tipo);

    final eventName = (item['event_name'] ?? 'Treino').toString();
    final eventDate = (item['event_date'] ?? '').toString();
    final eventTime = (item['event_time'] ?? '').toString();
    final motivo = (item['motivo'] ?? '').toString();
    final fundamento = (item['fundamento'] ?? '').toString();
    final observacao = (item['observacao'] ?? '').toString();
    final coachName = (item['coach_name'] ?? 'Técnico').toString();
    final slot = (item['slot'] ?? '').toString();
    final createdAt = (item['created_at'] ?? '').toString();

    final dataHora = [
      if (eventDate.isNotEmpty) eventDate,
      if (eventTime.isNotEmpty) eventTime,
    ].join(' • ');

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: EdgeInsets.all(isMobile ? 14 : 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE4EDF5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: isMobile ? 42 : 46,
                height: isMobile ? 42 : 46,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      eventName,
                      style: TextStyle(
                        color: olympusBlue,
                        fontSize: isMobile ? 15 : 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      dataHora.isEmpty ? 'Sem data' : dataHora,
                      style: TextStyle(
                        color: const Color(0xFF53657B),
                        fontSize: isMobile ? 12 : 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  label,
                  style: TextStyle(
                    color: color,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (motivo.isNotEmpty) ...[
            Text(
              'Motivo: $motivo',
              style: TextStyle(
                color: olympusBlue,
                fontSize: isMobile ? 12 : 13,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
          ],
          if (fundamento.isNotEmpty) ...[
            Text(
              'Fundamento: $fundamento',
              style: TextStyle(
                color: const Color(0xFF53657B),
                fontSize: isMobile ? 12 : 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
          ],
          if (observacao.isNotEmpty) ...[
            Text(
              'Observação: $observacao',
              style: TextStyle(
                color: const Color(0xFF6A7E94),
                fontSize: isMobile ? 12 : 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
          ],
          Text(
            _formatSlotLabel(slot),
            style: TextStyle(
              color: const Color(0xFF6A7E94),
              fontSize: isMobile ? 11 : 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Técnico: $coachName',
            style: TextStyle(
              color: const Color(0xFF6A7E94),
              fontSize: isMobile ? 11 : 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (createdAt.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'Avaliado em: ${_formatCreatedAt(createdAt)}',
              style: TextStyle(
                color: const Color(0xFF94A3B8),
                fontSize: isMobile ? 10 : 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = _isMobile(context);

    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FB),
      appBar: AppBar(
        title: const Text('Histórico do atleta'),
        backgroundColor: olympusBlue,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            onPressed: _carregarHistorico,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.all(isMobile ? 12 : 16),
        children: [
          _buildHeaderCard(isMobile),
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
          else if (_historico.isEmpty)
            Container(
              padding: EdgeInsets.all(isMobile ? 14 : 16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFFE4EDF5)),
              ),
              child: const Text(
                'Nenhuma avaliação encontrada para este atleta.',
                style: TextStyle(
                  color: Color(0xFF53657B),
                  fontWeight: FontWeight.w600,
                ),
              ),
            )
          else
            ..._historico.map((item) => _buildHistoryCard(item, isMobile)),
        ],
      ),
    );
  }
}
