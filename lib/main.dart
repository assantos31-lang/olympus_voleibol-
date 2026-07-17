import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'firebase_options.dart';
import 'pages/admin_home_page.dart';
import 'pages/admin_athletes_statistics_list_page.dart';
import 'pages/admin_coach_evaluations_page.dart';
import 'pages/athlete_agenda_page.dart';
import 'pages/athlete_dashboard_page.dart';
import 'pages/athlete_financial_page.dart';
import 'pages/athlete_statistics_page.dart';
import 'pages/athlete_coach_evaluation_page.dart';
import 'pages/athlete_messages_page.dart';
import 'pages/chat_rooms_page.dart';
import 'pages/complete_profile_page.dart';
import 'coach/pages/coach_received_evaluations_page.dart';
import 'coach/pages/coach_messages_page.dart';
import 'pages/dashboard_router_page.dart';
import 'pages/login_page.dart';
import 'pages/profiles_page.dart';
import 'services/auth_service.dart';
import 'services/active_chat_service.dart';
import 'services/badge_service.dart';
import 'services/push_token_service.dart';

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

const FlutterSecureStorage _secureStorage = FlutterSecureStorage();

bool _handledInitialMessage = false;
Map<String, dynamic>? _pendingNotificationData;
String? _lastChatNotificationRoomId;
DateTime? _lastChatNotificationNavigationAt;

int _stableNotificationId(String value) {
  var hash = 0;
  for (final unit in value.codeUnits) {
    hash = ((hash * 31) + unit) & 0x7fffffff;
  }
  return 100000 + (hash % 800000);
}

const AndroidNotificationChannel channel = AndroidNotificationChannel(
  'messages_channel',
  'Messages',
  description: 'Canal de notificações do Olympus',
  importance: Importance.max,
  showBadge: true,
);

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
}

bool _isBrokenAndroidEncryptedStorageError(Object error) {
  final text = error.toString();

  return text.contains('BadPaddingException') ||
      text.contains('BAD_DECRYPT') ||
      text.contains('Failed to unwrap key') ||
      text.contains('InvalidKeyException') ||
      text.contains('javax.crypto');
}

Future<void> _clearBrokenSecureStorage() async {
  if (kIsWeb || !Platform.isAndroid) return;

  try {
    await _secureStorage.deleteAll();
  } catch (e) {
    debugPrint('Erro ao limpar storage seguro: $e');
  }
}

