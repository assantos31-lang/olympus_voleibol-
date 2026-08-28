import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/organization_context_service.dart';

@immutable
class OlympusBranding {
  const OlympusBranding({
    this.teamName = 'Olympus Voleibol',
    this.primaryHex = '#1E3A5F',
    this.secondaryHex = '#D4AF37',
    this.backgroundHex = '#F4F7FB',
    this.surfaceHex = '#FFFDF8',
    this.textHex = '#172338',
    this.logoUrl = '',
    this.backgroundImageUrl = '',
    this.backgroundAsset = 'assets/images/monte_olimpo_v2.png',
    this.useBackgroundImage = true,
    this.backgroundOverlay = 0.64,
    this.cardRadius = 18,
  });

  final String teamName;
  final String primaryHex;
  final String secondaryHex;
  final String backgroundHex;
  final String surfaceHex;
  final String textHex;
  final String logoUrl;
  final String backgroundImageUrl;
  final String backgroundAsset;
  final bool useBackgroundImage;
  final double backgroundOverlay;
  final double cardRadius;

  Color get primaryColor => colorFromHex(primaryHex, const Color(0xFF1E3A5F));
  Color get secondaryColor =>
      colorFromHex(secondaryHex, const Color(0xFFD4AF37));
  Color get backgroundColor =>
      colorFromHex(backgroundHex, const Color(0xFFF4F7FB));
  Color get surfaceColor => colorFromHex(surfaceHex, const Color(0xFFFFFDF8));
  Color get textColor => colorFromHex(textHex, const Color(0xFF172338));

  static Color colorFromHex(String value, Color fallback) {
    final normalized = value.trim().replaceFirst('#', '');
    final hex = normalized.length == 6 ? 'FF$normalized' : normalized;
    if (hex.length != 8) return fallback;
    return Color(int.tryParse(hex, radix: 16) ?? fallback.toARGB32());
  }

  static String colorToHex(Color color) {
    final value = color.toARGB32() & 0xFFFFFF;
    return '#${value.toRadixString(16).padLeft(6, '0').toUpperCase()}';
  }

  factory OlympusBranding.fromMap(Map<String, dynamic>? map) {
    if (map == null || map.isEmpty) return const OlympusBranding();
    return OlympusBranding(
      teamName: (map['team_name'] ?? 'Olympus Voleibol').toString().trim(),
      primaryHex: (map['primary_color'] ?? '#1E3A5F').toString(),
      secondaryHex: (map['secondary_color'] ?? '#D4AF37').toString(),
      backgroundHex: (map['background_color'] ?? '#F4F7FB').toString(),
      surfaceHex: (map['surface_color'] ?? '#FFFDF8').toString(),
      textHex: (map['text_color'] ?? '#172338').toString(),
      logoUrl: (map['logo_url'] ?? '').toString().trim(),
      backgroundImageUrl: (map['background_image_url'] ?? '').toString().trim(),
      backgroundAsset:
          (map['background_asset'] ?? 'assets/images/monte_olimpo_v2.png')
              .toString(),
      useBackgroundImage: map['use_background_image'] != false,
      backgroundOverlay:
          ((map['background_overlay'] as num?)?.toDouble() ?? 0.64)
              .clamp(0.0, 0.9)
              .toDouble(),
      cardRadius: ((map['card_radius'] as num?)?.toDouble() ?? 18)
          .clamp(8.0, 32.0)
          .toDouble(),
    );
  }

  Map<String, dynamic> toMap() => {
        'team_name': teamName,
        'primary_color': primaryHex,
        'secondary_color': secondaryHex,
        'background_color': backgroundHex,
        'surface_color': surfaceHex,
        'text_color': textHex,
        'logo_url': logoUrl,
        'background_image_url': backgroundImageUrl,
        'background_asset': backgroundAsset,
        'use_background_image': useBackgroundImage,
        'background_overlay': backgroundOverlay,
        'card_radius': cardRadius,
      };

  OlympusBranding copyWith({
    String? teamName,
    String? primaryHex,
    String? secondaryHex,
    String? backgroundHex,
    String? surfaceHex,
    String? textHex,
    String? logoUrl,
    String? backgroundImageUrl,
    String? backgroundAsset,
    bool? useBackgroundImage,
    double? backgroundOverlay,
    double? cardRadius,
  }) {
    return OlympusBranding(
      teamName: teamName ?? this.teamName,
      primaryHex: primaryHex ?? this.primaryHex,
      secondaryHex: secondaryHex ?? this.secondaryHex,
      backgroundHex: backgroundHex ?? this.backgroundHex,
      surfaceHex: surfaceHex ?? this.surfaceHex,
      textHex: textHex ?? this.textHex,
      logoUrl: logoUrl ?? this.logoUrl,
      backgroundImageUrl: backgroundImageUrl ?? this.backgroundImageUrl,
      backgroundAsset: backgroundAsset ?? this.backgroundAsset,
      useBackgroundImage: useBackgroundImage ?? this.useBackgroundImage,
      backgroundOverlay: backgroundOverlay ?? this.backgroundOverlay,
      cardRadius: cardRadius ?? this.cardRadius,
    );
  }

