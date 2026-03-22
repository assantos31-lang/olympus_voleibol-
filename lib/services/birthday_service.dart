import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/birthday_person.dart';

class BirthdayService {
  final SupabaseClient _supabase = Supabase.instance.client;

  Future<List<BirthdayPerson>> getAllBirthdays() async {
    final response = await _supabase
        .from('profiles')
        .select('id, full_name, birth_date, user_type, avatar_url, gender')
        .not('birth_date', 'is', null)
        .neq('user_type', 'admin');

    final list = (response as List)
        .map(
          (item) => BirthdayPerson.fromMap(
            item as Map<String, dynamic>,
          ),
        )
        .toList();

    list.sort((a, b) => a.daysUntilBirthday.compareTo(b.daysUntilBirthday));
    return list;
  }

  Future<List<BirthdayPerson>> getBirthdaysOfMonth() async {
    final all = await getAllBirthdays();
    final monthBirthdays = all.where((p) => p.isBirthdayMonth).toList();

    monthBirthdays.sort((a, b) {
      if (a.birthDate.day != b.birthDate.day) {
        return a.birthDate.day.compareTo(b.birthDate.day);
      }
      return a.fullName.compareTo(b.fullName);
    });

    return monthBirthdays;
  }
}