Future<void> _initializeSupabase() async {
  try {
    await Supabase.initialize(
      url: 'https://wucxbbspybemvkqgqtou.supabase.co',
      anonKey: 'sb_publishable_jfe15-g7mYFo0mSI9tuDtw_dI6qrnx4',
    );
  } on PlatformException catch (e) {
    if (!_isBrokenAndroidEncryptedStorageError(e)) rethrow;

    await _clearBrokenSecureStorage();

    await Supabase.initialize(
      url: 'https://wucxbbspybemvkqgqtou.supabase.co',
      anonKey: 'sb_publishable_jfe15-g7mYFo0mSI9tuDtw_dI6qrnx4',
    );
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    if (!kIsWeb) {
      FirebaseMessaging.onBackgroundMessage(
        _firebaseMessagingBackgroundHandler,
      );
    }

    await flutterLocalNotificationsPlugin.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(),
      ),
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        final payload = response.payload;
        if (payload == null || payload.isEmpty) return;

        try {
          final data = Map<String, dynamic>.from(jsonDecode(payload) as Map);
          _navigateFromNotificationData(data);
        } catch (e) {
          debugPrint('Erro ao processar payload da notificaÃ§Ã£o local: $e');
        }
      },
    );

    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    await _initializeSupabase();

    runApp(
      MultiProvider(
        providers: [
          Provider<AuthService>(create: (_) => AuthService()),
        ],
        child: const MyApp(),
      ),
    );
  } catch (e, s) {
    debugPrint('ERRO FATAL AO INICIAR APP: $e');
    debugPrint('$s');

    runApp(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          backgroundColor: Colors.black,
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Erro ao iniciar o aplicativo:\n\n$e',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> initializeNotificationServicesForCompatibility() async {
  await flutterLocalNotificationsPlugin.initialize(
    InitializationSettings(
      android: const AndroidInitializationSettings('@mipmap/ic_launcher'),
    ),
    onDidReceiveNotificationResponse: (NotificationResponse response) {
      final payload = response.payload;
      if (payload == null || payload.isEmpty) return;

      try {
        final data = Map<String, dynamic>.from(jsonDecode(payload) as Map);
        _navigateFromNotificationData(data);
      } catch (e) {
        debugPrint('Erro ao processar payload da notificação local: $e');
      }
    },
  );

  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(channel);

  await _setupPushNotifications();
}

Future<void> _setupPushNotifications() async {
  if (kIsWeb) return;

  final messaging = FirebaseMessaging.instance;

  final settings = await messaging.requestPermission(
    alert: true,
    badge: true,
    sound: true,
    provisional: false,
  );

  debugPrint('Permissão push: ${settings.authorizationStatus}');

  await messaging.setAutoInitEnabled(true);

  await messaging.setForegroundNotificationPresentationOptions(
    alert: false,
    badge: true,
    sound: false,
  );

  FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
    debugPrint('Push em foreground: ${message.notification?.title}');

    final notification = message.notification;

    if (notification != null) {
      final data = message.data;
      final type = (data['type'] ?? data['notification_type'] ?? '')
          .toString()
          .toLowerCase();
      final roomId = (data['roomId'] ??
              data['room_id'] ??
              data['threadId'] ??
              data['thread_id'])
          ?.toString();
      final isChatNotification =
          (type == 'message' || type == 'chat_message') &&
              roomId != null &&
              roomId.isNotEmpty;
      final payloadNotificationId = int.tryParse(
        (data['notification_id'] ??
                data['notificationId'] ??
                data['local_notification_id'] ??
                '')
            .toString(),
      );
      final notificationId = isChatNotification
          ? (payloadNotificationId ?? _stableNotificationId('chat_$roomId'))
          : _stableNotificationId(
              message.messageId ??
                  '${notification.title ?? ''}_${notification.body ?? ''}',
            );
      final groupKey = isChatNotification ? 'chat_$roomId' : null;

      if (isChatNotification && ActiveChatService.isRoomOpen(roomId)) {
        await flutterLocalNotificationsPlugin.cancel(
          notificationId,
          tag: groupKey,
        );
        await BadgeService.updateBadge();
        return;
      }

      await flutterLocalNotificationsPlugin.show(
        notificationId,
        notification.title,
        notification.body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            'messages_channel',
            'Messages',
            channelDescription: 'Canal de notificações do Olympus',
            importance: Importance.max,
            priority: Priority.high,
            groupKey: groupKey,
            setAsGroupSummary: false,
            tag: groupKey,
          ),
          iOS: DarwinNotificationDetails(
            threadIdentifier: groupKey,
          ),
        ),
        payload: jsonEncode(message.data),
      );
    }

    await BadgeService.updateBadge();
  });

  FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) async {
    debugPrint('Push aberto pelo usuário: ${message.messageId}');
    await BadgeService.updateBadge();
    _handleNotificationTap(message);
  });

  if (!_handledInitialMessage) {
    _handledInitialMessage = true;

    final initialMessage = await FirebaseMessaging.instance.getInitialMessage();

    if (initialMessage != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await Future<void>.delayed(const Duration(milliseconds: 700));
        _handleNotificationTap(initialMessage);
      });
    }
  }

  await PushTokenService.instance.init();
}

void _handleNotificationTap(RemoteMessage message) {
  debugPrint('Notification tap data: ${message.data}');
  _navigateFromNotificationData(message.data);
}

void _navigateFromNotificationData(Map<String, dynamic> data) {
  final type = (data['type'] ?? data['notification_type'] ?? '')
      .toString()
      .trim()
      .toLowerCase()
      .replaceAll('-', '_');

  final eventId = (data['eventId'] ?? data['event_id'])?.toString();
  final threadId = (data['threadId'] ??
          data['thread_id'] ??
          data['roomId'] ??
          data['room_id'])
      ?.toString();

  if (Supabase.instance.client.auth.currentSession == null ||
      navigatorKey.currentState == null) {
    _pendingNotificationData = Map<String, dynamic>.from(data);
    return;
  }

  _pendingNotificationData = null;

  const eventNotificationTypes = {
    'event',
    'new_event',
    'event_created',
    'event_reminder',
    'convocation',
    'convocation_reminder',
    'checkin',
    'checkin_open',
    'checkin_last_10',
  };

  if (eventNotificationTypes.contains(type)) {
    _openAthleteAgenda(eventId: eventId);
    return;
  }

  if (type.startsWith('financial_') ||
      type == 'financial' ||
      type == 'finance' ||
      type == 'financial_record' ||
      type == 'new_financial_record') {
    navigatorKey.currentState?.pushNamed('/athlete-financial');
    return;
  }

  if (type == 'admin_evaluation_pending' ||
      type == 'evaluation_pending' ||
      type == 'coach_evaluation_pending') {
    navigatorKey.currentState?.pushNamed('/admin-coach-evaluations');
    return;
  }

  if (type == 'coach_evaluation_approved' ||
      type == 'coach_evaluation_received' ||
      type == 'evaluation_approved') {
    navigatorKey.currentState?.pushNamed('/coach-received-evaluations');
    return;
  }

  if (type == 'athlete_coach_feedback' ||
      type == 'athlete_feedback' ||
      type == 'coach_feedback') {
    navigatorKey.currentState?.pushNamed('/athlete-statistics');
    return;
  }

  if (type == 'platform_message' ||
      type == 'app_message' ||
      type == 'admin_message') {
    unawaited(_openPlatformMessages());
    return;
  }

  if (type == 'message' || type == 'chat_message') {
    final cleanThreadId = threadId?.trim();
    final now = DateTime.now();
    final isDuplicateTap = cleanThreadId != null &&
        cleanThreadId.isNotEmpty &&
        _lastChatNotificationRoomId == cleanThreadId &&
        _lastChatNotificationNavigationAt != null &&
        now.difference(_lastChatNotificationNavigationAt!) <
            const Duration(seconds: 2);

    if (isDuplicateTap) return;

    _lastChatNotificationRoomId = cleanThreadId;
    _lastChatNotificationNavigationAt = now;

    navigatorKey.currentState?.pushNamedAndRemoveUntil(
      '/chat-rooms',
      (route) => route.isFirst,
      arguments: {'roomId': cleanThreadId},
    );
    return;
  }
}

