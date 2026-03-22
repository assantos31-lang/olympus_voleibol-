import 'dart:ui';
import 'package:flutter/material.dart';
import '../models/birthday_person.dart';
import '../services/birthday_service.dart';

class AdminBirthdaysPage extends StatefulWidget {
  const AdminBirthdaysPage({super.key});

  @override
  State<AdminBirthdaysPage> createState() => _AdminBirthdaysPageState();
}

class _AdminBirthdaysPageState extends State<AdminBirthdaysPage> {
  String _selectedGenderFilter = 'all';

  @override
  Widget build(BuildContext context) {
    const goldenColor = Color(0xFFE4C050);
    const cyanColor = Color(0xFF8FE8FF);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Aniversariantes'),
        backgroundColor: const Color(0xFF1E3A5F),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Stack(
        children: [
          IgnorePointer(
            child: Stack(
              children: [
                Positioned.fill(
                  child: Opacity(
                    opacity: 0.78,
                    child: Image.asset(
                      'assets/images/monte_olimpo.png',
                      fit: BoxFit.cover,
                      alignment: Alignment.topCenter,
                      filterQuality: FilterQuality.high,
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
              ],
            ),
          ),
          FutureBuilder<List<BirthdayPerson>>(
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
                    textAlign: TextAlign.center,
                  ),
                );
              }

              final people = snapshot.data ?? [];

              if (people.isEmpty) {
                return Center(
                  child: Text(
                    'Nenhum aniversariante encontrado.',
                    style: TextStyle(color: Colors.white.withOpacity(0.85)),
                    textAlign: TextAlign.center,
                  ),
                );
              }

              final availableGenders = _availableGenders(people);
              final filteredPeople = people.where((person) {
                if (_selectedGenderFilter == 'all') return true;
                return person.normalizedGender == _selectedGenderFilter;
              }).toList();

              if (filteredPeople.isEmpty) {
                return Column(
                  children: [
                    _buildFilterBar(availableGenders),
                    Expanded(
                      child: Center(
                        child: Text(
                          'Nenhum aniversariante encontrado para este filtro.',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.85),
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  ],
                );
              }

              final Map<int, List<BirthdayPerson>> groupedByMonth = {};
              for (final person in filteredPeople) {
                groupedByMonth.putIfAbsent(person.birthDate.month, () => []);
                groupedByMonth[person.birthDate.month]!.add(person);
              }

              final groupedEntries = groupedByMonth.entries.toList()
                ..sort((a, b) => a.key.compareTo(b.key));

              return LayoutBuilder(
                builder: (context, constraints) {
                  final isMobile = constraints.maxWidth < 600;
                  final horizontalPadding = isMobile ? 12.0 : 16.0;

                  return ListView(
                    padding: EdgeInsets.fromLTRB(
                      horizontalPadding,
                      12,
                      horizontalPadding,
                      16,
                    ),
                    children: [
                      _buildFilterBar(availableGenders),
                      const SizedBox(height: 12),
                      ...groupedEntries.map((entry) {
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
                                style: TextStyle(
                                  color: goldenColor,
                                  fontSize: isMobile ? 17 : 19,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            ...monthPeople.map(
                              (person) => _buildBirthdayCard(
                                person: person,
                                goldenColor: goldenColor,
                                cyanColor: cyanColor,
                                isMobile: isMobile,
                              ),
                            ),
                          ],
                        );
                      }),
                    ],
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar(List<String> genders) {
    final items = <Map<String, String>>[
      {'value': 'all', 'label': 'Todos'},
      ...genders.map(
        (gender) => {
          'value': gender,
          'label': _genderLabel(gender),
        },
      ),
    ];

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: Colors.white.withOpacity(0.14),
        ),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withOpacity(0.13),
            Colors.white.withOpacity(0.06),
          ],
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Filtrar por gênero',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.92),
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 12),
              LayoutBuilder(
                builder: (context, constraints) {
                  final isNarrow = constraints.maxWidth < 380;
                  if (isNarrow) {
                    return Column(
                      children: items.map((item) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _buildFilterButton(
                            label: item['label']!,
                            value: item['value']!,
                            fullWidth: true,
                          ),
                        );
                      }).toList(),
                    );
                  }

                  return Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: items.map((item) {
                      return _buildFilterButton(
                        label: item['label']!,
                        value: item['value']!,
                      );
                    }).toList(),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFilterButton({
    required String label,
    required String value,
    bool fullWidth = false,
  }) {
    final selected = _selectedGenderFilter == value;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      width: fullWidth ? double.infinity : null,
      constraints:
          fullWidth ? null : const BoxConstraints(minWidth: 98, minHeight: 44),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: selected
            ? const LinearGradient(
                colors: [
                  Color(0xFFE4C050),
                  Color(0xFFF6D978),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : LinearGradient(
                colors: [
                  Colors.white.withOpacity(0.12),
                  Colors.white.withOpacity(0.06),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
        border: Border.all(
          color: selected
              ? const Color(0xFFE4C050)
              : Colors.white.withOpacity(0.18),
        ),
        boxShadow: selected
            ? [
                BoxShadow(
                  color: const Color(0xFFE4C050).withOpacity(0.24),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ]
            : [],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () {
            setState(() {
              _selectedGenderFilter = value;
            });
          },
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: fullWidth ? 14 : 16,
              vertical: 12,
            ),
            child: Row(
              mainAxisSize: fullWidth ? MainAxisSize.max : MainAxisSize.min,
              mainAxisAlignment: fullWidth
                  ? MainAxisAlignment.center
                  : MainAxisAlignment.center,
              children: [
                AnimatedOpacity(
                  duration: const Duration(milliseconds: 180),
                  opacity: selected ? 1 : 0,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Icon(
                      Icons.check_rounded,
                      size: 18,
                      color: selected
                          ? const Color(0xFF1E3A5F)
                          : Colors.transparent,
                    ),
                  ),
                ),
                Flexible(
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: selected
                          ? const Color(0xFF1E3A5F)
                          : Colors.white.withOpacity(0.96),
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBirthdayCard({
    required BirthdayPerson person,
    required Color goldenColor,
    required Color cyanColor,
    required bool isMobile,
  }) {
    final genderText = person.genderLabel;

    return Container(
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
          child: Padding(
            padding: EdgeInsets.all(isMobile ? 12 : 14),
            child: isMobile
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          _buildAvatar(
                            person,
                            goldenColor,
                            size: 54,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildTitleSection(
                              person: person,
                              genderText: genderText,
                              isMobile: isMobile,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _buildInfoText(person),
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: _buildAgeBadge(person.age, cyanColor),
                      ),
                    ],
                  )
                : Row(
                    children: [
                      _buildAvatar(
                        person,
                        goldenColor,
                        size: 62,
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildTitleSection(
                              person: person,
                              genderText: genderText,
                              isMobile: isMobile,
                            ),
                            const SizedBox(height: 8),
                            _buildInfoText(person),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      _buildAgeBadge(person.age, cyanColor),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildTitleSection({
    required BirthdayPerson person,
    required String? genderText,
    required bool isMobile,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          person.fullName,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: isMobile ? 15 : 16,
          ),
        ),
        if (genderText != null && genderText.isNotEmpty) ...[
          const SizedBox(height: 5),
          Text(
            genderText,
            style: TextStyle(
              color: Colors.white.withOpacity(0.72),
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildInfoText(BirthdayPerson person) {
    return Text(
      'Nascimento: ${person.formattedBirthday}  •  Faltam ${person.daysUntilBirthday} dia(s)',
      style: TextStyle(
        color: Colors.white.withOpacity(0.75),
        height: 1.35,
      ),
    );
  }

  Widget _buildAgeBadge(int age, Color cyanColor) {
    return Container(
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
        '$age anos',
        style: const TextStyle(
          color: Color(0xFF8FE8FF),
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildAvatar(
    BirthdayPerson person,
    Color goldenColor, {
    double size = 56,
  }) {
    final imageUrl = person.avatarUrl;

    if (imageUrl != null && imageUrl.isNotEmpty) {
      return Container(
        width: size,
        height: size,
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
            filterQuality: FilterQuality.high,
            gaplessPlayback: true,
            loadingBuilder: (context, child, progress) {
              if (progress == null) return child;
              return Container(
                color: goldenColor.withOpacity(0.08),
                alignment: Alignment.center,
                child: SizedBox(
                  width: size * 0.34,
                  height: size * 0.34,
                  child: const CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Color(0xFFE4C050),
                  ),
                ),
              );
            },
            errorBuilder: (_, __, ___) => Icon(
              Icons.cake_rounded,
              color: const Color(0xFFE4C050),
              size: size * 0.42,
            ),
          ),
        ),
      );
    }

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: goldenColor.withOpacity(0.16),
        border: Border.all(
          color: goldenColor.withOpacity(0.35),
        ),
      ),
      child: Icon(
        Icons.cake_rounded,
        color: const Color(0xFFE4C050),
        size: size * 0.42,
      ),
    );
  }

  List<String> _availableGenders(List<BirthdayPerson> people) {
    final genders = people
        .map((person) => person.normalizedGender)
        .whereType<String>()
        .toSet()
        .toList()
      ..sort();
    return genders;
  }

  String _genderLabel(String value) {
    switch (value) {
      case 'masculino':
        return 'Masculino';
      case 'feminino':
        return 'Feminino';
      default:
        return value.isEmpty
            ? 'Todos'
            : value[0].toUpperCase() + value.substring(1);
    }
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
