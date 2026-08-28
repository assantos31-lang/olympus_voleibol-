import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/organization_context_service.dart';
import '../theme/olympus_theme.dart';

class PlatformLoginBrandingPage extends StatefulWidget {
  const PlatformLoginBrandingPage({super.key});

  @override
  State<PlatformLoginBrandingPage> createState() =>
      _PlatformLoginBrandingPageState();
}

class _PlatformLoginBrandingPageState extends State<PlatformLoginBrandingPage> {
  static const _olympusOrganizationId =
      OrganizationContextService.olympusOrganizationId;

  final _supabase = Supabase.instance.client;
  final _picker = ImagePicker();
  late final OlympusBranding _initial;
  late OlympusBranding _draft;
  late final TextEditingController _nameController;
  late final TextEditingController _primaryController;
  late final TextEditingController _secondaryController;
  late final TextEditingController _logoController;
  late final TextEditingController _backgroundController;
  bool _uploadingLogo = false;
  bool _uploadingBackground = false;
  bool _saving = false;
  bool _saved = false;

  @override
  void initState() {
    super.initState();
    _initial = PublicAppBrandingController.instance.branding;
    _draft = _initial;
    _nameController = TextEditingController(text: _draft.teamName);
    _primaryController = TextEditingController(text: _draft.primaryHex);
    _secondaryController = TextEditingController(text: _draft.secondaryHex);
    _logoController = TextEditingController(text: _draft.logoUrl);
    _backgroundController = TextEditingController(
      text: _draft.backgroundImageUrl,
    );
  }

  @override
  void dispose() {
    if (!_saved) PublicAppBrandingController.instance.preview(_initial);
    _nameController.dispose();
    _primaryController.dispose();
    _secondaryController.dispose();
    _logoController.dispose();
    _backgroundController.dispose();
    super.dispose();
  }

  bool _validHex(String value) =>
      RegExp(r'^#[0-9A-Fa-f]{6}$').hasMatch(value.trim());

  void _update(OlympusBranding value) {
    setState(() => _draft = value);
    PublicAppBrandingController.instance.preview(value);
  }

  void _applyFields() {
    if (!_validHex(_primaryController.text) ||
        !_validHex(_secondaryController.text)) {
      _snack('Use as cores no formato #RRGGBB.');
      return;
    }
    _update(
      _draft.copyWith(
        teamName: _nameController.text.trim().isEmpty
            ? 'Olympus Voleibol'
            : _nameController.text.trim(),
        primaryHex: _primaryController.text.trim().toUpperCase(),
        secondaryHex: _secondaryController.text.trim().toUpperCase(),
        logoUrl: _logoController.text.trim(),
        backgroundImageUrl: _backgroundController.text.trim(),
      ),
    );
  }

  Future<void> _selectImage({required bool background}) async {
    final image = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 90,
      maxWidth: background ? 2400 : 1000,
    );
    if (image == null) return;
    setState(() {
      if (background) {
        _uploadingBackground = true;
      } else {
        _uploadingLogo = true;
      }
    });