Future<void> _openPlatformMessages() async {
  final navigator = navigatorKey.currentState;
  final user = Supabase.instance.client.auth.currentUser;
  if (navigator == null || user == null) return;

  String primaryRole = 'athlete';
  try {
    final profile = await Supabase.instance.client
        .from('profiles')
        .select('user_type')
        .eq('id', user.id)
        .maybeSingle();
    primaryRole =
        (profile?['user_type'] ?? 'athlete').toString().trim().toLowerCase();
  } catch (_) {}

  if (navigatorKey.currentState == null) return;
  if (primaryRole == 'admin') {
    navigator.push(
      MaterialPageRoute(builder: (_) => const AthleteMessagesPage()),
    );
  } else if ({'coach', 'treinador', 'tecnico', 'técnico'}
      .contains(primaryRole)) {
    navigator.push(
      MaterialPageRoute(builder: (_) => const CoachMessagesPage()),
    );
  } else {
    navigator.push(
      MaterialPageRoute(builder: (_) => const AthleteMessagesPage()),
    );
  }
}

void _flushPendingNotification() {
  final pendingData = _pendingNotificationData;
  if (pendingData == null) return;

  WidgetsBinding.instance.addPostFrameCallback((_) {
    Future<void>.delayed(const Duration(milliseconds: 500), () {
      _navigateFromNotificationData(pendingData);
    });
  });
}

void _openAthleteAgenda({String? eventId}) {
  final navigator = navigatorKey.currentState;

  if (navigator == null) {
    Future<void>.delayed(const Duration(milliseconds: 500), () {
      _openAthleteAgenda(eventId: eventId);
    });
    return;
  }

  navigator.pushNamed(
    '/athlete-agenda',
    arguments: {
      'eventId': eventId,
    },
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'Olympus Voleibol',
      debugShowCheckedModeBanner: false,
      locale: const Locale('pt', 'BR'),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('pt', 'BR'),
        Locale('en', 'US'),
      ],
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      initialRoute: '/',
      routes: {
        '/': (context) => const AppBootstrapPage(),
        '/login': (context) => const LoginPage(),
        '/profiles': (context) => const AdminOnlyProfilesRoute(),
        '/athlete-dashboard': (context) => const AthleteDashboardPage(),
        '/athlete-agenda': (context) => const AthleteAgendaPage(),
        '/athlete-financial': (context) => const AthleteFinancialPage(),
        '/athlete-statistics': (context) => const AthleteStatisticsPage(),
        '/complete-profile': (context) => const CompleteProfilePage(),
        '/dashboard': (context) => const DashboardRouterPage(),
        '/admin-home': (context) => const AdminHomePage(),
        '/admin-athletes-statistics': (context) =>
            const AdminAthletesStatisticsListPage(),
        '/athlete-coach-evaluation': (context) =>
            const AthleteCoachEvaluationPage(),
        '/admin-coach-evaluations': (context) =>
            const AdminCoachEvaluationsPage(),
        '/coach-received-evaluations': (context) =>
            const CoachReceivedEvaluationsPage(),
        '/chat-rooms': (context) {
          final args = ModalRoute.of(context)?.settings.arguments;
          String? roomId;
          if (args is Map) {
            roomId = (args['roomId'] ?? args['room_id'] ?? args['threadId'])
                ?.toString();
          }
          return ChatRoomsPage(initialRoomId: roomId);
        },
      },
    );
  }
}

class AppBootstrapPage extends StatefulWidget {
  const AppBootstrapPage({super.key});

  @override
  State<AppBootstrapPage> createState() => _AppBootstrapPageState();
}

