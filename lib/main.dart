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
import 'pages/chat_rooms_page.dart';
import 'pages/coach_dashboard_page.dart';
import 'pages/complete_profile_page.dart';
import 'pages/dashboard_router_page.dart';
import 'pages/login_page.dart';
import 'pages/member_dashboard_page.dart';
import 'pages/profiles_page.dart';
import 'pages/register_page.dart';
import 'services/auth_service.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
}

void main() async {
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

  await _setupPushNotifications();

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

  await messaging.requestPermission();

  await messaging.setAutoInitEnabled(true);

  FirebaseMessaging.onMessage.listen((RemoteMessage message) {
    debugPrint('Push em foreground: ${message.notification?.title}');
  });

  FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
    debugPrint('Push aberto pelo usuário: ${message.messageId}');
  });

  final token = await messaging.getToken();
  debugPrint('FCM TOKEN: $token');
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
      routes: {
        '/': (context) => const AuthWrapper(),
        '/login': (context) => const LoginPage(),
        '/register': (context) => const RegisterPage(),
        '/profiles': (context) => const AdminOnlyProfilesRoute(),
        '/athlete-dashboard': (context) => const AthleteDashboardPage(),
        '/coach-dashboard': (context) => const CoachDashboardPage(),
        '/member-dashboard': (context) => const MemberDashboardPage(),
        '/complete-profile': (context) => const CompleteProfilePage(),
        '/dashboard': (context) => const DashboardRouterPage(),
        '/admin-home': (context) => const AdminHomePage(),
        '/chat-rooms': (context) => const ChatRoomsPage(),
      },
    );
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
  final _authService = AuthService();
  bool _isLoading = true;
  bool _isLoggedIn = false;

  @override
  void initState() {
    super.initState();
    _checkAuth();
  }

  Future<void> _checkAuth() async {
    await Future.delayed(const Duration(milliseconds: 500));

    setState(() {
      _isLoggedIn = _authService.getCurrentUser() != null;
      _isLoading = false;
    });

    _authService.authStateChanges.listen((event) {
      if (mounted) {
        setState(() {
          _isLoggedIn = event.session != null;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const PremiumLoadingScreen(
        text: 'Carregando...',
      );
    }

    if (_isLoggedIn) {
      return const DashboardRouterPage();
    }

    return const LoginPage();
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
