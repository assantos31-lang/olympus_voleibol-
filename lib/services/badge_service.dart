import 'package:app_badge_plus/app_badge_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'chat_service.dart';

class BadgeService {
  static final SupabaseClient _supabase = Supabase.instance.client;

  static Future<void> updateBadge() async {
    final user = _supabase.auth.currentUser;

    if (user == null) {
      await clearBadge();
      return;
    }

    try {
      final response = await _supabase
          .from('app_message_participants')
          .select('unread_count')
          .eq('user_id', user.id);

      final rows = List<Map<String, dynamic>>.from(response);

      int total = 0;

      for (final row in rows) {
        total += ((row['unread_count'] ?? 0) as num).toInt();
      }

      final chatUnread = await ChatService().getTotalUnreadCount();
      await setBadge(total + chatUnread);
    } catch (e, st) {
      debugPrint('[BadgeService] Erro ao atualizar badge: $e');
      debugPrintStack(stackTrace: st);
    }
  }

  static Future<void> setBadge(int count) async {
    try {
      final supported = await AppBadgePlus.isSupported();

      if (!supported) {
        debugPrint('[BadgeService] Badge nao suportado neste aparelho');
        return;
      }

      if (count <= 0) {
        await AppBadgePlus.updateBadge(0);
        return;
      }

      await AppBadgePlus.updateBadge(count);
      debugPrint('[BadgeService] Badge atualizado: $count');
    } catch (e, st) {
      debugPrint('[BadgeService] Erro ao definir badge: $e');
      debugPrintStack(stackTrace: st);
    }
  }

  static Future<void> clearBadge() async {
    try {
      final supported = await AppBadgePlus.isSupported();

      if (!supported) {
        debugPrint('[BadgeService] Badge nao suportado neste aparelho');
        return;
      }

      await AppBadgePlus.updateBadge(0);
      debugPrint('[BadgeService] Badge limpo');
    } catch (e, st) {
      debugPrint('[BadgeService] Erro ao limpar badge: $e');
      debugPrintStack(stackTrace: st);
    }
  }
}
