import 'dart:ui';
import 'package:flutter/material.dart';
import '../models/birthday_person.dart';
import '../services/birthday_service.dart';

class AdminBirthdaysPage extends StatelessWidget {
  const AdminBirthdaysPage({super.key});

  @override
  Widget build(BuildContext context) {
    const goldenColor = Color(0xFFE4C050);
    const cyanColor = Color(0xFF8FE8FF);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Aniversariantes'),
        backgroundColor: const Color(0xFF0C2340),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF0C2340),
              Color(0xFF123A63),
              Color(0xFF071A30),
            ],
          ),
        ),
        child: FutureBuilder<List<BirthdayPerson>>(
          future: BirthdayService().getAllBirthdays(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                child: CircularProgressIndicator(color: Colors.white),
              );
            }

            if (snapshot.hasError) {
              return Center(
                child: Text(
                  'Erro ao carregar aniversariantes',
                  style: TextStyle(color: Colors.white.withOpacity(0.85)),
                ),
              );
            }

            final people = snapshot.data ?? [];

            if (people.isEmpty) {
              return Center(
                child: Text(
                  'Nenhum aniversariante encontrado.',
                  style: TextStyle(color: Colors.white.withOpacity(0.85)),
                ),
              );
            }

            final Map<int, List<BirthdayPerson>> groupedByMonth = {};
            for (final person in people) {
              groupedByMonth.putIfAbsent(person.birthDate.month, () => []);
              groupedByMonth[person.birthDate.month]!.add(person);
            }

            final groupedEntries = groupedByMonth.entries.toList()
              ..sort((a, b) => a.key.compareTo(b.key));

            return ListView(
              padding: const EdgeInsets.all(16),
              children: groupedEntries.map((entry) {
                final month = entry.key;
                final monthPeople = entry.value;

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(
                        top: 6,
                        bottom: 12,
                        left: 4,
                      ),
                      child: Text(
                        _monthName(month),
                        style: const TextStyle(
                          color: Color(0xFFE4C050),
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    ...monthPeople.map(
                      (person) => Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.14),
                          ),
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              Colors.white.withOpacity(0.14),
                              Colors.white.withOpacity(0.06),
                            ],
                          ),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(18),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                            child: ListTile(
                              leading: _buildAvatar(
                                person,
                                goldenColor,
                              ),
                              title: Text(
                                person.fullName,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              subtitle: Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Text(
                                  'Nascimento: ${person.formattedBirthday}  •  Faltam ${person.daysUntilBirthday} dia(s)',
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.75),
                                  ),
                                ),
                              ),
                              trailing: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: cyanColor.withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: cyanColor.withOpacity(0.30),
                                  ),
                                ),
                                child: Text(
                                  '${person.age} anos',
                                  style: const TextStyle(
                                    color: Color(0xFF8FE8FF),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              }).toList(),
            );
          },
        ),
      ),
    );
  }

  Widget _buildAvatar(BirthdayPerson person, Color goldenColor) {
    final imageUrl = _extractImageUrl(person);

    if (imageUrl != null && imageUrl.isNotEmpty) {
      return Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: goldenColor.withOpacity(0.16),
          border: Border.all(
            color: goldenColor.withOpacity(0.35),
          ),
        ),
        child: ClipOval(
          child: Image.network(
            imageUrl,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => const Icon(
              Icons.cake_rounded,
              color: Color(0xFFE4C050),
            ),
          ),
        ),
      );
    }

    return Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: goldenColor.withOpacity(0.16),
        border: Border.all(
          color: goldenColor.withOpacity(0.35),
        ),
      ),
      child: const Icon(
        Icons.cake_rounded,
        color: Color(0xFFE4C050),
      ),
    );
  }

  String? _extractImageUrl(BirthdayPerson person) {
    try {
      final dynamic p = person;
      final possibleUrl = p.avatarUrl ??
          p.photoUrl ??
          p.avatar ??
          p.imageUrl ??
          p.profileImageUrl;

      if (possibleUrl is String && possibleUrl.trim().isNotEmpty) {
        return possibleUrl.trim();
      }
    } catch (_) {}

    return null;
  }

  String _monthName(int month) {
    const months = [
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

    return months[month];
  }
}
