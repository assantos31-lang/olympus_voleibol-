import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PushNotificationService {
  PushNotificationService._();

  static final PushNotificationService instance = PushNotificationService._();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;

    await _requestPermission();
    await _initializeLocalNotifications();
    await _configureForegroundPresentation();
    await _saveCurrentToken();
    _listenTokenRefresh();
    _listenForegroundMessages();
    _listenNotificationTap();

    _initialized = true;
  }

  Future<void> _requestPermission() async {
    await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
      announcement: false,
      criticalAlert: false,
      carPlay: false,
    );
  }

  Future<void> _configureForegroundPresentation() async {
    await _messaging.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );
  }

  Future<void> _initializeLocalNotifications() async {
    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings();

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
      macOS: iosSettings,
    );

    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (details) {
        _handleNotificationPayload(details.payload);
      },
    );

    const androidChannel = AndroidNotificationChannel(
      'messages_channel',
      'Mensagens',
      description: 'Canal de notificações de mensagens',
      importance: Importance.max,
    );

    await _localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(androidChannel);
  }

  Future<void> _saveCurrentToken() async {
    final token = await _messaging.getToken();
    if (token == null || token.isEmpty) return;
    await _upsertToken(token);
  }

  void _listenTokenRefresh() {
    _messaging.onTokenRefresh.listen((token) async {
      if (token.isEmpty) return;
      await _upsertToken(token);
    });
  }

  Future<void> _upsertToken(String token) async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    final platform = _platformName();

    try {
      final existing = await Supabase.instance.client
          .from('user_push_tokens')
          .select('id')
          .eq('user_id', user.id)
          .maybeSingle();

      if (existing != null && existing['id'] != null) {
        await Supabase.instance.client.from('user_push_tokens').update({
          'device_token': token,
          'platform': platform,
          'updated_at': DateTime.now().toIso8601String(),
        }).eq('id', existing['id']);
      } else {
        await Supabase.instance.client.from('user_push_tokens').insert({
          'user_id': user.id,
          'device_token': token,
          'platform': platform,
          'created_at': DateTime.now().toIso8601String(),
          'updated_at': DateTime.now().toIso8601String(),
        });
      }
    } catch (e) {
      debugPrint('Erro ao salvar push token: $e');
    }
  }

  String _platformName() {
    if (kIsWeb) return 'web';
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    return 'unknown';
  }

  void _listenForegroundMessages() {
    FirebaseMessaging.onMessage.listen((message) async {
      final title = message.notification?.title ?? 'Nova mensagem';
      final body = message.notification?.body ?? '';
      final payload = message.data['thread_id']?.toString();

      await _localNotifications.show(
        title.hashCode ^ body.hashCode,
        title,
        body,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'messages_channel',
            'Mensagens',
            channelDescription: 'Canal de notificações de mensagens',
            importance: Importance.max,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(),
        ),
        payload: payload,
      );
    });
  }

  void _listenNotificationTap() {
    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      final payload = message.data['thread_id']?.toString();
      _handleNotificationPayload(payload);
    });
  }

  Future<void> handleInitialMessage() async {
    final initialMessage = await _messaging.getInitialMessage();
    if (initialMessage == null) return;

    final payload = initialMessage.data['thread_id']?.toString();
    _handleNotificationPayload(payload);
  }

  void _handleNotificationPayload(String? threadId) {
    if (threadId == null || threadId.isEmpty) return;
    debugPrint('Abrir thread de mensagem: $threadId');
    // Aqui depois podemos ligar com navigatorKey/rota nomeada.
  }
}

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint('Mensagem recebida em background: ${message.messageId}');
}
