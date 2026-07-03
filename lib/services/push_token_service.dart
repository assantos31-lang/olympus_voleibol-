import 'dart:async';
import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

class PushTokenService {
  PushTokenService._();

  static final PushTokenService instance = PushTokenService._();

  final SupabaseClient _supabase = Supabase.instance.client;
  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  final Uuid _uuid = const Uuid();

  StreamSubscription<String>? _tokenRefreshSub;
  StreamSubscription<AuthState>? _authStateSub;
  bool _initialized = false;

  static const String _installationIdKey = 'push_installation_id';

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    debugPrint('[PushTokenService] init()');

    await _configureForegroundPresentation();
    _listenAuthChanges();
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

  void _listenAuthChanges() {
    _authStateSub?.cancel();

    _authStateSub = _supabase.auth.onAuthStateChange.listen((data) async {
      final event = data.event;
      final session = data.session;

      debugPrint(
        '[PushTokenService] auth change | event=$event | user=${session?.user.id}',
      );

      try {
        if (session?.user != null) {
          await syncCurrentUserTokenIfPossible();
          return;
        }

        if (event == AuthChangeEvent.signedOut) {
          await clearUserOnLogout();
        }
      } catch (e, st) {
        debugPrint('[PushTokenService] ERRO auth listener: $e');
        debugPrintStack(stackTrace: st);
      }
    });
  }

  void _listenTokenRefresh() {
    _tokenRefreshSub?.cancel();

    _tokenRefreshSub = _messaging.onTokenRefresh.listen((token) async {
      debugPrint('[PushTokenService] token refresh');

      try {
        if (Platform.isIOS) {
          final apns = await _messaging.getAPNSToken();

          if (apns == null || apns.isEmpty) {
            debugPrint('[PushTokenService] refresh ignorado sem APNS');
            return;
          }
        }

        final user = _supabase.auth.currentUser;
        if (user == null) {
          debugPrint('[PushTokenService] refresh ignorado sem user');
          return;
        }

        final permission = await _messaging.getNotificationSettings();

        await _upsertToken(
          token,
          permissionStatus: permission.authorizationStatus.name,
        );
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
          '[PushTokenService] iOS tentativa $attempt | apns=${apnsToken != null && apnsToken.isNotEmpty}',
        );

        if (apnsToken != null && apnsToken.isNotEmpty) {
          final fcmToken = await _messaging.getToken();

          debugPrint(
            '[PushTokenService] iOS tentativa $attempt | fcm=${fcmToken != null && fcmToken.isNotEmpty}',
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

    debugPrint('[PushTokenService] Android token obtido: ${token != null}');

    return token;
  }

  Future<void> syncCurrentUserTokenIfPossible() async {
    final user = _supabase.auth.currentUser;

    debugPrint('[PushTokenService] USER: ${user?.id}');

    if (user == null) {
      debugPrint('[PushTokenService] sem user');
      return;
    }

    debugPrint('[PushTokenService] sync user=${user.id}');

    final permission = await requestPermissionIfNeeded();

    debugPrint(
      '[PushTokenService] PERMISSION: ${permission.authorizationStatus}',
    );

    if (Platform.isIOS) {
      String? apns;

      for (int i = 1; i <= 10; i++) {
        apns = await _messaging.getAPNSToken();

        debugPrint('[PushTokenService] aguardando APNS tentativa $i');

        if (apns != null && apns.isNotEmpty) {
          debugPrint('[PushTokenService] APNS OK');
          break;
        }

        await Future.delayed(const Duration(seconds: 1));
      }

      if (apns == null || apns.isEmpty) {
        debugPrint('[PushTokenService] APNS nao disponivel, abortando sync');
        return;
      }
    }

    final token = await _obtainTokenRobustly();

    debugPrint('[PushTokenService] TOKEN: $token');

    if (token == null || token.isEmpty) {
      debugPrint('[PushTokenService] token null');
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
      debugPrint('[PushTokenService] sem user no upsert');
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

    debugPrint('[PushTokenService] vai salvar token');
    debugPrint('[PushTokenService] user no upsert: ${user.id}');
    debugPrint(payload.toString());

    try {
      await _supabase.rpc(
        'register_user_push_token',
        params: {
          'p_installation_id': installationId,
          'p_device_token': token,
          'p_platform': Platform.isIOS ? 'ios' : 'android',
          'p_permission_status': permissionStatus,
          'p_app_version': version,
        },
      );

      debugPrint('[PushTokenService] salvo via RPC');
    } catch (rpcError, rpcStack) {
      debugPrint(
          '[PushTokenService] erro RPC register_user_push_token: $rpcError');
      debugPrintStack(stackTrace: rpcStack);

      try {
        await _supabase
            .from('user_push_tokens')
            .upsert(payload, onConflict: 'installation_id');

        debugPrint('[PushTokenService] salvo via fallback upsert');
      } catch (e, st) {
        debugPrint('[PushTokenService] erro fallback upsert: $e');
        debugPrintStack(stackTrace: st);
      }
    }

    await _syncProfilePushToken(user.id, token);
  }

  Future<void> _syncProfilePushToken(String userId, String token) async {
    try {
      await _supabase.from('profiles').update({
        'push_token': token,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', userId);

      debugPrint('[PushTokenService] profiles.push_token atualizado');
    } catch (e, st) {
      debugPrint(
          '[PushTokenService] erro ao atualizar profiles.push_token: $e');
      debugPrintStack(stackTrace: st);
    }
  }

  Future<void> syncAfterLogin() async {
    debugPrint('[PushTokenService] syncAfterLogin');

    int attempts = 0;

    while (_supabase.auth.currentUser == null && attempts < 15) {
      await Future.delayed(const Duration(milliseconds: 400));
      attempts++;
    }

    final user = _supabase.auth.currentUser;

    if (user == null) {
      debugPrint('[PushTokenService] user ainda null');
      return;
    }

    debugPrint('[PushTokenService] user OK: ${user.id}');

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
        tokenError = 'APNS token ainda nao disponivel no device';
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
    await _authStateSub?.cancel();
    _tokenRefreshSub = null;
    _authStateSub = null;
    _initialized = false;
  }
}