  ThemeData toThemeData() {
    final primary = primaryColor;
    final secondary = secondaryColor;
    final surface = surfaceColor;
    final text = textColor;
    final onPrimary = _readableOnColor(primary);
    final onSecondary = _readableOnColor(secondary);
    final textTheme = ThemeData.light().textTheme.apply(
          bodyColor: text,
          displayColor: text,
        );
    final scheme = ColorScheme.fromSeed(
      seedColor: primary,
      brightness: Brightness.light,
    ).copyWith(
      primary: primary,
      onPrimary: onPrimary,
      secondary: secondary,
      onSecondary: onSecondary,
      surface: surface,
      onSurface: text,
      error: const Color(0xFFC62828),
    );

    final rounded = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(cardRadius),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      textTheme: textTheme,
      primaryTextTheme: textTheme.apply(
        bodyColor: onPrimary,
        displayColor: onPrimary,
      ),
      // O fundo institucional é desenhado uma única vez abaixo do Navigator.
      // Scaffolds sem cor própria refletem automaticamente a imagem do clube.
      scaffoldBackgroundColor: Colors.transparent,
      canvasColor: backgroundColor,
      splashColor: secondary.withValues(alpha: 0.14),
      highlightColor: secondary.withValues(alpha: 0.08),
      appBarTheme: AppBarTheme(
        backgroundColor: primary,
        foregroundColor: onPrimary,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        iconTheme: IconThemeData(color: onPrimary),
        actionsIconTheme: IconThemeData(color: secondary),
        titleTextStyle: TextStyle(
          color: onPrimary,
          fontSize: 20,
          fontWeight: FontWeight.w800,
        ),
      ),
      cardTheme: CardThemeData(
        color: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 2,
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        shape: rounded,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: rounded,
        titleTextStyle: TextStyle(
          color: primary,
          fontSize: 20,
          fontWeight: FontWeight.w900,
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        modalBackgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(cardRadius + 6),
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: primary,
        contentTextStyle: const TextStyle(color: Colors.white),
        actionTextColor: secondary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        labelStyle: TextStyle(color: primary),
        hintStyle: TextStyle(color: text.withValues(alpha: 0.62)),
        prefixIconColor: primary,
        suffixIconColor: primary,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 15,
          vertical: 14,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: BorderSide(color: primary.withValues(alpha: 0.18)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: BorderSide(color: secondary, width: 1.8),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: const BorderSide(color: Color(0xFFC62828)),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primary,
          side: BorderSide(color: primary.withValues(alpha: 0.48)),
          minimumSize: const Size(48, 46),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primary,
          textStyle: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: secondary,
        foregroundColor: _readableOnColor(secondary),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: surface,
        selectedColor: primary,
        checkmarkColor: secondary,
        side: BorderSide(color: primary.withValues(alpha: 0.20)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        labelStyle: TextStyle(color: primary, fontWeight: FontWeight.w700),
        secondaryLabelStyle: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? secondary
              : const Color(0xFFE1E5EA),
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? primary
              : const Color(0xFF8993A0),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: secondary,
        linearTrackColor: primary.withValues(alpha: 0.12),
        circularTrackColor: primary.withValues(alpha: 0.12),
      ),
      dividerTheme: DividerThemeData(
        color: primary.withValues(alpha: 0.13),
        thickness: 1,
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: primary,
        textColor: text,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface,
        indicatorColor: secondary.withValues(alpha: 0.24),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color:
                states.contains(WidgetState.selected) ? primary : Colors.grey,
          ),
        ),
      ),
    );
  }

  static Color _readableOnColor(Color color) {
    return ThemeData.estimateBrightnessForColor(color) == Brightness.dark
        ? Colors.white
        : const Color(0xFF102845);
  }
}

class OlympusBrandingController extends ChangeNotifier {
  OlympusBrandingController._();

  static final OlympusBrandingController instance =
      OlympusBrandingController._();
  static const String settingsKey = 'app_branding';
  static const String _cachePrefix = 'organization_branding_v1_';
  static const String _lastOrganizationKey = 'last_login_organization_id_v1';

  final SupabaseClient _client = Supabase.instance.client;
  OlympusBranding _branding = const OlympusBranding();
  RealtimeChannel? _channel;
  String? _channelOrganizationId;
  Future<void>? _initialization;
  bool _hasRememberedOrganization = false;

  OlympusBranding get branding => _branding;
  bool get hasRememberedOrganization => _hasRememberedOrganization;

