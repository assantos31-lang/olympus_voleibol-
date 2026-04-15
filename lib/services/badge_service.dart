import 'package:app_badge_plus/app_badge_plus.dart';
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
        total += ((row['unread_count'] ?? 0) as num).toInt();
      }

      final supported = await AppBadgePlus.isSupported();
      if (!supported) return;

      await AppBadgePlus.updateBadge(total);
    } catch (e) {
      print('Erro ao atualizar badge: $e');
    }
  }

  static Future<void> clearBadge() async {
    try {
      final supported = await AppBadgePlus.isSupported();
      if (!supported) return;

      await AppBadgePlus.updateBadge(0);
    } catch (e) {
      print('Erro ao limpar badge: $e');
    }
  }
}
