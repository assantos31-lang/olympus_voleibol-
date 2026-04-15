import 'package:flutter_app_badger/flutter_app_badger.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class BadgeService {
  static final _supabase = Supabase.instance.client;

  static Future<void> updateBadge() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    try {
      final response = await _supabase
          .from('app_message_participants')
          .select('unread_count')
          .eq('user_id', user.id);

      int total = 0;

      for (final row in response) {
        total += (row['unread_count'] ?? 0) as int;
      }

      if (total > 0) {
        FlutterAppBadger.updateBadgeCount(total);
      } else {
        FlutterAppBadger.removeBadge();
      }
    } catch (e) {
      print('Erro ao atualizar badge: $e');
    }
  }
}