  Future<void> initialize({bool force = false}) {
    if (!force && _initialization != null) return _initialization!;
    final operation = _load();
    _initialization = operation;
    return operation;
  }

  Future<void> _load() async {
    if (_client.auth.currentUser == null) {
      final preferences = await SharedPreferences.getInstance();
      final rememberedId =
          preferences.getString(_lastOrganizationKey)?.trim() ?? '';
      if (rememberedId.isNotEmpty) {
        _hasRememberedOrganization = true;
        await _restoreCache(rememberedId);
      }
      return;
    }

    final organization = await OrganizationContextService.instance.initialize(
      force: true,
    );
    final organizationId =
        organization?.id ?? OrganizationContextService.instance.currentId;

    _hasRememberedOrganization = true;
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_lastOrganizationKey, organizationId);
    await _restoreCache(organizationId);

    try {
      final row = await _client
          .from('organization_settings')
          .select('value')
          .eq('organization_id', organizationId)
          .eq('key', settingsKey)
          .maybeSingle();
      final value = row?['value'];
      if (value is Map) {
        final next = OlympusBranding.fromMap(Map<String, dynamic>.from(value));
        _setBranding(next);
        await _saveCache(organizationId, next);
      } else if (organization != null && organization.branding.isNotEmpty) {
        final next = OlympusBranding.fromMap(organization.branding);
        _setBranding(next);
        await _saveCache(organizationId, next);
      }
      unawaited(_listenForChanges(organizationId));
    } catch (error) {
      debugPrint('Não foi possível carregar a identidade visual: $error');
    }
  }

  void preview(OlympusBranding value) => _setBranding(value);

  Future<void> save(OlympusBranding value) async {
    final organization = await OrganizationContextService.instance.initialize(
      force: true,
    );
    final organizationId =
        organization?.id ?? OrganizationContextService.instance.currentId;
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      throw StateError('Administrador não autenticado.');
    }
    if (organization == null || !organization.canManage) {
      throw StateError('Usuário sem permissão para alterar este clube.');
    }

    await _client.from('organization_settings').upsert({
      'organization_id': organizationId,
      'key': settingsKey,
      'value': value.toMap(),
      'updated_at': DateTime.now().toIso8601String(),
      'updated_by': userId,
    }, onConflict: 'organization_id,key');

    await _client.from('organizations').update({
      'branding': value.toMap(),
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', organizationId);

    await _saveCache(organizationId, value);
    _setBranding(value);
  }

  void restoreDefaultPreview() => _setBranding(const OlympusBranding());

  void _setBranding(OlympusBranding value) {
    _branding = value;
    notifyListeners();
  }

  Future<void> _listenForChanges(String organizationId) async {
    if (_channel != null && _channelOrganizationId == organizationId) return;
    if (_channel != null) {
      await _client.removeChannel(_channel!);
    }

    _channelOrganizationId = organizationId;
    _channel = _client.channel('app-branding-live-$organizationId')
      ..onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'organization_settings',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'organization_id',
          value: organizationId,
        ),
        callback: (payload) {
          if ((payload.newRecord['key'] ?? '').toString() != settingsKey) {
            return;
          }
          final raw = payload.newRecord['value'];
          if (raw is Map) {
            final next = OlympusBranding.fromMap(
              Map<String, dynamic>.from(raw),
            );
            _setBranding(next);
            unawaited(_saveCache(organizationId, next));
          }
        },
      )
      ..subscribe();
  }

  Future<void> _restoreCache(String organizationId) async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final raw = preferences.getString('$_cachePrefix$organizationId');
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        _setBranding(
          OlympusBranding.fromMap(Map<String, dynamic>.from(decoded)),
        );
      }
    } catch (error) {
      debugPrint('Não foi possível restaurar a identidade em cache: $error');
    }
  }

  Future<void> _saveCache(String organizationId, OlympusBranding value) async {
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(
        '$_cachePrefix$organizationId',
        jsonEncode(value.toMap()),
      );
    } catch (error) {
      debugPrint('Não foi possível salvar a identidade em cache: $error');
    }
  }

  Future<void> reset() async {
    if (_channel != null) {
      await _client.removeChannel(_channel!);
    }
    _channel = null;
    _channelOrganizationId = null;
    _initialization = null;
    // Mantém no login a identidade do último time usado neste aparelho.
    notifyListeners();
  }
}

class PublicAppBrandingController extends ChangeNotifier {
  PublicAppBrandingController._();

  static final PublicAppBrandingController instance =
      PublicAppBrandingController._();
  static const String _cacheKey = 'public_login_branding_v1';

  final SupabaseClient _client = Supabase.instance.client;
  OlympusBranding _branding = const OlympusBranding();
  Future<void>? _initialization;

  OlympusBranding get branding => _branding;

