import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AdminBirthdaysPage extends StatefulWidget {
  const AdminBirthdaysPage({super.key});

  @override
  State<AdminBirthdaysPage> createState() => _AdminBirthdaysPageState();
}

class _AdminBirthdaysPageState extends State<AdminBirthdaysPage> {
  final supabase = Supabase.instance.client;

  List<Map<String, dynamic>> users = [];
  bool isLoading = true;

  static const Color olympusBlue = Color(0xFF1E3A5F);
  static const Color olympusGold = Color(0xFFD4AF37);
  static const Color olympusLightBlue = Color(0xFF2C5F8D);

  @override
  void initState() {
    super.initState();
    fetchUsers();
  }

  Future<void> fetchUsers() async {
    try {
      setState(() => isLoading = true);

      final response = await supabase
          .from('profiles')
          .select('full_name, birth_date, avatar_url, court_position')
          .not('birth_date', 'is', null);

      final fetchedUsers = List<Map<String, dynamic>>.from(response);

      fetchedUsers.removeWhere((user) {
        final birthDate = user['birth_date'];
        return birthDate == null || birthDate.toString().trim().isEmpty;
      });

      setState(() {
        users = fetchedUsers;
        isLoading = false;
      });
    } catch (e) {
      debugPrint('Erro ao buscar aniversariantes: $e');
      if (mounted) {
        setState(() => isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao carregar aniversariantes: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  DateTime _normalizeDate(DateTime date) {
    return DateTime(date.year, date.month, date.day);
  }

  DateTime _parseBirthDate(dynamic value) {
    return DateTime.parse(value.toString());
  }

  int calculateAge(DateTime birthDate) {
    final today = _normalizeDate(DateTime.now());
    int age = today.year - birthDate.year;

    if (today.month < birthDate.month ||
        (today.month == birthDate.month && today.day < birthDate.day)) {
      age--;
    }

    return age;
  }

  int daysUntilNextBirthday(DateTime birthDate) {
    final today = _normalizeDate(DateTime.now());
    DateTime nextBirthday =
        DateTime(today.year, birthDate.month, birthDate.day);

    if (nextBirthday.isBefore(today)) {
      nextBirthday = DateTime(today.year + 1, birthDate.month, birthDate.day);
    }

    return nextBirthday.difference(today).inDays;
  }

  bool isBirthdayToday(DateTime birthDate) {
    final today = DateTime.now();
    return today.day == birthDate.day && today.month == birthDate.month;
  }

  bool isBirthdayThisWeek(DateTime birthDate) {
    final days = daysUntilNextBirthday(birthDate);
    return days > 0 && days <= 7;
  }

  String formatBirthdayDay(DateTime birthDate) {
    return DateFormat('dd/MM').format(birthDate);
  }

  String formatPosition(String? position) {
    if (position == null || position.trim().isEmpty) {
      return 'Não informado';
    }
    return position;
  }

  Map<int, List<Map<String, dynamic>>> groupByMonth() {
    final Map<int, List<Map<String, dynamic>>> grouped = {};

    for (final originalUser in users) {
      final user = Map<String, dynamic>.from(originalUser);
      final birth = _parseBirthDate(user['birth_date']);

      user['age'] = calculateAge(birth);
      user['days'] = daysUntilNextBirthday(birth);
      user['birth'] = birth;
      user['birthday_label'] = formatBirthdayDay(birth);
      user['position_label'] =
          formatPosition(user['court_position']?.toString());

      grouped.putIfAbsent(birth.month, () => []).add(user);
    }

    for (final month in grouped.keys) {
      grouped[month]!.sort((a, b) {
        final daysComparison = (a['days'] as int).compareTo(b['days'] as int);
        if (daysComparison != 0) return daysComparison;
        return (a['full_name'] ?? '').toString().compareTo(
              (b['full_name'] ?? '').toString(),
            );
      });
    }

    final sortedEntries = grouped.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    return {for (final entry in sortedEntries) entry.key: entry.value};
  }

  String getMonthName(int month) {
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

  Color _cardBackgroundColor(DateTime birthDate) {
    if (isBirthdayToday(birthDate)) {
      return Colors.green.withOpacity(0.12);
    }
    if (isBirthdayThisWeek(birthDate)) {
      return Colors.orange.withOpacity(0.12);
    }
    return Colors.white;
  }

  Color _cardBorderColor(DateTime birthDate) {
    if (isBirthdayToday(birthDate)) {
      return Colors.green.withOpacity(0.45);
    }
    if (isBirthdayThisWeek(birthDate)) {
      return Colors.orange.withOpacity(0.45);
    }
    return olympusGold.withOpacity(0.18);
  }

  Widget _buildAvatar(String? avatarUrl, String fullName) {
    final hasAvatar = avatarUrl != null && avatarUrl.trim().isNotEmpty;

    return CircleAvatar(
      radius: 26,
      backgroundColor: olympusGold.withOpacity(0.18),
      backgroundImage: hasAvatar ? NetworkImage(avatarUrl) : null,
      child: !hasAvatar
          ? Text(
              fullName.isNotEmpty ? fullName[0].toUpperCase() : '?',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: olympusBlue,
              ),
            )
          : null,
    );
  }

  Widget _buildBirthdayCard(Map<String, dynamic> user) {
    final DateTime birthDate = user['birth'] as DateTime;
    final int age = user['age'] as int;
    final int days = user['days'] as int;
    final String fullName = (user['full_name'] ?? 'Sem nome').toString();
    final String avatarUrl = (user['avatar_url'] ?? '').toString();
    final String birthdayLabel = (user['birthday_label'] ?? '').toString();
    final String positionLabel =
        (user['position_label'] ?? 'Não informado').toString();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: _cardBackgroundColor(birthDate),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _cardBorderColor(birthDate),
          width: 1.1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        leading: _buildAvatar(avatarUrl, fullName),
        title: Text(
          fullName,
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            color: olympusBlue,
            fontSize: 16,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Aniversário: $birthdayLabel',
                style: TextStyle(
                  color: Colors.grey[800],
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                isBirthdayToday(birthDate)
                    ? 'Idade: $age - Hoje é dia de comemorar a vida!'
                    : 'Idade: $age - ${days == 1 ? 'Falta 1 dia para comemorar a vida!' : 'Faltam $days dias para comemorar a vida!'}',
                style: TextStyle(
                  color: isBirthdayToday(birthDate)
                      ? Colors.green[700]
                      : isBirthdayThisWeek(birthDate)
                          ? Colors.orange[800]
                          : Colors.grey[700],
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Posição: $positionLabel',
                style: TextStyle(
                  color: Colors.grey[700],
                  fontSize: 13.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMonthSection(int month, List<Map<String, dynamic>> monthUsers) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
          child: Row(
            children: [
              const Icon(Icons.cake_outlined, color: olympusGold, size: 20),
              const SizedBox(width: 8),
              Text(
                getMonthName(month),
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: olympusBlue,
                ),
              ),
            ],
          ),
        ),
        ...monthUsers.map(_buildBirthdayCard),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final grouped = groupByMonth();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Aniversariantes'),
        backgroundColor: olympusBlue,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            onPressed: fetchUsers,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : grouped.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'Nenhum aniversariante com data cadastrada.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.grey[700],
                      ),
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.only(bottom: 20),
                  children: grouped.entries
                      .map(
                          (entry) => _buildMonthSection(entry.key, entry.value))
                      .toList(),
                ),
    );
  }
}
