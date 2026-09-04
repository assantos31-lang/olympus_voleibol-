import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/organization_context_service.dart';
import '../theme/olympus_theme.dart';

class AdminBrandingPage extends StatefulWidget {
  const AdminBrandingPage({super.key});

  @override
  State<AdminBrandingPage> createState() => _AdminBrandingPageState();
}

class _AdminBrandingPageState extends State<AdminBrandingPage> {
  static const List<Color> _primaryPresets = [
    Color(0xFF1E3A5F),
    Color(0xFF0A2463),
    Color(0xFF102845),
    Color(0xFF163A2B),
    Color(0xFF5A1738),
    Color(0xFF3D246C),
    Color(0xFF1F2937),
    Color(0xFF8B1E1E),
  ];

  static const List<Color> _secondaryPresets = [
    Color(0xFFD4AF37),
    Color(0xFFE4C050),
    Color(0xFFFFC857),
    Color(0xFF70E1F5),
    Color(0xFF73E2A7),
    Color(0xFFFF8FA3),
    Color(0xFFB29BFF),
    Color(0xFFFF8C42),
  ];

  static const List<Color> _textPresets = [
    Color(0xFF172338),
    Color(0xFF0F172A),
    Color(0xFF1F2937),
    Color(0xFF334155),
    Color(0xFF3F2D20),
    Color(0xFF4A1734),
    Color(0xFF102845),
    Color(0xFFFFFFFF),
  ];

  static const List<Color> _backgroundPresets = [
    Color(0xFFF4F7FB),
    Color(0xFFFFFDF8),
    Color(0xFFF2F0EA),
    Color(0xFFE8EEF5),
    Color(0xFFEAF4EF),
    Color(0xFF172338),
    Color(0xFF102845),
    Color(0xFF101A16),
  ];

  static const List<Color> _surfacePresets = [
    Color(0xFFFFFDF8),
    Color(0xFFF4F7FB),
    Color(0xFF1E3A5F),
    Color(0xFF0A2463),
    Color(0xFF163A2B),
    Color(0xFF5A1738),
    Color(0xFF3D246C),
    Color(0xFF1F2937),
  ];

  // Criada uma unica vez e exibida sob demanda. O GridView monta apenas as
  // cores visiveis, mantendo o painel leve mesmo com uma paleta ampla.
  static final List<Color> _completePalette = List<Color>.unmodifiable([
    for (final color in Colors.primaries) ...[
      color.shade100,
      color.shade300,
      color.shade500,
      color.shade700,
      color.shade900,
    ],
    for (final color in Colors.accents) ...[
      color.shade100,
      color.shade400,
      color.shade700,
    ],
    Colors.white,
    Colors.black,
    Colors.blueGrey.shade100,
    Colors.blueGrey.shade300,
    Colors.blueGrey.shade500,
    Colors.blueGrey.shade700,
    Colors.blueGrey.shade900,
    Colors.grey.shade100,
    Colors.grey.shade300,
    Colors.grey.shade500,
    Colors.grey.shade700,
    Colors.grey.shade900,
    Colors.brown.shade100,
    Colors.brown.shade300,
    Colors.brown.shade500,
    Colors.brown.shade700,
    Colors.brown.shade900,
  ]);

  final SupabaseClient _supabase = Supabase.instance.client;
  final ImagePicker _picker = ImagePicker();
  late final OlympusBranding _initialBranding;
  late OlympusBranding _draft;
  late final TextEditingController _teamNameController;
  late final TextEditingController _primaryController;
  late final TextEditingController _secondaryController;
  late final TextEditingController _backgroundController;
  late final TextEditingController _surfaceController;
  late final TextEditingController _textController;
  late final TextEditingController _fieldTitleController;
  late final TextEditingController _logoController;
  late final TextEditingController _backgroundImageController;
  bool _saving = false;
  bool _uploadingLogo = false;
  bool _uploadingBackground = false;
  bool _saved = false;