  Future<void> initialize({bool force = false}) {
    if (!force && _initialization != null) return _initialization!;
    final operation = _load();
    _initialization = operation;
    return operation;
  }

  Future<void> _load() async {
    await _restoreCache();
    try {
      final value = await _client.rpc('get_public_login_branding_v1');
      if (value is Map) {
        final next = OlympusBranding.fromMap(
          Map<String, dynamic>.from(value),
        );
        await _setBranding(next, persist: true);
      }
    } catch (error) {
      debugPrint('Não foi possível carregar a tela inicial pública: $error');
    }
  }

  Future<void> save(OlympusBranding value) async {
    if (_client.auth.currentUser == null) {
      throw StateError('Administrador Master não autenticado.');
    }
    await _client.rpc(
      'platform_set_public_login_branding_v1',
      params: {'p_branding': value.toMap()},
    );
    await _setBranding(value, persist: true);
  }

  void preview(OlympusBranding value) {
    _branding = value;
    notifyListeners();
  }

  Future<void> restoreOlympus() => save(const OlympusBranding());

  Future<void> _restoreCache() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final raw = preferences.getString(_cacheKey);
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        _branding = OlympusBranding.fromMap(
          Map<String, dynamic>.from(decoded),
        );
        notifyListeners();
      }
    } catch (error) {
      debugPrint('Não foi possível restaurar a tela inicial em cache: $error');
    }
  }

  Future<void> _setBranding(
    OlympusBranding value, {
    required bool persist,
  }) async {
    _branding = value;
    if (persist) {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(_cacheKey, jsonEncode(value.toMap()));
    }
    notifyListeners();
  }
}

class OlympusBrandedBackground extends StatelessWidget {
  const OlympusBrandedBackground({
    super.key,
    required this.child,
    this.padding,
    this.showImage = true,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final bool showImage;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: OlympusBrandingController.instance,
      builder: (context, _) {
        final branding = OlympusBrandingController.instance.branding;
        return Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: branding.backgroundColor),
            if (showImage && branding.useBackgroundImage)
              _BrandBackgroundImage(branding: branding),
            if (showImage && branding.useBackgroundImage)
              ColoredBox(
                color: branding.primaryColor.withValues(
                  alpha: branding.backgroundOverlay,
                ),
              ),
            SafeArea(
              top: false,
              child: Padding(padding: padding ?? EdgeInsets.zero, child: child),
            ),
          ],
        );
      },
    );
  }
}

/// Fundo institucional aplicado abaixo de todas as rotas do aplicativo.
class OlympusGlobalBackground extends StatelessWidget {
  const OlympusGlobalBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: OlympusBrandingController.instance,
      builder: (context, _) {
        final branding = OlympusBrandingController.instance.branding;
        return Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: branding.backgroundColor),
            if (branding.useBackgroundImage)
              _BrandBackgroundImage(branding: branding),
            if (branding.useBackgroundImage)
              ColoredBox(
                color: branding.primaryColor.withValues(
                  alpha: branding.backgroundOverlay,
                ),
              ),
            child,
          ],
        );
      },
    );
  }
}

/// Somente a imagem configurada para o clube, com o fundo padrão do Olympus
/// como alternativa caso a imagem remota fique indisponível.
class OlympusBrandBackgroundImage extends StatelessWidget {
  const OlympusBrandBackgroundImage({
    super.key,
    this.fit = BoxFit.cover,
    this.alignment = Alignment.center,
    this.width,
    this.height,
    this.errorBuilder,
  });

  final BoxFit fit;
  final AlignmentGeometry alignment;
  final double? width;
  final double? height;
  final ImageErrorWidgetBuilder? errorBuilder;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: OlympusBrandingController.instance,
      builder: (context, _) {
        final branding = OlympusBrandingController.instance.branding;
        Widget fallback() => Image.asset(
              branding.backgroundAsset,
              fit: fit,
              alignment: alignment,
              width: width,
              height: height,
              errorBuilder: errorBuilder ??
                  (_, __, ___) => ColoredBox(color: branding.primaryColor),
            );
        if (branding.backgroundImageUrl.isEmpty) return fallback();
        return Image.network(
          branding.backgroundImageUrl,
          fit: fit,
          alignment: alignment,
          width: width,
          height: height,
          errorBuilder: (_, __, ___) => fallback(),
        );
      },
    );
  }
}

class _BrandBackgroundImage extends StatelessWidget {
  const _BrandBackgroundImage({required this.branding});

  final OlympusBranding branding;

  @override
  Widget build(BuildContext context) {
    if (branding.backgroundImageUrl.isNotEmpty) {
      return Image.network(
        branding.backgroundImageUrl,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _assetFallback(),
      );
    }
    return _assetFallback();
  }

  Widget _assetFallback() {
    return Image.asset(
      branding.backgroundAsset,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
    );
  }
}
