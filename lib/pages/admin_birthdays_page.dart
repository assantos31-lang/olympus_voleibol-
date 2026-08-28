import 'package:flutter/material.dart';
import '../theme/olympus_theme.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'dart:ui';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/permission_service.dart';

class AdminBirthdaysPage extends StatefulWidget {
  const AdminBirthdaysPage({super.key});

  @override
  State<AdminBirthdaysPage> createState() => _AdminBirthdaysPageState();
}

class _AdminBirthdaysPageState extends State<AdminBirthdaysPage> {
  final supabase = Supabase.instance.client;
  final PermissionService _permissionService = PermissionService();

  List<Map<String, dynamic>> users = [];
  bool isLoading = true;
  bool _checkingPermission = true;
  bool _hasPermission = false;

  static const Color olympusBlue = Color(0xFF1E3A5F);
  static const Color olympusGold = Color(0xFFD4AF37);
  static const Color olympusLightBlue = Color(0xFF2C5F8D);

  @override
  void initState() {
    super.initState();
    _checkPermission();
  }

  Future<void> _checkPermission() async {
    final user = supabase.auth.currentUser;

    if (user == null) {
      if (mounted) {
        Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
      }
      return;
    }

    final hasAccess = await _permissionService.hasAccess(user.id, 'birthdays');

    if (!mounted) return;

    setState(() {
      _hasPermission = hasAccess;
      _checkingPermission = false;
    });

    if (hasAccess) {
      fetchUsers();
    }
  }

  Future<void> fetchUsers() async {
    try {
      setState(() => isLoading = true);

      final response = await supabase
          .from('profiles')
          .select('full_name, birth_date, avatar_url, court_position, gender')
          .eq('is_active', true)
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

  DateTime? _parseBirthDate(dynamic value) {
    final rawValue = value?.toString().trim();
    if (rawValue == null || rawValue.isEmpty) return null;
    return DateTime.tryParse(rawValue);
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
      if (birth == null) continue;

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

    final currentMonth = DateTime.now().month;
    final sortedEntries = grouped.entries.toList()
      ..sort((a, b) {
        final aOffset = (a.key - currentMonth + 12) % 12;
        final bOffset = (b.key - currentMonth + 12) % 12;
        return aOffset.compareTo(bOffset);
      });

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

  Color _baseCardColorByGender(String? gender) {
    final normalized = (gender ?? '').trim().toLowerCase();
    if (normalized == 'masculino') {
      return const Color(0xFF243F56);
    }
    if (normalized == 'feminino') {
      return const Color(0xFF624154);
    }
    return Colors.white;
  }

  Color _cardTextColorByGender(String? gender) {
    final normalized = (gender ?? '').trim().toLowerCase();
    if (normalized == 'masculino' || normalized == 'feminino') {
      return Colors.white;
    }
    return olympusBlue;
  }

  Color _cardSubtleTextColorByGender(String? gender) {
    final normalized = (gender ?? '').trim().toLowerCase();
    if (normalized == 'masculino' || normalized == 'feminino') {
      return Colors.white.withOpacity(0.88);
    }
    return Colors.grey[700]!;
  }

  String? _resolveAvatarUrl(String? rawValue) {
    final value = rawValue?.trim();
    if (value == null || value.isEmpty) return null;
    if (value.startsWith('http://') || value.startsWith('https://')) {
      return value;
    }
    return supabase.storage.from('avatars').getPublicUrl(value);
  }

  Widget _buildAvatar(String? rawAvatarUrl, String fullName) {
    final avatarUrl = _resolveAvatarUrl(rawAvatarUrl);
    final fallback = Container(
      color: olympusGold.withOpacity(0.18),
      alignment: Alignment.center,
      child: Text(
        fullName.isNotEmpty ? fullName[0].toUpperCase() : '?',
        style: const TextStyle(
          fontWeight: FontWeight.bold,
          color: olympusBlue,
        ),
      ),
    );

    return Container(
      width: 52,
      height: 52,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: olympusGold.withOpacity(0.55), width: 1.4),
      ),
      child: avatarUrl == null
          ? fallback
          : CachedNetworkImage(
              imageUrl: avatarUrl,
              fit: BoxFit.cover,
              memCacheWidth: 240,
              memCacheHeight: 240,
              fadeInDuration: const Duration(milliseconds: 120),
              placeholder: (_, __) => fallback,
              errorWidget: (_, __, ___) => fallback,
            ),
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
    final String gender = (user['gender'] ?? '').toString();

    final baseColor = _baseCardColorByGender(gender);
    final titleColor = _cardTextColorByGender(gender);
    final bodyColor = _cardSubtleTextColorByGender(gender);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            decoration: BoxDecoration(
              color: baseColor.withOpacity(0.35),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: _cardBorderColor(birthDate),
                width: 1.1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
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
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: titleColor,
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
                        color: bodyColor,
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
                            ? Colors.green[100]
                            : isBirthdayThisWeek(birthDate)
                                ? const Color(0xFFFFE0B2)
                                : bodyColor,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Posição: $positionLabel',
                      style: TextStyle(
                        color: bodyColor,
                        fontSize: 13.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMonthSection(int month, List<Map<String, dynamic>> monthUsers) {
    final isCurrentMonth = month == DateTime.now().month;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          margin: const EdgeInsets.fromLTRB(16, 20, 16, 8),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: isCurrentMonth
                ? olympusGold.withOpacity(0.20)
                : Colors.white.withOpacity(0.10),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isCurrentMonth
                  ? olympusGold.withOpacity(0.78)
                  : Colors.white.withOpacity(0.18),
              width: isCurrentMonth ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                isCurrentMonth
                    ? Icons.celebration_rounded
                    : Icons.cake_outlined,
                color: isCurrentMonth ? olympusGold : Colors.white,
                size: 22,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  getMonthName(month),
                  style: TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w800,
                    color: isCurrentMonth ? olympusGold : Colors.white,
                  ),
                ),
              ),
              if (isCurrentMonth)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: olympusGold,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Text(
                    'Mês atual',
                    style: TextStyle(
                      color: olympusBlue,
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                )
              else
                Text(
                  '${monthUsers.length}',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: Colors.white70,
                  ),
                ),
            ],
          ),
        ),
        ...monthUsers.map(_buildBirthdayCard),
      ],
    );
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
          child: Container(
            color: Colors.black.withOpacity(0.14),
          ),
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

  Widget _buildAccessDeniedScreen() {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Aniversariantes'),
        backgroundColor: olympusBlue,
        foregroundColor: Colors.white,
      ),
      body: Stack(
        children: [
          Positioned.fill(child: _buildPremiumBackground()),
          Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                  child: Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.16),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.22),
                      ),
                    ),
                    child: Text(
                      'Você não tem permissão para acessar esta página.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 16,
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_checkingPermission) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (!_hasPermission) {
      return _buildAccessDeniedScreen();
    }

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
      body: Stack(
        children: [
          Positioned.fill(child: _buildPremiumBackground()),
          isLoading
              ? const Center(child: CircularProgressIndicator())
              : grouped.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(20),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                            child: Container(
                              padding: const EdgeInsets.all(24),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.16),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: Colors.white.withOpacity(0.22),
                                ),
                              ),
                              child: const Text(
                                'Nenhum aniversariante com data cadastrada.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.only(bottom: 20),
                      children: grouped.entries
                          .map((entry) =>
                              _buildMonthSection(entry.key, entry.value))
                          .toList(),
                    ),
        ],
      ),
    );
  }
}
