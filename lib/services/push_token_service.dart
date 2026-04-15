import 'dart:async';
import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
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
      debugPrint('[PushTokenService] iOS foreground presentation configurado');
    }
  }

  void _listenTokenRefresh() {
    _tokenRefreshSub?.cancel();

    _tokenRefreshSub = _messaging.onTokenRefresh.listen((token) async {
      debugPrint('[PushTokenService] onTokenRefresh disparou');
      try {
        await _upsertToken(token);
      } catch (e, st) {
        debugPrint('[PushTokenService] erro no onTokenRefresh: $e');
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
      '[PushTokenService] authorizationStatus: ${settings.authorizationStatus}',
    );

    return settings;
  }

  Future<String?> _obtainTokenRobustly() async {
    if (Platform.isIOS) {
      for (int attempt = 1; attempt <= 8; attempt++) {
        final apnsToken = await _messaging.getAPNSToken();
        final fcmToken = await _messaging.getToken();

        debugPrint(
          '[PushTokenService] tentativa iOS $attempt | apnsToken=${apnsToken != null} | fcmToken=${fcmToken != null && fcmToken.isNotEmpty}',
        );

        if (apnsToken != null && fcmToken != null && fcmToken.isNotEmpty) {
          return fcmToken;
        }

        await Future.delayed(const Duration(seconds: 2));
      }

      return null;
    }

    final token = await _messaging.getToken();
    debugPrint(
      '[PushTokenService] token Android obtido: ${token != null && token.isNotEmpty}',
    );
    return token;
  }

  Future<void> syncCurrentUserTokenIfPossible() async {
    final user = _supabase.auth.currentUser;
    if (user == null) {
      debugPrint('[PushTokenService] sem usuário logado, sync ignorado');
      return;
    }

    final permission = await requestPermissionIfNeeded();
    final token = await _obtainTokenRobustly();

    if (token == null || token.isEmpty) {
      debugPrint('[PushTokenService] token indisponível, nada a salvar');
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
      debugPrint('[PushTokenService] _upsertToken abortado: sem usuário');
      return;
    }

    final installationId = await _getOrCreateInstallationId();
    final now = DateTime.now().toUtc().toIso8601String();

    final payload = {
      'installation_id': installationId,
      'user_id': user.id,
      'device_token': token,
      'platform': Platform.isIOS ? 'ios' : 'android',
      'permission_status': permissionStatus,
      'last_seen_at': now,
      'updated_at': now,
    };

    debugPrint('[PushTokenService] salvando token...');
    debugPrint('[PushTokenService] user_id=${user.id}');
    debugPrint('[PushTokenService] installation_id=$installationId');
    debugPrint('[PushTokenService] platform=${payload['platform']}');

    await _supabase
        .from('user_push_tokens')
        .upsert(payload, onConflict: 'installation_id');

    debugPrint('[PushTokenService] token salvo com sucesso');
  }

  Future<void> syncAfterLogin() async {
    debugPrint('[PushTokenService] syncAfterLogin()');
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

      debugPrint('[PushTokenService] instalação desvinculada no logout');
    } catch (e, st) {
      debugPrint('[PushTokenService] erro no logout: $e');
      debugPrintStack(stackTrace: st);
    }
  }

  Future<void> dispose() async {
    await _tokenRefreshSub?.cancel();
    _tokenRefreshSub = null;
    _initialized = false;
  }
}