class _AppBootstrapPageState extends State<AppBootstrapPage> {
  bool _isReady = false;
  bool _hasError = false;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    try {
      await _setupPushNotifications();

      if (!mounted) return;

      setState(() {
        _isReady = true;
      });
    } catch (e) {
      debugPrint('Erro no bootstrap do app: $e');

      if (_isBrokenAndroidEncryptedStorageError(e)) {
        await _clearBrokenSecureStorage();

        if (!mounted) return;

        setState(() {
          _isReady = true;
          _hasError = false;
          _errorMessage = '';
        });
        return;
      }

      if (!mounted) return;

      setState(() {
        _hasError = true;
        _errorMessage = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_hasError) {
      return Scaffold(
        body: Stack(
          children: [
            Positioned.fill(
              child: Image.asset(
                'assets/images/monte_olimpo_v2.png',
                fit: BoxFit.cover,
              ),
            ),
            Positioned.fill(
              child: Container(color: Colors.black.withOpacity(0.65)),
            ),
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.error_outline,
                      color: Colors.white,
                      size: 48,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Erro ao iniciar o aplicativo',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _errorMessage,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (!_isReady) {
      return const PremiumLoadingScreen(
        text: 'Iniciando aplicativo...',
      );
    }

    return const AuthWrapper();
  }
}

class PremiumLoadingScreen extends StatelessWidget {
  final String text;

  const PremiumLoadingScreen({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: Image.asset(
              'assets/images/monte_olimpo_v2.png',
              fit: BoxFit.cover,
              alignment: Alignment.center,
            ),
          ),
          Positioned.fill(
            child: Container(
              color: Colors.black.withOpacity(0.55),
            ),
          ),
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0x66102845),
                    Color(0x401E3A5F),
                    Color(0x99000000),
                  ],
                ),
              ),
            ),
          ),
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const CircularProgressIndicator(
                  color: Color(0xFFFFD54F),
                ),
                const SizedBox(height: 20),
                Text(
                  text,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  final _auth = Supabase.instance.client.auth;
  bool _initialAuthResolved = false;
  bool _postLoginServicesScheduled = false;

  @override
  void initState() {
    super.initState();

    Future<void>.delayed(const Duration(milliseconds: 1200), () {
      if (!mounted) return;

      setState(() {
        _initialAuthResolved = true;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: _auth.onAuthStateChange,
      builder: (context, snapshot) {
        final hasSession =
            _auth.currentSession != null && _auth.currentUser != null;

        if (!_initialAuthResolved && !hasSession) {
          return const PremiumLoadingScreen(
            text: 'Restaurando sessão...',
          );
        }

        if (hasSession) {
          if (!_postLoginServicesScheduled) {
            _postLoginServicesScheduled = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              PushTokenService.instance.syncCurrentUserTokenIfPossible();
              BadgeService.updateBadge();
              _flushPendingNotification();
            });
          }

          return const DashboardRouterPage();
        }

        _postLoginServicesScheduled = false;

        if (!_initialAuthResolved &&
            snapshot.connectionState == ConnectionState.waiting) {
          return const PremiumLoadingScreen(
            text: 'Restaurando sessão...',
          );
        }

        return const LoginPage();
      },
    );
  }
}

class AdminOnlyProfilesRoute extends StatefulWidget {
  const AdminOnlyProfilesRoute({super.key});

  @override
  State<AdminOnlyProfilesRoute> createState() => _AdminOnlyProfilesRouteState();
}

class _AdminOnlyProfilesRouteState extends State<AdminOnlyProfilesRoute> {
  final supabase = Supabase.instance.client;
  bool _isLoading = true;
  bool _isAdmin = false;

  @override
  void initState() {
    super.initState();
    _checkAccess();
  }

  Future<void> _checkAccess() async {
    try {
      final user = supabase.auth.currentUser;

      if (user == null) {
        if (mounted) {
          Navigator.pushNamedAndRemoveUntil(
            context,
            '/login',
            (route) => false,
          );
        }
        return;
      }

      final profile = await supabase
          .from('profiles')
          .select('user_type')
          .eq('id', user.id)
          .maybeSingle();

      if (!mounted) return;

      final userType = (profile?['user_type'] ?? '').toString();

      if (userType != 'admin') {
        Navigator.pushNamedAndRemoveUntil(
          context,
          '/dashboard',
          (route) => false,
        );
        return;
      }

      setState(() {
        _isAdmin = true;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;

      Navigator.pushNamedAndRemoveUntil(
        context,
        '/dashboard',
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const PremiumLoadingScreen(
        text: 'Carregando...',
      );
    }

    if (!_isAdmin) {
      return const SizedBox.shrink();
    }

    return const ProfilesPage();
  }
}
