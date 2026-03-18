class BirthdayPerson {
  final String id;
  final String fullName;
  final DateTime birthDate;
  final String? userType;

  BirthdayPerson({
    required this.id,
    required this.fullName,
    required this.birthDate,
    this.userType,
  });

  factory BirthdayPerson.fromMap(Map<String, dynamic> map) {
    return BirthdayPerson(
      id: map['id'] as String,
      fullName: map['full_name'] as String? ?? '',
      birthDate: DateTime.parse(map['birth_date'] as String),
      userType: map['user_type'] as String?,
    );
  }

  int get age {
    final today = DateTime.now();
    int years = today.year - birthDate.year;
    final hadBirthdayThisYear = (today.month > birthDate.month) ||
        (today.month == birthDate.month && today.day >= birthDate.day);

    if (!hadBirthdayThisYear) years--;
    return years;
  }

  DateTime get nextBirthday {
    final today = DateTime.now();
    DateTime next = DateTime(today.year, birthDate.month, birthDate.day);

    if (next.isBefore(DateTime(today.year, today.month, today.day))) {
      next = DateTime(today.year + 1, birthDate.month, birthDate.day);
    }

    return next;
  }

  int get daysUntilBirthday {
    final today = DateTime.now();
    final startToday = DateTime(today.year, today.month, today.day);
    return nextBirthday.difference(startToday).inDays;
  }

  bool get isBirthdayMonth {
    final today = DateTime.now();
    return birthDate.month == today.month;
  }

  String get formattedBirthday {
    final d = birthDate.day.toString().padLeft(2, '0');
    final m = birthDate.month.toString().padLeft(2, '0');
    return '$d/$m';
  }
}