    try {
      final source = await image.readAsBytes();
      Uint8List bytes = source;
      var extension = image.name.toLowerCase().endsWith('.png') ? 'png' : 'jpg';

      if (background) {
        final decoded = img.decodeImage(source);
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
        final resized = img.copyResize(
          cropped,
          width: 1080,
          height: 2400,
          interpolation: img.Interpolation.cubic,
        );
        bytes = Uint8List.fromList(img.encodeJpg(resized, quality: 90));
        extension = 'jpg';
      }

      final kind = background ? 'background' : 'logo';
      final path = 'organizations/$_olympusOrganizationId/platform-login/'
          '${kind}_${DateTime.now().millisecondsSinceEpoch}.$extension';
      await _supabase.storage.from('avatars').uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(
              upsert: true,
              contentType: extension == 'png' ? 'image/png' : 'image/jpeg',
            ),
          );
      final url = _supabase.storage.from('avatars').getPublicUrl(path);
      if (background) {
        _backgroundController.text = url;
        _update(
          _draft.copyWith(
            backgroundImageUrl: url,
            useBackgroundImage: true,
          ),
        );
      } else {
        _logoController.text = url;
        _update(_draft.copyWith(logoUrl: url));
      }
    } catch (error) {
      _snack('Não foi possível enviar a imagem: $error');
    } finally {
      if (mounted) {
        setState(() {
          _uploadingLogo = false;
          _uploadingBackground = false;
        });
      }
    }
  }

  void _restoreOlympusPreview() {
    const olympus = OlympusBranding();
    _nameController.text = olympus.teamName;
    _primaryController.text = olympus.primaryHex;
    _secondaryController.text = olympus.secondaryHex;
    _logoController.text = olympus.logoUrl;
    _backgroundController.text = olympus.backgroundImageUrl;
    _update(olympus);
  }

  Future<void> _save() async {
    if (_saving) return;
    _applyFields();
    if (!_validHex(_primaryController.text) ||
        !_validHex(_secondaryController.text)) return;
    setState(() => _saving = true);
    try {
      await PublicAppBrandingController.instance.save(_draft);
      _saved = true;
      if (!mounted) return;
      _snack('Tela inicial publicada com sucesso.');
      Navigator.pop(context, true);
    } catch (error) {
      _snack('Não foi possível publicar a tela inicial: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tela inicial do aplicativo'),
        actions: [
          IconButton(
            tooltip: 'Restaurar Olympus',
            onPressed: _restoreOlympusPreview,
            icon: const Icon(Icons.restart_alt_rounded),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 110),
        children: [
          Card(
            color: Theme.of(context).colorScheme.primaryContainer,
            child: const Padding(
              padding: EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline_rounded),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Esta é a tela pública exibida antes do login. Ela não '
                      'altera o Olympus nem a identidade dos outros clubes. '
                      'Após o login, cada usuário verá a marca do próprio time.',
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          _preview(),
          const SizedBox(height: 16),
          TextField(
            controller: _nameController,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Nome exibido na tela inicial',
              prefixIcon: Icon(Icons.badge_rounded),
            ),
            onChanged: (_) => _applyFields(),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _colorField(_primaryController, 'Principal')),
              const SizedBox(width: 10),
              Expanded(child: _colorField(_secondaryController, 'Destaque')),
            ],
          ),
          const SizedBox(height: 18),
          _imageSection(
            title: 'Logotipo da tela inicial',
            controller: _logoController,
            loading: _uploadingLogo,
            onSelect: () => _selectImage(background: false),
          ),
          const SizedBox(height: 18),
          _imageSection(
            title: 'Imagem de fundo da tela inicial',
            controller: _backgroundController,
            loading: _uploadingBackground,
            onSelect: () => _selectImage(background: true),
            measure:
                'Medida exata: 1080 × 2400 px • Proporção 9:20 • JPG ou PNG. '
                'O app recorta e ajusta automaticamente.',
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Exibir imagem de fundo'),
            value: _draft.useBackgroundImage,
            onChanged: (value) =>
                _update(_draft.copyWith(useBackgroundImage: value)),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.publish_rounded),
            label: Text(_saving ? 'Publicando...' : 'Publicar tela inicial'),
          ),
        ),
      ),
    );
  }

  Widget _colorField(TextEditingController controller, String label) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(labelText: 'Cor $label'),
      onChanged: (_) => _applyFields(),
    );
  }

  Widget _imageSection({
    required String title,
    required TextEditingController controller,
    required bool loading,
    required VoidCallback onSelect,
    String? measure,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
            if (measure != null) ...[
              const SizedBox(height: 6),
              Text(measure, style: Theme.of(context).textTheme.bodySmall),
            ],
            const SizedBox(height: 10),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: 'URL da imagem',
                prefixIcon: Icon(Icons.link_rounded),
              ),
              onChanged: (_) => _applyFields(),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: loading ? null : onSelect,
              icon: loading
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.add_photo_alternate_rounded),
              label: Text(loading ? 'Enviando...' : 'Selecionar imagem'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _preview() {
    Widget background = ColoredBox(color: _draft.primaryColor);
    if (_draft.useBackgroundImage) {
      if (_draft.backgroundImageUrl.isNotEmpty) {
        background = Image.network(
          _draft.backgroundImageUrl,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => ColoredBox(color: _draft.primaryColor),
        );
      } else {
        background = Image.asset(_draft.backgroundAsset, fit: BoxFit.cover);
      }
    }
    return AspectRatio(
      aspectRatio: 9 / 16,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Stack(
          fit: StackFit.expand,
          children: [
            background,
            ColoredBox(color: _draft.primaryColor.withValues(alpha: .56)),
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 104,
                    height: 104,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _draft.secondaryColor,
                    ),
                    padding: const EdgeInsets.all(4),
                    child: ClipOval(
                      child: _draft.logoUrl.isEmpty
                          ? Image.asset('assets/images/olympus_logo.png')
                          : Image.network(
                              _draft.logoUrl,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Image.asset(
                                'assets/images/olympus_logo.png',
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _draft.teamName.toUpperCase(),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 24,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Faça login para acessar o sistema',
                    style:
                        TextStyle(color: Colors.white.withValues(alpha: .86)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
