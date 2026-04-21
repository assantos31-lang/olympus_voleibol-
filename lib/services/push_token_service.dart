import 'dart:async';
import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:package_info_plus/package_info_plus.dart';

class PushTokenService {
  PushTokenService._();

  static final PushTokenService instance = PushTokenService._();

  final SupabaseClient _supabase = Supabase.instance.client;
  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  final Uuid _uuid = const Uuid();

  StreamSubscription<String>? _tokenRefreshSub;
  bool _initialized = false;

  static const String _installationIdKey = 'push_installation_id';

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    debugPrint('[PushTokenService] init()');

    await _configureForegroundPresentation();
    _listenTokenRefresh();
    await syncCurrentUserTokenIfPossible();
  }

  Future<void> _configureForegroundPresentation() async {
    if (Platform.isIOS) {
      await _messaging.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );
      debugPrint('[PushTokenService] iOS foreground OK');
    }
  }

  void _listenTokenRefresh() {
    _tokenRefreshSub?.cancel();

    _tokenRefreshSub = _messaging.onTokenRefresh.listen((token) async {
      debugPrint('[PushTokenService] 🔁 token refresh');

      try {
        // 🔥 BLOQUEIO CRÍTICO PARA iOS
        if (Platform.isIOS) {
          final apns = await _messaging.getAPNSToken();

          if (apns == null || apns.isEmpty) {
            debugPrint('[PushTokenService] ❌ refresh ignorado (sem APNS)');
            return;
          }
        }

        await _upsertToken(token);
      } catch (e, st) {
        debugPrint('[PushTokenService] ERRO refresh: $e');
        debugPrintStack(stackTrace: st);
      }
    });
  }

  Future<String> _getOrCreateInstallationId() async {
    final existing = await _storage.read(key: _installationIdKey);

    if (existing != null && existing.isNotEmpty) {
      return existing;
    }

    final newId = _uuid.v4();
    await _storage.write(key: _installationIdKey, value: newId);

    debugPrint('[PushTokenService] installation_id criado: $newId');

    return newId;
  }

  Future<NotificationSettings> requestPermissionIfNeeded() async {
    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );

    debugPrint(
      '[PushTokenService] permission: ${settings.authorizationStatus}',
    );

    return settings;
  }

  Future<String?> _obtainTokenRobustly() async {
    if (Platform.isIOS) {
      for (int attempt = 1; attempt <= 12; attempt++) {
        final apnsToken = await _messaging.getAPNSToken();

        debugPrint(
          '[PushTokenService] iOS tentativa $attempt | apns=${apnsToken != null}',
        );

        if (apnsToken != null && apnsToken.isNotEmpty) {
          final fcmToken = await _messaging.getToken();

          debugPrint(
            '[PushTokenService] iOS tentativa $attempt | fcm=${fcmToken != null}',
          );

          if (fcmToken != null && fcmToken.isNotEmpty) {
            return fcmToken;
          }
        }

        await Future.delayed(const Duration(seconds: 2));
      }

      return null;
    }

    final token = await _messaging.getToken();

    debugPrint(
      '[PushTokenService] Android token obtido: ${token != null}',
    );

    return token;
  }

  Future<void> syncCurrentUserTokenIfPossible() async {
    final user = _supabase.auth.currentUser;

    if (user == null) {
      debugPrint('[PushTokenService] sem user');
      return;
    }

    debugPrint('[PushTokenService] sync user=${user.id}');

    final permission = await requestPermissionIfNeeded();
    final token = await _obtainTokenRobustly();

    if (token == null || token.isEmpty) {
      debugPrint('[PushTokenService] token NULL ❌');
      return;
    }

    await _upsertToken(
      token,
      permissionStatus: permission.authorizationStatus.name,
    );
  }

  Future<void> _upsertToken(
    String token, {
    String? permissionStatus,
  }) async {
    final user = _supabase.auth.currentUser;

    if (user == null) {
      debugPrint('[PushTokenService] sem user no upsert ❌');
      return;
    }

    final installationId = await _getOrCreateInstallationId();
    final now = DateTime.now().toUtc().toIso8601String();

    final packageInfo = await PackageInfo.fromPlatform();
    final version = '${packageInfo.version}+${packageInfo.buildNumber}';

    final payload = {
      'installation_id': installationId,
      'user_id': user.id,
      'device_token': token,
      'platform': Platform.isIOS ? 'ios' : 'android',
      'permission_status': permissionStatus,
      'last_seen_at': now,
      'updated_at': now,
      'app_version': version,
    };

    debugPrint('[PushTokenService] UPSERT...');
    debugPrint(payload.toString());

    try {
      await _supabase
          .from('user_push_tokens')
          .upsert(payload, onConflict: 'installation_id');

      debugPrint('[PushTokenService] ✅ salvo');
    } catch (e, st) {
      debugPrint('[PushTokenService] ❌ erro upsert: $e');
      debugPrintStack(stackTrace: st);
    }
  }

  Future<void> syncAfterLogin() async {
    debugPrint('[PushTokenService] syncAfterLogin');
    await syncCurrentUserTokenIfPossible();
  }

  Future<void> clearUserOnLogout() async {
    final installationId = await _getOrCreateInstallationId();
    final now = DateTime.now().toUtc().toIso8601String();

    try {
      await _supabase.from('user_push_tokens').update({
        'user_id': null,
        'updated_at': now,
        'last_seen_at': now,
      }).eq('installation_id', installationId);

      debugPrint('[PushTokenService] logout OK');
    } catch (e, st) {
      debugPrint('[PushTokenService] erro logout: $e');
      debugPrintStack(stackTrace: st);
    }
  }

  Future<Map<String, dynamic>> getDebugInfo() async {
    final user = _supabase.auth.currentUser;
    final installationId = await _getOrCreateInstallationId();
    final permission = await _messaging.getNotificationSettings();

    String? apnsToken;
    String? fcmToken;
    String? tokenError;

    if (Platform.isIOS) {
      apnsToken = await _messaging.getAPNSToken();

      if (apnsToken != null && apnsToken.isNotEmpty) {
        try {
          fcmToken = await _messaging.getToken();
        } catch (e) {
          tokenError = e.toString();
        }
      } else {
        tokenError = 'APNS token ainda não disponível no device';
      }
    } else {
      try {
        fcmToken = await _messaging.getToken();
      } catch (e) {
        tokenError = e.toString();
      }
    }

    return {
      'user_id': user?.id,
      'platform': Platform.isIOS ? 'ios' : 'android',
      'installation_id': installationId,
      'permission': permission.authorizationStatus.name,
      'fcm_token': fcmToken,
      'fcm_token_exists': fcmToken != null,
      'apns_token_exists': apnsToken != null,
      'token_error': tokenError,
    };
  }

  Future<String> forceSyncForDebug() async {
    try {
      await syncCurrentUserTokenIfPossible();
      return 'SYNC_OK';
    } catch (e, st) {
      debugPrint('[PushTokenService] erro debug: $e');
      debugPrintStack(stackTrace: st);
      return 'SYNC_ERROR: $e';
    }
  }

  Future<void> dispose() async {
    await _tokenRefreshSub?.cancel();
    _tokenRefreshSub = null;
    _initialized = false;
  }
}
