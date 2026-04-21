import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/auth_service.dart';
import '../services/push_token_service.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> with TickerProviderStateMixin {
  static const Color olympusBlue = Color(0xFF1E3A5F);
  static const Color olympusGold = Color(0xFFD4AF37);
  static const Color olympusLightBlue = Color(0xFF2C5F8D);
  static const Color futuristicDark = Color(0xFF0B1420);
  static const Color futuristicCard = Color(0xFF122235);

  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _authService = AuthService();
  final _emailFocusNode = FocusNode();
  final _passwordFocusNode = FocusNode();

  late final AnimationController _animationController;
  late final AnimationController _pulseController;
  late final Animation<double> _fadeAnimation;
  late final Animation<double> _logoScaleAnimation;
  late final Animation<double> _logoPulseAnimation;
  late final Animation<Offset> _contentSlideAnimation;

  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _isAnyFieldFocused = false;

  @override
  void initState() {
    super.initState();

    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: true);

    _fadeAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOutCubic,
    );

    _logoScaleAnimation = Tween<double>(
      begin: 0.92,
      end: 1,
    ).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Curves.easeOutBack,
      ),
    );

    _logoPulseAnimation = Tween<double>(
      begin: 1.0,
      end: 1.03,
    ).animate(
      CurvedAnimation(
        parent: _pulseController,
        curve: Curves.easeInOut,
      ),
    );

    _contentSlideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.045),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Curves.easeOutCubic,
      ),
    );

    _emailFocusNode.addListener(_handleFocusChange);
    _passwordFocusNode.addListener(_handleFocusChange);

    _animationController.forward();
  }

  void _handleFocusChange() {
    final hasFocus = _emailFocusNode.hasFocus || _passwordFocusNode.hasFocus;
    if (hasFocus != _isAnyFieldFocused) {
      setState(() {
        _isAnyFieldFocused = hasFocus;
      });
    }
  }

  Widget _buildOlympusBackground() {
    return Stack(
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedScale(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutCubic,
              scale: _isAnyFieldFocused ? 0.965 : 1.0,
              child: AnimatedSlide(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOutCubic,
                offset:
                    _isAnyFieldFocused ? const Offset(0, -0.012) : Offset.zero,
                child: Image.asset(
                  'assets/images/monte_olimpo_v2.png',
                  fit: BoxFit.cover,
                  alignment: Alignment.center,
                  errorBuilder: (context, error, stackTrace) {
                    debugPrint('Erro ao carregar monte_olimpo_v2.png: $error');
                    return Container(
                      color: Colors.red,
                      alignment: Alignment.center,
                      child: const Text(
                        'ERRO AO CARREGAR monte_olimpo_v2.png',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutCubic,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    olympusBlue.withOpacity(_isAnyFieldFocused ? 0.66 : 0.58),
                    olympusBlue.withOpacity(_isAnyFieldFocused ? 0.42 : 0.34),
                    futuristicDark
                        .withOpacity(_isAnyFieldFocused ? 0.82 : 0.72),
                  ],
                ),
              ),
            ),
          ),
        ),
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutCubic,
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0, -0.25),
                  radius: 1.15,
                  colors: [
                    olympusLightBlue
                        .withOpacity(_isAnyFieldFocused ? 0.18 : 0.12),
                    Colors.transparent,
                    futuristicDark
                        .withOpacity(_isAnyFieldFocused ? 0.22 : 0.16),
                  ],
                ),
              ),
            ),
          ),
        ),
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(
              painter: _FuturisticBackgroundPainter(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildGlassCard({
    required Widget child,
    EdgeInsetsGeometry? padding,
    BorderRadius? borderRadius,
    double blurSigma = 16,
  }) {
    final radius = borderRadius ?? BorderRadius.circular(24);

    return ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Colors.white.withOpacity(0.12),
                Colors.white.withOpacity(0.05),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: radius,
            border: Border.all(
              color: olympusGold.withOpacity(0.24),
              width: 1.05,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.28),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    _pulseController.dispose();
    _emailFocusNode.removeListener(_handleFocusChange);
    _passwordFocusNode.removeListener(_handleFocusChange);
    _emailFocusNode.dispose();
    _passwordFocusNode.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;

    FocusScope.of(context).unfocus();
    setState(() => _isLoading = true);

    await Future.delayed(const Duration(milliseconds: 80));

    final result = await _authService.signIn(
      _emailController.text.trim(),
      _passwordController.text,
    );

    if (!mounted) return;

    if (result['success'] == true) {
      try {
        await PushTokenService.instance.syncAfterLogin();
      } catch (e) {
        debugPrint('ERRO AO SINCRONIZAR PUSH: $e');
      }

      if (!mounted) return;

      Navigator.pushNamedAndRemoveUntil(
        context,
        '/dashboard',
        (route) => false,
      );
    } else {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result['error'] ?? 'Erro ao fazer login'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  InputDecoration _inputDecoration({
    required String label,
    required IconData icon,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(color: Colors.white.withOpacity(0.78)),
      prefixIcon: Icon(icon, color: olympusGold),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: const Color(0xFF0A1A2C).withOpacity(0.82),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: olympusGold.withOpacity(0.24)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: olympusGold.withOpacity(0.24)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: olympusGold, width: 1.8),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: Colors.redAccent),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: Colors.redAccent, width: 1.8),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final screenWidth = media.size.width;
    final isVerySmall = screenWidth < 360;
    final isMobile = screenWidth < 600;
    final isTablet = screenWidth >= 600 && screenWidth < 900;

    final logoSize = isVerySmall
        ? 125.0
        : isMobile
            ? 150.0
            : isTablet
                ? 175.0
                : 190.0;

    final horizontalPadding = isVerySmall
        ? 14.0
        : isMobile
            ? 18.0
            : 24.0;

    final buttonHeight = isVerySmall
        ? 48.0
        : isMobile
            ? 52.0
            : 56.0;

    final buttonFontSize = isVerySmall
        ? 13.0
        : isMobile
            ? 15.0
            : 16.0;

    final buttonIconSize = isVerySmall
        ? 18.0
        : isMobile
            ? 20.0
            : 22.0;

    final headerTitleFont = isVerySmall
        ? 22.0
        : isMobile
            ? 28.0
            : 38.0;

    final headerSubtitleFont = isVerySmall
        ? 13.0
        : isMobile
            ? 16.0
            : 20.0;

    final infoFont = isVerySmall
        ? 11.0
        : isMobile
            ? 13.0
            : 15.0;

    final cardRadius = isVerySmall ? 24.0 : 28.0;
    final formRadius = isVerySmall ? 22.0 : 24.0;

    final headerTopMargin = logoSize * 0.58;
    final headerTopPadding =
        (logoSize - headerTopMargin) + (isMobile ? 22.0 : 26.0);

    return Scaffold(
      backgroundColor: futuristicDark,
      body: Stack(
        children: [
          _buildOlympusBackground(),
          SafeArea(
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: SlideTransition(
                position: _contentSlideAnimation,
                child: Center(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.symmetric(
                      horizontal: horizontalPadding,
                      vertical: isVerySmall ? 12 : 18,
                    ),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: isMobile ? 380 : 540,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Stack(
                            clipBehavior: Clip.none,
                            alignment: Alignment.topCenter,
                            children: [
                              Container(
                                margin: EdgeInsets.only(top: headerTopMargin),
                                child: _buildGlassCard(
                                  borderRadius:
                                      BorderRadius.circular(cardRadius),
                                  blurSigma: 20,
                                  padding: EdgeInsets.fromLTRB(
                                    isVerySmall ? 16 : 24,
                                    headerTopPadding,
                                    isVerySmall ? 16 : 24,
                                    isVerySmall ? 18 : 28,
                                  ),
                                  child: Column(
                                    children: [
                                      Text(
                                        'OLYMPUS',
                                        style: TextStyle(
                                          fontSize: headerTitleFont,
                                          fontWeight: FontWeight.w800,
                                          color: Colors.white,
                                          letterSpacing:
                                              isVerySmall ? 1.2 : 2.0,
                                          height: 1,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                      SizedBox(height: isVerySmall ? 6 : 8),
                                      Text(
                                        'VOLEIBOL',
                                        style: TextStyle(
                                          fontSize: headerSubtitleFont,
                                          fontWeight: FontWeight.w800,
                                          color: olympusGold,
                                          letterSpacing:
                                              isVerySmall ? 1.8 : 2.8,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                      SizedBox(height: isVerySmall ? 12 : 16),
                                      Text(
                                        'Faça login para acessar o sistema',
                                        style: TextStyle(
                                          fontSize: infoFont,
                                          color: Colors.white.withOpacity(0.78),
                                          fontWeight: FontWeight.w500,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              ScaleTransition(
                                scale: _logoScaleAnimation,
                                child: AnimatedBuilder(
                                  animation: _logoPulseAnimation,
                                  builder: (context, child) {
                                    return Transform.scale(
                                      scale: _logoPulseAnimation.value,
                                      child: child,
                                    );
                                  },
                                  child: Container(
                                    width: logoSize,
                                    height: logoSize,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      gradient: LinearGradient(
                                        colors: [
                                          olympusGold.withOpacity(0.95),
                                          const Color(0xFFFFE08A),
                                        ],
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: olympusGold.withOpacity(0.30),
                                          blurRadius: isMobile ? 22 : 30,
                                          spreadRadius: isMobile ? 2 : 4,
                                        ),
                                      ],
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.all(4),
                                      child: ClipOval(
                                        child: Image.asset(
                                          'assets/images/olympus_logo.png',
                                          fit: BoxFit.cover,
                                          width: logoSize,
                                          height: logoSize,
                                          errorBuilder:
                                              (context, error, stackTrace) {
                                            debugPrint(
                                                'Erro ao carregar logo: $error');
                                            return Container(
                                              color: futuristicCard,
                                              alignment: Alignment.center,
                                              child: Icon(
                                                Icons.sports_volleyball,
                                                size: logoSize * 0.52,
                                                color: olympusGold,
                                              ),
                                            );
                                          },
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: isVerySmall ? 20 : 30),
                          _buildGlassCard(
                            borderRadius: BorderRadius.circular(formRadius),
                            blurSigma: 22,
                            padding: EdgeInsets.all(isVerySmall ? 14 : 22),
                            child: Form(
                              key: _formKey,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  TextFormField(
                                    controller: _emailController,
                                    focusNode: _emailFocusNode,
                                    style: const TextStyle(color: Colors.white),
                                    decoration: _inputDecoration(
                                      label: 'Email',
                                      icon: Icons.email_outlined,
                                    ),
                                    keyboardType: TextInputType.emailAddress,
                                    validator: (value) {
                                      if (value?.isEmpty ?? true) {
                                        return 'Digite seu email';
                                      }
                                      if (!value!.contains('@')) {
                                        return 'Email inválido';
                                      }
                                      return null;
                                    },
                                  ),
                                  const SizedBox(height: 16),
                                  TextFormField(
                                    controller: _passwordController,
                                    focusNode: _passwordFocusNode,
                                    style: const TextStyle(color: Colors.white),
                                    decoration: _inputDecoration(
                                      label: 'Senha',
                                      icon: Icons.lock_outline,
                                      suffixIcon: IconButton(
                                        icon: Icon(
                                          _obscurePassword
                                              ? Icons.visibility_outlined
                                              : Icons.visibility_off_outlined,
                                          color: olympusGold,
                                        ),
                                        onPressed: () {
                                          setState(() {
                                            _obscurePassword =
                                                !_obscurePassword;
                                          });
                                        },
                                      ),
                                    ),
                                    obscureText: _obscurePassword,
                                    validator: (value) {
                                      if (value?.isEmpty ?? true) {
                                        return 'Digite sua senha';
                                      }
                                      if (value!.length < 6) {
                                        return 'Senha deve ter no mínimo 6 caracteres';
                                      }
                                      return null;
                                    },
                                  ),
                                  const SizedBox(height: 22),
                                  SizedBox(
                                    width: double.infinity,
                                    height: buttonHeight,
                                    child: DecoratedBox(
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(18),
                                        boxShadow: [
                                          BoxShadow(
                                            color:
                                                olympusGold.withOpacity(0.24),
                                            blurRadius: 18,
                                            offset: const Offset(0, 6),
                                          ),
                                        ],
                                      ),
                                      child: ElevatedButton(
                                        onPressed:
                                            _isLoading ? null : _handleLogin,
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: olympusGold,
                                          foregroundColor: olympusBlue,
                                          elevation: 0,
                                          shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(18),
                                          ),
                                        ),
                                        child: _isLoading
                                            ? const SizedBox(
                                                width: 22,
                                                height: 22,
                                                child:
                                                    CircularProgressIndicator(
                                                  strokeWidth: 2,
                                                  valueColor:
                                                      AlwaysStoppedAnimation<
                                                          Color>(
                                                    olympusBlue,
                                                  ),
                                                ),
                                              )
                                            : Row(
                                                mainAxisAlignment:
                                                    MainAxisAlignment.center,
                                                children: [
                                                  Icon(
                                                    Icons.login_rounded,
                                                    size: buttonIconSize,
                                                  ),
                                                  const SizedBox(width: 8),
                                                  Text(
                                                    'ENTRAR',
                                                    style: TextStyle(
                                                      fontSize: buttonFontSize,
                                                      fontWeight:
                                                          FontWeight.w800,
                                                      letterSpacing: 1,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          SizedBox(height: isVerySmall ? 16 : 24),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.18),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color: olympusGold.withOpacity(0.16),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.shield_outlined,
                                  color: olympusGold,
                                  size: 16,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Olympus Voleibol © 2026',
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.78),
                                    fontSize: isVerySmall ? 10 : 12,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (_isLoading)
            Positioned.fill(
              child: Container(
                decoration: const BoxDecoration(
                  image: DecorationImage(
                    image: AssetImage('assets/images/monte_olimpo_v2.png'),
                    fit: BoxFit.cover,
                    alignment: Alignment.center,
                  ),
                ),
                child: Container(
                  color: Colors.black.withOpacity(0.65),
                  child: const Center(
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(olympusGold),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _FuturisticBackgroundPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final wavePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..color = const Color(0xFFD4AF37).withOpacity(0.07)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);

    final wavePaint2 = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..color = const Color(0xFF8FE8FF).withOpacity(0.06)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);

    final particlePaint = Paint()
      ..style = PaintingStyle.fill
      ..color = Colors.white.withOpacity(0.06);

    final glowParticlePaint = Paint()
      ..style = PaintingStyle.fill
      ..color = const Color(0xFFD4AF37).withOpacity(0.09)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);

    final path1 = Path();
    path1.moveTo(0, size.height * 0.18);
    path1.cubicTo(
      size.width * 0.20,
      size.height * 0.10,
      size.width * 0.35,
      size.height * 0.28,
      size.width * 0.52,
      size.height * 0.18,
    );
    path1.cubicTo(
      size.width * 0.68,
      size.height * 0.08,
      size.width * 0.82,
      size.height * 0.23,
      size.width,
      size.height * 0.15,
    );
    canvas.drawPath(path1, wavePaint);

    final path2 = Path();
    path2.moveTo(0, size.height * 0.80);
    path2.cubicTo(
      size.width * 0.18,
      size.height * 0.70,
      size.width * 0.36,
      size.height * 0.90,
      size.width * 0.56,
      size.height * 0.80,
    );
    path2.cubicTo(
      size.width * 0.74,
      size.height * 0.72,
      size.width * 0.86,
      size.height * 0.86,
      size.width,
      size.height * 0.78,
    );
    canvas.drawPath(path2, wavePaint2);

    final nodePaint = Paint()
      ..color = const Color(0xFFE8FCFF).withOpacity(0.12)
      ..style = PaintingStyle.fill;

    final linePaint = Paint()
      ..color = const Color(0xFFC7F6FF).withOpacity(0.10)
      ..strokeWidth = 1;

    final points = <Offset>[
      Offset(size.width * 0.72, size.height * 0.34),
      Offset(size.width * 0.82, size.height * 0.38),
      Offset(size.width * 0.90, size.height * 0.33),
      Offset(size.width * 0.76, size.height * 0.44),
      Offset(size.width * 0.88, size.height * 0.47),
      Offset(size.width * 0.69, size.height * 0.52),
      Offset(size.width * 0.83, size.height * 0.56),
      Offset(size.width * 0.93, size.height * 0.52),
      Offset(size.width * 0.73, size.height * 0.64),
      Offset(size.width * 0.86, size.height * 0.67),
    ];

    for (int i = 0; i < points.length - 1; i++) {
      canvas.drawLine(points[i], points[i + 1], linePaint);
    }
    canvas.drawLine(points[0], points[3], linePaint);
    canvas.drawLine(points[1], points[4], linePaint);
    canvas.drawLine(points[3], points[5], linePaint);
    canvas.drawLine(points[4], points[6], linePaint);
    canvas.drawLine(points[6], points[8], linePaint);
    canvas.drawLine(points[7], points[9], linePaint);

    for (final point in points) {
      canvas.drawCircle(point, 1.8, nodePaint);
    }

    final particles = <Offset>[
      Offset(size.width * 0.10, size.height * 0.12),
      Offset(size.width * 0.18, size.height * 0.20),
      Offset(size.width * 0.26, size.height * 0.15),
      Offset(size.width * 0.84, size.height * 0.18),
      Offset(size.width * 0.90, size.height * 0.24),
      Offset(size.width * 0.14, size.height * 0.72),
      Offset(size.width * 0.24, size.height * 0.82),
      Offset(size.width * 0.78, size.height * 0.78),
      Offset(size.width * 0.88, size.height * 0.70),
      Offset(size.width * 0.66, size.height * 0.14),
      Offset(size.width * 0.58, size.height * 0.22),
      Offset(size.width * 0.42, size.height * 0.86),
    ];

    for (final particle in particles) {
      canvas.drawCircle(particle, 1.6, particlePaint);
    }

    final glowParticles = <Offset>[
      Offset(size.width * 0.20, size.height * 0.30),
      Offset(size.width * 0.76, size.height * 0.26),
      Offset(size.width * 0.82, size.height * 0.62),
      Offset(size.width * 0.32, size.height * 0.74),
    ];

    for (final particle in glowParticles) {
      canvas.drawCircle(particle, 2.4, glowParticlePaint);
    }

    final glowPaint = Paint()
      ..color = const Color(0xFFD4AF37).withOpacity(0.05)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 26);

    canvas.drawCircle(
      Offset(size.width * 0.20, size.height * 0.25),
      70,
      glowPaint,
    );
    canvas.drawCircle(
      Offset(size.width * 0.78, size.height * 0.55),
      90,
      glowPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
