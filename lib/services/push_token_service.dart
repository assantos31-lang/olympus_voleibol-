import 'dart:async';
import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'organization_context_service.dart';

class PushTokenService {
  PushTokenService._();

  static final PushTokenService instance = PushTokenService._();

  final SupabaseClient _supabase = Supabase.instance.client;
  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  final Uuid _uuid = const Uuid();

  StreamSubscription<String>? _tokenRefreshSub;
  StreamSubscription<AuthState>? _authStateSub;
  Future<void>? _syncInFlight;
  Timer? _retryTimer;
  bool _initialized = false;

  static const String _installationIdKey = 'push_installation_id';

  static void _debugLog(String? message, {int? wrapWidth}) {
    if (kDebugMode) {
      debugPrint(message, wrapWidth: wrapWidth);
    }
  }

  static void _debugStack({
    StackTrace? stackTrace,
    String? label,
    int? maxFrames,
  }) {
    if (kDebugMode) {
      debugPrintStack(
        stackTrace: stackTrace,
        label: label,
        maxFrames: maxFrames,
      );
    }
  }

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    _debugLog('[PushTokenService] init()');

    await _configureForegroundPresentation();
    _listenAuthChanges();
    _listenTokenRefresh();
    await syncCurrentUserTokenIfPossible();
  }

  Future<void> _configureForegroundPresentation() async {
    if (Platform.isIOS) {
      await _messaging.setForegroundNotificationPresentationOptions(
        // O app cria uma única notificação local em main.dart. Manter o alerta
        // automático ativo no iOS duplicava notificações em primeiro plano e
        // impedia ocultar o conteúdo quando a conversa já estava aberta.
        alert: false,
        badge: true,
        sound: false,
      );
      _debugLog('[PushTokenService] iOS foreground OK');
    }
  }

  void _listenAuthChanges() {
    _authStateSub?.cancel();

    _authStateSub = _supabase.auth.onAuthStateChange.listen((data) async {
      final event = data.event;
      final session = data.session;

      _debugLog(
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
        _debugLog('[PushTokenService] ERRO auth listener: $e');
        _debugStack(stackTrace: st);
      }
    });
  }

  void _listenTokenRefresh() {
    _tokenRefreshSub?.cancel();

    _tokenRefreshSub = _messaging.onTokenRefresh.listen((token) async {
      _debugLog('[PushTokenService] token refresh');

      try {
        if (Platform.isIOS) {
          final apns = await _messaging.getAPNSToken();

          if (apns == null || apns.isEmpty) {
            _debugLog('[PushTokenService] refresh ignorado sem APNS');
            _scheduleRetry();
            return;
          }
        }

        final user = _supabase.auth.currentUser;
        if (user == null) {
          _debugLog('[PushTokenService] refresh ignorado sem user');
          return;
        }

        final permission = await _messaging.getNotificationSettings();

        await _upsertToken(
          token,
          permissionStatus: permission.authorizationStatus.name,
        );
      } catch (e, st) {
        _debugLog('[PushTokenService] ERRO refresh: $e');
        _debugStack(stackTrace: st);
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

    _debugLog('[PushTokenService] installation_id criado: $newId');

    return newId;
  }

  Future<NotificationSettings> requestPermissionIfNeeded() async {
    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );

    _debugLog(
      '[PushTokenService] permission: ${settings.authorizationStatus}',
    );

    return settings;
  }

  Future<String?> _obtainTokenRobustly() async {
    if (Platform.isIOS) {
      for (int attempt = 1; attempt <= 12; attempt++) {
        final apnsToken = await _messaging.getAPNSToken();

        _debugLog(
          '[PushTokenService] iOS tentativa $attempt | apns=${apnsToken != null && apnsToken.isNotEmpty}',
        );

        if (apnsToken != null && apnsToken.isNotEmpty) {
          final fcmToken = await _messaging.getToken();

          _debugLog(
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

    _debugLog('[PushTokenService] Android token obtido: ${token != null}');

    return token;
  }

  Future<void> syncCurrentUserTokenIfPossible() {
    final running = _syncInFlight;
    if (running != null) return running;

    final operation = _syncCurrentUserToken();
    _syncInFlight = operation;
    return operation.whenComplete(() {
      if (identical(_syncInFlight, operation)) {
        _syncInFlight = null;
      }
    });
  }

  Future<void> _syncCurrentUserToken() async {
    final user = _supabase.auth.currentUser;

    _debugLog('[PushTokenService] USER: ${user?.id}');

    if (user == null) {
      _debugLog('[PushTokenService] sem user');
      return;
    }

    _debugLog('[PushTokenService] sync user=${user.id}');

    final permission = await requestPermissionIfNeeded();

    _debugLog(
      '[PushTokenService] PERMISSION: ${permission.authorizationStatus}',
    );

    if (Platform.isIOS) {
      String? apns;

      for (int i = 1; i <= 10; i++) {
        apns = await _messaging.getAPNSToken();

        _debugLog('[PushTokenService] aguardando APNS tentativa $i');

        if (apns != null && apns.isNotEmpty) {
          _debugLog('[PushTokenService] APNS OK');
          break;
        }

        await Future.delayed(const Duration(seconds: 1));
      }

      if (apns == null || apns.isEmpty) {
        _debugLog('[PushTokenService] APNS nao disponivel, abortando sync');
        _scheduleRetry();
        return;
      }
    }

    final token = await _obtainTokenRobustly();

    _debugLog(
      '[PushTokenService] token obtido: ${token != null && token.isNotEmpty}',
    );

    if (token == null || token.isEmpty) {
      _debugLog('[PushTokenService] token null');
      _scheduleRetry();
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
      _debugLog('[PushTokenService] sem user no upsert');
      return;
    }

    final installationId = await _getOrCreateInstallationId();
    final now = DateTime.now().toUtc().toIso8601String();

    final packageInfo = await PackageInfo.fromPlatform();
    final version = '${packageInfo.version}+${packageInfo.buildNumber}';

    final payload = {
      'installation_id': installationId,
      'user_id': user.id,
      'organization_id': OrganizationContextService.instance.currentId,
      'device_token': token,
      'platform': Platform.isIOS ? 'ios' : 'android',
      'permission_status': permissionStatus,
      'last_seen_at': now,
      'updated_at': now,
      'app_version': version,
    };

    _debugLog('[PushTokenService] vai salvar token');
    _debugLog('[PushTokenService] user no upsert: ${user.id}');
    _debugLog(
      '[PushTokenService] payload preparado | plataforma=${payload['platform']} | versao=${payload['app_version']}',
    );

    var tokenSaved = false;

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

      _debugLog('[PushTokenService] salvo via RPC');
      tokenSaved = true;
    } catch (rpcError, rpcStack) {
      _debugLog(
          '[PushTokenService] erro RPC register_user_push_token: $rpcError');
      _debugStack(stackTrace: rpcStack);

      try {
        await _supabase
            .from('user_push_tokens')
            .upsert(payload, onConflict: 'installation_id');

        _debugLog('[PushTokenService] salvo via fallback upsert');
        tokenSaved = true;
      } catch (e, st) {
        _debugLog('[PushTokenService] erro fallback upsert: $e');
        _debugStack(stackTrace: st);
      }
    }

    if (!tokenSaved) {
      _scheduleRetry();
      return;
    }

    _retryTimer?.cancel();
    _retryTimer = null;

    await _syncProfilePushToken(user.id, token);
  }

  void _scheduleRetry({Duration delay = const Duration(seconds: 30)}) {
    if (_retryTimer?.isActive == true) return;

    _retryTimer = Timer(delay, () {
      _retryTimer = null;
      unawaited(syncCurrentUserTokenIfPossible());
    });
    _debugLog('[PushTokenService] nova tentativa agendada');
  }

  Future<void> _syncProfilePushToken(String userId, String token) async {
    try {
      await _supabase.from('profiles').update({
        'push_token': token,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', userId);

      _debugLog('[PushTokenService] profiles.push_token atualizado');
    } catch (e, st) {
      _debugLog('[PushTokenService] erro ao atualizar profiles.push_token: $e');
      _debugStack(stackTrace: st);
    }
  }

  Future<void> syncAfterLogin() async {
    _debugLog('[PushTokenService] syncAfterLogin');

    int attempts = 0;

    while (_supabase.auth.currentUser == null && attempts < 15) {
      await Future.delayed(const Duration(milliseconds: 400));
      attempts++;
    }

    final user = _supabase.auth.currentUser;

    if (user == null) {
      _debugLog('[PushTokenService] user ainda null');
      return;
    }

    _debugLog('[PushTokenService] user OK: ${user.id}');

    await syncCurrentUserTokenIfPossible();
  }

  Future<void> clearUserOnLogout() async {
    final userId = _supabase.auth.currentUser?.id;
    final installationId = await _getOrCreateInstallationId();
    final now = DateTime.now().toUtc().toIso8601String();
    String? currentToken;

    try {
      currentToken = await _messaging.getToken();
    } catch (e) {
      _debugLog('[PushTokenService] token indisponível no logout: $e');
    }

    try {
      await _supabase
          .from('user_push_tokens')
          .delete()
          .eq('installation_id', installationId);

      _debugLog('[PushTokenService] logout OK');
    } catch (e, st) {
      _debugLog('[PushTokenService] erro logout: $e');
      _debugStack(stackTrace: st);
    }

    // Compatibilidade com instalações antigas que ainda consultam
    // profiles.push_token. A condição pelo token evita apagar o vínculo de
    // outro aparelho que continue conectado à mesma conta.
    if (userId != null && currentToken != null && currentToken.isNotEmpty) {
      try {
        await _supabase
            .from('profiles')
            .update({
              'push_token': null,
              'updated_at': now,
            })
            .eq('id', userId)
            .eq('push_token', currentToken);
        _debugLog('[PushTokenService] profiles.push_token limpo no logout');
      } catch (e, st) {
        _debugLog(
          '[PushTokenService] erro ao limpar profiles.push_token: $e',
        );
        _debugStack(stackTrace: st);
      }
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
      _debugLog('[PushTokenService] erro debug: $e');
      _debugStack(stackTrace: st);
      return 'SYNC_ERROR: $e';
    }
  }

  Future<void> dispose() async {
    _retryTimer?.cancel();
    _retryTimer = null;
    await _tokenRefreshSub?.cancel();
    await _authStateSub?.cancel();
    _tokenRefreshSub = null;
    _authStateSub = null;
    _initialized = false;
  }
}