  @override
  void initState() {
    super.initState();
    _initialBranding = OlympusBrandingController.instance.branding;
    _draft = _initialBranding;
    _teamNameController = TextEditingController(text: _draft.teamName);
    _primaryController = TextEditingController(text: _draft.primaryHex);
    _secondaryController = TextEditingController(text: _draft.secondaryHex);
    _backgroundController = TextEditingController(text: _draft.backgroundHex);
    _surfaceController = TextEditingController(text: _draft.surfaceHex);
    _textController = TextEditingController(text: _draft.textHex);
    _fieldTitleController = TextEditingController(text: _draft.fieldTitleHex);
    _logoController = TextEditingController(text: _draft.logoUrl);
    _backgroundImageController = TextEditingController(
      text: _draft.backgroundImageUrl,
    );
  }

  @override
  void dispose() {
    if (!_saved) {
      OlympusBrandingController.instance.preview(_initialBranding);
    }
    _teamNameController.dispose();
    _primaryController.dispose();
    _secondaryController.dispose();
    _backgroundController.dispose();
    _surfaceController.dispose();
    _textController.dispose();
    _fieldTitleController.dispose();
    _logoController.dispose();
    _backgroundImageController.dispose();
    super.dispose();
  }

  void _updateDraft(OlympusBranding value) {
    setState(() => _draft = value);
    OlympusBrandingController.instance.preview(value);
  }

  bool _isValidHex(String value) {
    return RegExp(r'^#[0-9A-Fa-f]{6}$').hasMatch(value.trim());
  }

  void _applyHexFields() {
    final values = [
      _primaryController.text,
      _secondaryController.text,
      _backgroundController.text,
      _surfaceController.text,
      _textController.text,
      _fieldTitleController.text,
    ];
    if (values.any((value) => !_isValidHex(value))) {
      _showSnack('Use cores no formato #RRGGBB.');
      return;
    }
    _updateDraft(
      _draft.copyWith(
        teamName: _teamNameController.text.trim().isEmpty
            ? OrganizationContextService.instance.currentName
            : _teamNameController.text.trim(),
        primaryHex: _primaryController.text.toUpperCase(),
        secondaryHex: _secondaryController.text.toUpperCase(),
        backgroundHex: _backgroundController.text.toUpperCase(),
        surfaceHex: _surfaceController.text.toUpperCase(),
        textHex: _textController.text.toUpperCase(),
        fieldTitleHex: _fieldTitleController.text.toUpperCase(),
        logoUrl: _logoController.text.trim(),
        backgroundImageUrl: _backgroundImageController.text.trim(),
      ),
    );
  }

