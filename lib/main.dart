import 'dart:async';
import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'firebase_options.dart';
import 'pages/admin_home_page.dart';
import 'pages/athlete_dashboard_page.dart';
import 'pages/admin_athletes_statistics_page.dart';
import 'pages/chat_rooms_page.dart';
import 'pages/complete_profile_page.dart';
import 'pages/dashboard_router_page.dart';
import 'pages/login_page.dart';
import 'pages/profiles_page.dart';
import 'services/auth_service.dart';
import 'services/badge_service.dart';
import 'services/push_token_service.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  if (!kIsWeb) {
    FirebaseMessaging.onBackgroundMessage(
      _firebaseMessagingBackgroundHandler,
    );
  }

  await Supabase.initialize(
    url: 'https://wucxbbspybemvkqgqtou.supabase.co',
    anonKey: 'sb_publishable_jfe15-g7mYFo0mSI9tuDtw_dI6qrnx4',
  );

  runApp(
    MultiProvider(
      providers: [
        Provider<AuthService>(create: (_) => AuthService()),
      ],
      child: const MyApp(),
    ),
  );
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
    alert: true,
    badge: true,
    sound: true,
  );

  FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
    debugPrint('Push em foreground: ${message.notification?.title}');
    await BadgeService.updateBadge();
  });

  FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) async {
    debugPrint('Push aberto pelo usuário: ${message.messageId}');
    await BadgeService.updateBadge();
  });

  await PushTokenService.instance.init();
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
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
      onGenerateRoute: (settings) {
        if (settings.name == '/admin-athletes-statistics') {
          return AthleteStatisticsPage.route(adminView: true);
        }
        return null;
      },
      routes: {
        '/': (context) => const AppBootstrapPage(),
        '/login': (context) => const LoginPage(),
        '/profiles': (context) => const AdminOnlyProfilesRoute(),
        '/athlete-dashboard': (context) => const AthleteDashboardPage(),
        '/complete-profile': (context) => const CompleteProfilePage(),
        '/dashboard': (context) => const DashboardRouterPage(),
        '/admin-home': (context) => const AdminHomePage(),
        '/chat-rooms': (context) => const ChatRoomsPage(),
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
          WidgetsBinding.instance.addPostFrameCallback((_) {
            PushTokenService.instance.syncCurrentUserTokenIfPossible();
            BadgeService.updateBadge();
          });
          return const DashboardRouterPage();
        }

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
