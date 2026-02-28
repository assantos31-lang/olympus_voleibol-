import 'package:flutter/material.dart';
import 'add_event_page.dart';

class AgendaPage extends StatelessWidget {
  const AgendaPage({super.key});

  @override
  Widget build(BuildContext context) {
    final goldenColor = const Color(0xFFE4C050);

    return Scaffold(
      backgroundColor: const Color(0xFF1E3A5F),
      appBar: AppBar(
        title: const Text(
          'Agenda',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        backgroundColor: const Color(0xFF2E5C8A),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildDateHeader(context),
          const SizedBox(height: 16),
          _buildEventCard(
            goldenColor: goldenColor,
            title: 'Treino - Categoria Sub-18',
            date: '15',
            month: 'JAN',
            time: '18:00 - 20:00',
            location: 'Quadra Principal',
            icon: Icons.fitness_center,
            color: Colors.blue,
          ),
          _buildEventCard(
            goldenColor: goldenColor,
            title: 'Jogo Amistoso vs. Atlético Vôlei',
            date: '17',
            month: 'JAN',
            time: '19:30 - 21:30',
            location: 'Ginásio Municipal',
            icon: Icons.sports_volleyball,
            color: Colors.red,
          ),
          _buildEventCard(
            goldenColor: goldenColor,
            title: 'Reunião de Pais e Atletas',
            date: '20',
            month: 'JAN',
            time: '19:00 - 20:30',
            location: 'Sala de Reuniões',
            icon: Icons.people,
            color: Colors.green,
          ),
          _buildEventCard(
            goldenColor: goldenColor,
            title: 'Treino - Categoria Adulto',
            date: '22',
            month: 'JAN',
            time: '20:00 - 22:00',
            location: 'Quadra Principal',
            icon: Icons.fitness_center,
            color: Colors.blue,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const AddEventPage()),
          );
        },
        backgroundColor: goldenColor,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Novo Evento'),
      ),
    );
  }

  Widget _buildDateHeader(BuildContext context) {
    return GestureDetector(
      onTap: () async {
        // ✅ Correção 1: Removido 'locale' - herda do MaterialApp
        // ✅ Correção 2: Removido try-catch para não mascarar erros
        final DateTime? picked = await showDatePicker(
          context: context,
          initialDate: DateTime.now(),
          firstDate: DateTime(2020),
          lastDate: DateTime(2030),
        );
        if (picked != null) {
          debugPrint(
              'Data selecionada: ${picked.day}/${picked.month}/${picked.year}');
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        decoration: BoxDecoration(
          color: const Color(0xFF2E5C8A).withOpacity(0.5),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.calendar_today,
                color: Color(0xFFE4C050), size: 18),
            const SizedBox(width: 8),
            const Text(
              'Hoje, 15 de Janeiro de 2026',
              style: TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEventCard({
    required Color goldenColor,
    required String title,
    required String date,
    required String month,
    required String time,
    required String location,
    required IconData icon,
    required Color color,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: Colors.white.withOpacity(0.1),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.white.withOpacity(0.2)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: goldenColor.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                children: [
                  Text(
                    date,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    month,
                    style: TextStyle(
                      color: goldenColor,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(icon, color: color, size: 18),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(Icons.access_time, color: Colors.white70, size: 14),
                      const SizedBox(width: 4),
                      Text(
                        time,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.8),
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.location_on, color: Colors.white70, size: 14),
                      const SizedBox(width: 4),
                      Text(
                        location,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.8),
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