  Future<void> _uploadImage({required bool isBackground}) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) {
      _showSnack('Administrador não autenticado.');
      return;
    }

    final organization = await OrganizationContextService.instance.initialize(
      force: true,
    );
    if (organization == null || !organization.canManage) {
      _showSnack('Administrador sem permissão para alterar este clube.');
      return;
    }

    final image = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 88,
      maxWidth: isBackground ? 1920 : 900,
    );
    if (image == null) return;

    setState(() {
      if (isBackground) {
        _uploadingBackground = true;
      } else {
        _uploadingLogo = true;
      }
    });

    try {
      final sourceBytes = await image.readAsBytes();
      final rawExtension = image.name.split('.').last.toLowerCase();
      var extension = rawExtension == 'png' ? 'png' : 'jpg';
      Uint8List bytes = sourceBytes;

      if (isBackground) {
        final decoded = img.decodeImage(sourceBytes);
        if (decoded == null) {
          throw const FormatException('Formato de imagem não suportado.');
        }

        final oriented = img.bakeOrientation(decoded);
        var cropWidth = oriented.width;
        var cropHeight = (cropWidth * 20 / 9).round();
        if (cropHeight > oriented.height) {
          cropHeight = oriented.height;
          cropWidth = (cropHeight * 9 / 20).round();
        }

        final cropped = img.copyCrop(
          oriented,
          x: (oriented.width - cropWidth) ~/ 2,
          y: (oriented.height - cropHeight) ~/ 2,
          width: cropWidth,
          height: cropHeight,
        );
        final normalized = img.copyResize(
          cropped,
          width: 1080,
          height: 2400,
          interpolation: img.Interpolation.cubic,
        );
        bytes = Uint8List.fromList(img.encodeJpg(normalized, quality: 90));
        extension = 'jpg';
      }
      final kind = isBackground ? 'background' : 'logo';
      final path =
          'organizations/${organization.id}/branding/${kind}_${DateTime.now().millisecondsSinceEpoch}.$extension';
      await _supabase.storage.from('avatars').uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(
              upsert: true,
              contentType: extension == 'png' ? 'image/png' : 'image/jpeg',
            ),
          );
      final url = _supabase.storage.from('avatars').getPublicUrl(path);
      if (isBackground) {
        _backgroundImageController.text = url;
        _updateDraft(
          _draft.copyWith(backgroundImageUrl: url, useBackgroundImage: true),
        );
      } else {
        _logoController.text = url;
        _updateDraft(_draft.copyWith(logoUrl: url));
      }
    } catch (error) {
      _showSnack('Não foi possível enviar a imagem: $error');
    } finally {
      if (mounted) {
        setState(() {
          _uploadingBackground = false;
          _uploadingLogo = false;
        });
      }
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    _applyHexFields();
    if (!_isValidHex(_primaryController.text) ||
        !_isValidHex(_secondaryController.text) ||
        !_isValidHex(_backgroundController.text) ||
        !_isValidHex(_surfaceController.text)) {
      return;
    }
    if (!_isValidHex(_fieldTitleController.text)) return;

    setState(() => _saving = true);
    try {
      await OlympusBrandingController.instance.save(_draft);
      _saved = true;
      if (!mounted) return;
      _showSnack(
        'Cores publicadas para Admin, Treinadores e Atletas deste clube.',
      );
      Navigator.pop(context, true);
    } catch (error) {
      _showSnack('Erro ao salvar identidade visual: $error');
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  void _restoreDefaults() {
    final defaults = const OlympusBranding().copyWith(
      teamName: OrganizationContextService.instance.currentName,
    );
    _teamNameController.text = defaults.teamName;
    _primaryController.text = defaults.primaryHex;
    _secondaryController.text = defaults.secondaryHex;
    _backgroundController.text = defaults.backgroundHex;
    _surfaceController.text = defaults.surfaceHex;
    _textController.text = defaults.textHex;
    _fieldTitleController.text = defaults.fieldTitleHex;
    _logoController.text = defaults.logoUrl;
    _backgroundImageController.text = defaults.backgroundImageUrl;
    _updateDraft(defaults);
  }

  void _showSnack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cores e identidade do clube'),
        actions: [
          IconButton(
            tooltip: 'Restaurar cores padrão',
            onPressed: _restoreDefaults,
            icon: const Icon(Icons.restart_alt_rounded),
          ),
        ],
      ),
      body: OlympusBrandedBackground(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 110),
          children: [
            _buildPreview(theme),
            _section(
              icon: Icons.badge_rounded,
              title: 'Clube e marca',
              subtitle: 'Nome e logotipo exibidos para todos os usuários.',
              child: Column(
                children: [
                  TextField(
                    controller: _teamNameController,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Nome do clube ou equipe',
                      prefixIcon: Icon(Icons.shield_rounded),
                    ),
                    onChanged: (value) => _updateDraft(
                      _draft.copyWith(
                        teamName: value.trim().isEmpty
                            ? OrganizationContextService.instance.currentName
                            : value.trim(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _logoController,
                    decoration: const InputDecoration(
                      labelText: 'URL do logotipo',
                      prefixIcon: Icon(Icons.image_rounded),
                    ),
                    onChanged: (value) =>
                        _updateDraft(_draft.copyWith(logoUrl: value.trim())),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _uploadingLogo
                          ? null
                          : () => _uploadImage(isBackground: false),
                      icon: _uploadingLogo
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.upload_rounded),
                      label: const Text('Selecionar logotipo'),
                    ),
                  ),
                ],
              ),
            ),
            _section(
              icon: Icons.palette_rounded,
              title: 'Cores do aplicativo',
              subtitle:
                  'Aplicadas aos perfis de Admin, Treinador e Atleta deste clube.',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _colorSelector(
                    title: 'Cor principal',
                    colors: _primaryPresets,
                    selected: _draft.primaryColor,
                    onSelected: (color) {
                      final hex = OlympusBranding.colorToHex(color);
                      _primaryController.text = hex;
                      _updateDraft(_draft.copyWith(primaryHex: hex));
                    },
                  ),
                  const SizedBox(height: 16),
                  _colorSelector(
                    title: 'Cor de destaque',
                    colors: _secondaryPresets,
                    selected: _draft.secondaryColor,
                    onSelected: (color) {
                      final hex = OlympusBranding.colorToHex(color);
                      _secondaryController.text = hex;
                      _updateDraft(_draft.copyWith(secondaryHex: hex));
                    },
                  ),
                  const SizedBox(height: 16),
                  _colorSelector(
                    title: 'Cor dos cartões',
                    subtitle:
                        'Define os cards de painéis, Estatísticas, Chat e Financeiro.',
                    colors: _surfacePresets,
                    selected: _draft.surfaceColor,
                    onSelected: (color) {
                      final hex = OlympusBranding.colorToHex(color);
                      _surfaceController.text = hex;
                      _updateDraft(_draft.copyWith(surfaceHex: hex));
                    },
                  ),
                  const SizedBox(height: 16),
                  _colorSelector(
                    title: 'Cor do fundo',
                    subtitle: 'Cor exibida quando não houver imagem de fundo.',
                    colors: _backgroundPresets,
                    selected: _draft.backgroundColor,
                    onSelected: (color) {
                      final hex = OlympusBranding.colorToHex(color);
                      _backgroundController.text = hex;
                      _updateDraft(_draft.copyWith(backgroundHex: hex));
                    },
                  ),
                  const SizedBox(height: 16),
                  _colorSelector(
                    title: 'Cor dos textos',
                    colors: _textPresets,
                    selected: _draft.textColor,
                    onSelected: (color) {
                      final hex = OlympusBranding.colorToHex(color);
                      _textController.text = hex;
                      _updateDraft(_draft.copyWith(textHex: hex));
                    },
                  ),
                  const SizedBox(height: 16),
                  _colorSelector(
                    title: 'Títulos sobre o fundo',
                    subtitle:
                        'Usada nos títulos posicionados acima dos cartões.',
                    colors: _textPresets,
                    selected: _draft.fieldTitleColor,
                    onSelected: (color) {
                      final hex = OlympusBranding.colorToHex(color);
                      _fieldTitleController.text = hex;
                      _updateDraft(_draft.copyWith(fieldTitleHex: hex));
                    },
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: _hexField(_primaryController, 'Principal'),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _hexField(_secondaryController, 'Destaque'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _hexField(_textController, 'Textos'),
                  const SizedBox(height: 10),
                  _hexField(_fieldTitleController, 'Títulos sobre o fundo'),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _hexField(_backgroundController, 'Fundo'),
                      ),
                      const SizedBox(width: 10),
                      Expanded(child: _hexField(_surfaceController, 'Cartões')),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: _applyHexFields,
                      icon: const Icon(Icons.check_circle_outline_rounded),
                      label: const Text('Aplicar códigos'),
                    ),
                  ),
                ],
              ),
            ),
            _section(
              icon: Icons.wallpaper_rounded,
              title: 'Imagem de fundo',
              subtitle:
                  'Use o fundo padrão ou envie a identidade do novo time.',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _draft.primaryColor.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _draft.primaryColor.withValues(alpha: 0.18),
                      ),
                    ),
                    child: const Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.straighten_rounded),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Tamanho exato: 1080 × 2400 px\n'
                            'Proporção: 9:20 • Formato: JPG ou PNG\n'
                            'A imagem será recortada e ajustada automaticamente '
                            'para evitar distorções. Mantenha pessoas, textos e '
                            'escudos na região central.',
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_draft.backgroundImageUrl.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: SizedBox(
                        height: 190,
                        child: Image.network(
                          _draft.backgroundImageUrl,
                          fit: BoxFit.cover,
                          alignment: Alignment.center,
                          errorBuilder: (_, __, ___) => const ColoredBox(
                            color: Color(0xFFE5E7EB),
                            child: Center(
                              child: Text('Não foi possível exibir o fundo.'),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Exibir imagem de fundo'),
                    subtitle: const Text(
                      'Aplicada às telas que usam fundo institucional.',
                    ),
                    value: _draft.useBackgroundImage,
                    onChanged: (value) => _updateDraft(
                      _draft.copyWith(useBackgroundImage: value),
                    ),
                  ),
                  TextField(
                    controller: _backgroundImageController,
                    decoration: const InputDecoration(
                      labelText: 'URL da imagem de fundo',
                      prefixIcon: Icon(Icons.link_rounded),
                    ),
                    onChanged: (value) => _updateDraft(
                      _draft.copyWith(backgroundImageUrl: value.trim()),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _uploadingBackground
                          ? null
                          : () => _uploadImage(isBackground: true),
                      icon: _uploadingBackground
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.add_photo_alternate_rounded),
                      label: Text(
                        _draft.backgroundImageUrl.isEmpty
                            ? 'Selecionar imagem de fundo'
                            : 'Alterar imagem de fundo',
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  _slider(
                    title: 'Escurecimento do fundo',
                    value: _draft.backgroundOverlay,
                    min: 0.20,
                    max: 0.85,
                    divisions: 13,
                    label: '${(_draft.backgroundOverlay * 100).round()}%',
                    onChanged: (value) =>
                        _updateDraft(_draft.copyWith(backgroundOverlay: value)),
                  ),
                  _slider(
                    title: 'Arredondamento dos cartões',
                    value: _draft.cardRadius,
                    min: 8,
                    max: 32,
                    divisions: 12,
                    label: '${_draft.cardRadius.round()} px',
                    onChanged: (value) =>
                        _updateDraft(_draft.copyWith(cardRadius: value)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          decoration: BoxDecoration(
            color: _draft.primaryColor,
            border: Border(top: BorderSide(color: _draft.secondaryColor)),
          ),
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: _draft.secondaryColor,
              foregroundColor:
                  ThemeData.estimateBrightnessForColor(_draft.secondaryColor) ==
                          Brightness.dark
                      ? Colors.white
                      : _draft.primaryColor,
            ),
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.publish_rounded),
            label: Text(
              _saving ? 'Publicando...' : 'Publicar identidade visual',
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPreview(ThemeData theme) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: _draft.surfaceColor,
        borderRadius: BorderRadius.circular(_draft.cardRadius + 6),
        border: Border.all(
          color: _draft.secondaryColor.withValues(alpha: 0.72),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.24),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            color: _draft.primaryColor,
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                _logoPreview(),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _draft.teamName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 19,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        'Pré-visualização ao vivo',
                        style: TextStyle(color: _draft.secondaryColor),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.notifications_rounded, color: _draft.secondaryColor),
              ],
            ),
          ),
          Container(
            width: double.infinity,
            color: _draft.backgroundColor,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
            child: Text(
              'Título acima do cartão',
              style: TextStyle(
                color: _draft.fieldTitleColor,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Cartões, botões e formulários seguem automaticamente esta identidade.',
                    style: TextStyle(color: _draft.primaryColor),
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: _draft.primaryColor,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () {},
                  child: const Text('Ação'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _logoPreview() {
    final fallback = Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: _draft.secondaryColor.withValues(alpha: 0.16),
      ),
      child: Icon(Icons.shield_rounded, color: _draft.secondaryColor),
    );
    if (_draft.logoUrl.isEmpty) return fallback;
    return ClipOval(
      child: Image.network(
        _draft.logoUrl,
        width: 52,
        height: 52,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => fallback,
      ),
    );
  }

  Widget _section({
    required IconData icon,
    required String title,
    required String subtitle,
    required Widget child,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: _draft.secondaryColor.withValues(
                    alpha: 0.17,
                  ),
                  foregroundColor: _draft.primaryColor,
                  child: Icon(icon),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                      Text(
                        subtitle,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }

  Widget _colorSelector({
    required String title,
    String? subtitle,
    required List<Color> colors,
    required Color selected,
    required ValueChanged<Color> onSelected,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
        if (subtitle != null) ...[
          const SizedBox(height: 3),
          Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
        ],
        const SizedBox(height: 9),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Theme.of(context).dividerColor),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: selected,
                  shape: BoxShape.circle,
                  border: Border.all(color: Theme.of(context).dividerColor),
                ),
              ),
              const SizedBox(width: 9),
              Text(
                'Cor atual: ${OlympusBranding.colorToHex(selected)}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: colors.map((color) {
            final isSelected = color.toARGB32() == selected.toARGB32();
            return InkWell(
              onTap: () => onSelected(color),
              borderRadius: BorderRadius.circular(999),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isSelected ? Colors.white : Colors.transparent,
                    width: 3,
                  ),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: color,
                            blurRadius: 10,
                            spreadRadius: 2,
                          ),
                        ]
                      : null,
                ),
                child: isSelected
                    ? Icon(
                        Icons.check_rounded,
                        color: ThemeData.estimateBrightnessForColor(color) ==
                                Brightness.dark
                            ? Colors.white
                            : Colors.black,
                      )
                    : null,
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: () => _openCompletePalette(
            title: title,
            selected: selected,
            onSelected: onSelected,
          ),
          icon: const Icon(Icons.color_lens_outlined),
          label: Text('Ver paleta completa (${_completePalette.length} cores)'),
        ),
      ],
    );
  }

  Future<void> _openCompletePalette({
    required String title,
    required Color selected,
    required ValueChanged<Color> onSelected,
  }) async {
    final palette =
        _completePalette.any((color) => color.toARGB32() == selected.toARGB32())
            ? _completePalette
            : <Color>[selected, ..._completePalette];
    final picked = await showModalBottomSheet<Color>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);
        return FractionallySizedBox(
          heightFactor: 0.82,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${palette.length} opções rápidas. A cor atual aparece primeiro quando for personalizada.',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 14),
                Expanded(
                  child: GridView.builder(
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 58,
                      mainAxisSpacing: 10,
                      crossAxisSpacing: 10,
                    ),
                    itemCount: palette.length,
                    itemBuilder: (context, index) {
                      final color = palette[index];
                      final isSelected =
                          color.toARGB32() == selected.toARGB32();
                      final foreground =
                          ThemeData.estimateBrightnessForColor(color) ==
                                  Brightness.dark
                              ? Colors.white
                              : Colors.black;
                      return Semantics(
                        button: true,
                        selected: isSelected,
                        label: 'Cor ${OlympusBranding.colorToHex(color)}',
                        child: Material(
                          color: color,
                          shape: CircleBorder(
                            side: BorderSide(
                              color: isSelected
                                  ? theme.colorScheme.primary
                                  : theme.dividerColor,
                              width: isSelected ? 4 : 1,
                            ),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            onTap: () => Navigator.pop(sheetContext, color),
                            child: isSelected
                                ? Icon(Icons.check_rounded, color: foreground)
                                : null,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (picked == null || !mounted) return;
    onSelected(picked);
  }

  Widget _hexField(TextEditingController controller, String label) {
    final valid = _isValidHex(controller.text);
    final color = OlympusBranding.colorFromHex(
      controller.text,
      Theme.of(context).disabledColor,
    );
    final markerColor =
        ThemeData.estimateBrightnessForColor(color) == Brightness.dark
            ? Colors.white
            : Colors.black;
    return TextField(
      controller: controller,
      textCapitalization: TextCapitalization.characters,
      maxLength: 7,
      decoration: InputDecoration(
        labelText: label,
        counterText: '',
        prefixIcon: Padding(
          padding: const EdgeInsets.all(13),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(color: Theme.of(context).dividerColor),
            ),
            child: valid
                ? Icon(Icons.check_rounded, size: 14, color: markerColor)
                : Icon(Icons.more_horiz_rounded, size: 14, color: markerColor),
          ),
        ),
      ),
      onChanged: (_) {
        if (mounted) setState(() {});
      },
      onSubmitted: (_) => _applyHexFields(),
    );
  }

  Widget _slider({
    required String title,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required String label,
    required ValueChanged<double> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            Text(label),
          ],
        ),
        Slider(
          value: value,
          min: min,
          max: max,
          divisions: divisions,
          label: label,
          onChanged: onChanged,
        ),
      ],
    );
  }
}
