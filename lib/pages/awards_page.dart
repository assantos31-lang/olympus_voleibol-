import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/award_models.dart';
import '../services/awards_service.dart';
import '../services/organization_context_service.dart';
import '../services/organization_storage_service.dart';
import '../theme/olympus_theme.dart';

class AwardsPage extends StatefulWidget {
  const AwardsPage({super.key, this.canManage = false});

  /// A permissao desta tela acompanha o perfil atualmente selecionado.
  /// O padrao seguro e somente leitura; apenas a Area Admin informa `true`.
  final bool canManage;

  @override
  State<AwardsPage> createState() => _AwardsPageState();
}

class _AwardsPageState extends State<AwardsPage> {
  final AwardsService _service = AwardsService();
  final SupabaseClient _supabase = Supabase.instance.client;
  final DateFormat _dateFormat = DateFormat('dd/MM/yyyy', 'pt_BR');
  final ImagePicker _picker = ImagePicker();

  bool _loading = true;
  bool _canManage = false;
  String? _error;
  List<AwardDefinition> _definitions = const [];
  List<AwardEdition> _editions = const [];
  late int _selectedYear;
  late int _selectedMonth;

  OlympusBranding get _branding => OlympusBrandingController.instance.branding;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedYear = now.year;
    _selectedMonth = now.month;
    _load();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final canManage = widget.canManage;
      final results = await Future.wait<dynamic>([
        _service.loadDefinitions(canManage: canManage),
        _service.loadEditions(canManage: canManage),
      ]);
      if (!mounted) return;
      setState(() {
        _canManage = canManage;
        _definitions = results[0] as List<AwardDefinition>;
        _editions = results[1] as List<AwardEdition>;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString().contains('award_')
            ? 'O módulo de premiações ainda não foi ativado no banco de dados.'
            : 'Não foi possível carregar as premiações.';
      });
    }
  }

  List<AwardEdition> get _visiblePeriodEditions => _editions
      .where(
          (item) => item.year == _selectedYear && item.month == _selectedMonth)
      .toList();

  List<int> get _availableYears {
    final years = <int>{DateTime.now().year, ..._editions.map((e) => e.year)}
        .toList()
      ..sort((a, b) => b.compareTo(a));
    return years;
  }

  Future<ImageSource?> _chooseImageSource() =>
      showModalBottomSheet<ImageSource>(
        context: context,
        builder: (context) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_camera_rounded),
                title: const Text('Tirar foto'),
                onTap: () => Navigator.pop(context, ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_rounded),
                title: const Text('Escolher da galeria'),
                onTap: () => Navigator.pop(context, ImageSource.gallery),
              ),
            ],
          ),
        ),
      );

  Future<String?> _pickAndUploadImage(String folder) async {
    final source = await _chooseImageSource();
    if (source == null) return null;
    final file = await _picker.pickImage(source: source, imageQuality: 95);
    if (file == null) return null;

    final organization =
        await OrganizationContextService.instance.initialize(force: true);
    if (organization == null) throw StateError('Clube ativo não encontrado.');
    final decoded = img.decodeImage(await file.readAsBytes());
    if (decoded == null) throw const FormatException('Imagem não suportada.');
    final oriented = img.bakeOrientation(decoded);
    const maxSide = 1800;
    final normalized = oriented.width >= oriented.height
        ? oriented.width > maxSide
            ? img.copyResize(oriented, width: maxSide)
            : oriented
        : oriented.height > maxSide
            ? img.copyResize(oriented, height: maxSide)
            : oriented;
    final bytes = Uint8List.fromList(img.encodeJpg(normalized, quality: 88));
    final path = OrganizationStorageService.scopedPath(
      'awards/$folder/${DateTime.now().millisecondsSinceEpoch}.jpg',
    );
    await _supabase.storage.from('event-images').uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(
            upsert: true,
            contentType: 'image/jpeg',
          ),
        );
    return _supabase.storage.from('event-images').getPublicUrl(path);
  }

  void _showMessage(String text, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        backgroundColor: error ? Theme.of(context).colorScheme.error : null,
      ),
    );
  }

  Future<void> _openDefinitionForm([AwardDefinition? definition]) async {
    final saved = await Navigator.push<_AwardDefinitionFormResult>(
      context,
      MaterialPageRoute(
        builder: (_) => AwardDefinitionFormPage(
          definition: definition,
          initialYear: _selectedYear,
          initialMonth: _selectedMonth,
          uploadImage: () => _pickAndUploadImage('covers'),
        ),
      ),
    );
    if (saved == null) return;
    _selectedYear = saved.year;
    _selectedMonth = saved.month;
    await _load();
  }

  Future<void> _openEditionForm({
    AwardDefinition? definition,
    AwardEdition? edition,
  }) async {
    if (_definitions.isEmpty) {
      _showMessage('Crie primeiro um tipo de premiação.', error: true);
      return;
    }
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => AwardEditionFormPage(
          definitions: _definitions,
          initialDefinition: definition,
          edition: edition,
          initialYear: _selectedYear,
          initialMonth: _selectedMonth,
          uploadImage: () => _pickAndUploadImage('deliveries'),
        ),
      ),
    );
    if (saved == true) await _load();
  }

  Future<bool> _confirmDelete(String title, String body) async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(title),
            content: Text(body),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.error,
                ),
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Excluir'),
              ),
            ],
          ),
        ) ==
        true;
  }

  Future<void> _deleteDefinition(AwardDefinition item) async {
    final confirmed = await _confirmDelete(
      'Excluir tipo de premiação?',
      'As edições mensais e os vencedores de “${item.title}” também serão excluídos.',
    );
    if (!confirmed) return;
    try {
      await _service.deleteDefinition(item.id);
      await _load();
      _showMessage('Tipo de premiação excluído.');
    } catch (_) {
      _showMessage('Não foi possível excluir a premiação.', error: true);
    }
  }

  Future<void> _deleteEdition(AwardEdition item) async {
    final confirmed = await _confirmDelete(
      'Excluir entrega?',
      'A foto, a legenda e os vencedores desta edição serão removidos do mural.',
    );
    if (!confirmed) return;
    try {
      await _service.deleteEdition(item.id);
      await _load();
      _showMessage('Entrega excluída do mural.');
    } catch (_) {
      _showMessage('Não foi possível excluir a entrega.', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final branding = _branding;
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Premiações'),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded)),
        ],
      ),
      floatingActionButton: _canManage && !_loading
          ? FloatingActionButton.extended(
              onPressed: () => _openEditionForm(),
              icon: const Icon(Icons.add_a_photo_rounded),
              label: const Text('Nova entrega'),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 104),
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: branding.premiumCardColor.withValues(alpha: 0.94),
                borderRadius: BorderRadius.circular(branding.cardRadius + 4),
                border: Border.all(
                  color: branding.secondaryColor.withValues(alpha: 0.56),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      color: branding.secondaryColor.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: Icon(
                      Icons.emoji_events_rounded,
                      color: branding.secondaryColor,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Mural de premiações',
                          style: TextStyle(
                            color: branding.onPremiumCardColor,
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          'Conquistas e destaques da equipe',
                          style: TextStyle(
                            color: branding.onPremiumCardColor
                                .withValues(alpha: 0.72),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            _buildPeriodFilter(),
            if (_canManage) ...[
              const SizedBox(height: 14),
              _buildDefinitionsManager(),
            ],
            const SizedBox(height: 14),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(48),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              _EmptyPanel(
                icon: Icons.cloud_off_rounded,
                title: _error!,
                buttonLabel: 'Tentar novamente',
                onPressed: _load,
              )
            else if (_visiblePeriodEditions.isEmpty)
              _EmptyPanel(
                icon: Icons.emoji_events_outlined,
                title: _canManage
                    ? 'Nenhuma entrega publicada neste mês. Cadastre os vencedores e a foto para exibir aos atletas.'
                    : 'Nenhuma premiação publicada neste mês.',
                buttonLabel: _canManage ? 'Cadastrar entrega' : null,
                onPressed: _canManage ? () => _openEditionForm() : null,
              )
            else
              ..._visiblePeriodEditions.map(_buildEditionCard),
          ],
        ),
      ),
    );
  }

  Widget _buildPeriodFilter() {
    final months = DateFormat.MMMM('pt_BR').dateSymbols.MONTHS;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Expanded(
              flex: 2,
              child: DropdownButtonFormField<int>(
                initialValue: _selectedMonth,
                decoration: const InputDecoration(
                  labelText: 'Mês',
                  prefixIcon: Icon(Icons.calendar_month_rounded),
                ),
                items: List.generate(
                  12,
                  (index) => DropdownMenuItem(
                    value: index + 1,
                    child: Text(
                      '${months[index][0].toUpperCase()}${months[index].substring(1)}',
                    ),
                  ),
                ),
                onChanged: (value) =>
                    setState(() => _selectedMonth = value ?? _selectedMonth),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: DropdownButtonFormField<int>(
                initialValue: _selectedYear,
                decoration: const InputDecoration(labelText: 'Ano'),
                items: _availableYears
                    .map((year) => DropdownMenuItem(
                          value: year,
                          child: Text('$year'),
                        ))
                    .toList(),
                onChanged: (value) =>
                    setState(() => _selectedYear = value ?? _selectedYear),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDefinitionsManager() {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Tipos de premiação',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                  ),
                ),
                TextButton.icon(
                  onPressed: () => _openDefinitionForm(),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Criar'),
                ),
              ],
            ),
            if (_definitions.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 10),
                child: Text('Nenhum tipo criado.'),
              )
            else
              ..._definitions.map(
                (item) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    backgroundColor:
                        _branding.secondaryColor.withValues(alpha: 0.18),
                    child: Icon(
                      Icons.workspace_premium_rounded,
                      color: _branding.secondaryColor,
                    ),
                  ),
                  title: Text(
                    item.title,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  subtitle: Text(
                    '${awardSourceLabel(item.sourceType)} • ${item.winnerCount} vencedor(es)',
                  ),
                  trailing: PopupMenuButton<String>(
                    onSelected: (action) async {
                      if (action == 'edit') await _openDefinitionForm(item);
                      if (action == 'edition') {
                        await _openEditionForm(definition: item);
                      }
                      if (action == 'visibility') {
                        await _service.setDefinitionVisible(
                          item.id,
                          !item.isVisible,
                        );
                        await _load();
                      }
                      if (action == 'delete') await _deleteDefinition(item);
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(
                          value: 'edition', child: Text('Nova entrega')),
                      const PopupMenuItem(
                          value: 'edit', child: Text('Editar tipo')),
                      PopupMenuItem(
                        value: 'visibility',
                        child: Text(item.isVisible ? 'Ocultar' : 'Mostrar'),
                      ),
                      const PopupMenuItem(
                          value: 'delete', child: Text('Excluir')),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildEditionCard(AwardEdition item) {
    final branding = _branding;
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _openEditionDetails(item),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (item.deliveryPhotoUrl.isNotEmpty)
              GestureDetector(
                onTap: () => _viewPhoto(item.deliveryPhotoUrl),
                child: Container(
                  width: double.infinity,
                  constraints: const BoxConstraints(maxHeight: 440),
                  color: branding.primaryColor.withValues(alpha: 0.10),
                  child: CachedNetworkImage(
                    imageUrl: item.deliveryPhotoUrl,
                    fit: BoxFit.contain,
                    placeholder: (_, __) => const AspectRatio(
                      aspectRatio: 4 / 3,
                      child: Center(child: CircularProgressIndicator()),
                    ),
                    errorWidget: (_, __, ___) => const AspectRatio(
                      aspectRatio: 4 / 3,
                      child: Center(child: Icon(Icons.broken_image_rounded)),
                    ),
                  ),
                ),
              )
            else if (item.definition.coverImageUrl.isNotEmpty)
              Container(
                width: double.infinity,
                constraints: const BoxConstraints(maxHeight: 300),
                color: branding.primaryColor.withValues(alpha: 0.10),
                child: CachedNetworkImage(
                  imageUrl: item.definition.coverImageUrl,
                  fit: BoxFit.contain,
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.definition.title,
                              style: TextStyle(
                                color: branding.textColor,
                                fontSize: 19,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              awardSourceLabel(item.definition.sourceType),
                              style: TextStyle(
                                color: branding.primaryColor,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (_canManage)
                        PopupMenuButton<String>(
                          onSelected: (action) {
                            if (action == 'edit') {
                              _openEditionForm(edition: item);
                            } else if (action == 'delete') {
                              _deleteEdition(item);
                            }
                          },
                          itemBuilder: (_) => const [
                            PopupMenuItem(value: 'edit', child: Text('Editar')),
                            PopupMenuItem(
                                value: 'delete', child: Text('Excluir')),
                          ],
                        ),
                    ],
                  ),
                  if (_canManage) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 7,
                      runSpacing: 7,
                      children: [
                        _StatusChip(
                          icon: item.isPublished
                              ? Icons.public_rounded
                              : Icons.edit_note_rounded,
                          label: item.isPublished ? 'Publicado' : 'Rascunho',
                        ),
                        if (!item.isVisible)
                          const _StatusChip(
                            icon: Icons.visibility_off_rounded,
                            label: 'Oculto',
                          ),
                      ],
                    ),
                  ],
                  if (item.winners.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    ...item.winners.map(
                      (winner) => Padding(
                        padding: const EdgeInsets.only(bottom: 9),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 22,
                              backgroundColor: branding.secondaryColor
                                  .withValues(alpha: 0.16),
                              backgroundImage: winner.avatarUrl.isEmpty
                                  ? null
                                  : CachedNetworkImageProvider(
                                      winner.avatarUrl),
                              child: winner.avatarUrl.isEmpty
                                  ? Text(
                                      winner.name.isEmpty
                                          ? '?'
                                          : winner.name[0].toUpperCase(),
                                      style: TextStyle(
                                        color: branding.primaryColor,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    )
                                  : null,
                            ),
                            const SizedBox(width: 11),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    winner.name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  if (winner.resultLabel.isNotEmpty)
                                    Text(winner.resultLabel),
                                ],
                              ),
                            ),
                            Text(
                              '${winner.position}º',
                              style: TextStyle(
                                color: branding.secondaryColor,
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  if (item.caption.isNotEmpty) ...[
                    const SizedBox(height: 5),
                    Text(item.caption),
                  ],
                  if (item.deliveryDate != null) ...[
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Icon(
                          Icons.celebration_rounded,
                          size: 17,
                          color: branding.secondaryColor,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Entrega em ${_dateFormat.format(item.deliveryDate!)}',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openEditionDetails(AwardEdition item) {
    final branding = _branding;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.82,
        maxChildSize: 0.95,
        builder: (context, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 28),
          children: [
            Center(
              child: Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade400,
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              item.definition.title,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 4),
            Text(
              '${DateFormat.MMMM('pt_BR').format(item.period)} de ${item.year}',
              style: TextStyle(
                color: branding.primaryColor,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (item.deliveryPhotoUrl.isNotEmpty ||
                item.definition.coverImageUrl.isNotEmpty) ...[
              const SizedBox(height: 16),
              ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: CachedNetworkImage(
                  imageUrl: item.deliveryPhotoUrl.isNotEmpty
                      ? item.deliveryPhotoUrl
                      : item.definition.coverImageUrl,
                  fit: BoxFit.contain,
                  placeholder: (_, __) => const AspectRatio(
                    aspectRatio: 4 / 3,
                    child: Center(child: CircularProgressIndicator()),
                  ),
                  errorWidget: (_, __, ___) => const AspectRatio(
                    aspectRatio: 4 / 3,
                    child: Center(child: Icon(Icons.broken_image_rounded)),
                  ),
                ),
              ),
            ],
            if (item.definition.description.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(item.definition.description),
            ],
            if (item.caption.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(item.caption),
            ],
            if (item.winners.isNotEmpty) ...[
              const SizedBox(height: 20),
              const Text(
                'Vencedores',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 8),
              ...item.winners.map(
                (winner) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    backgroundImage: winner.avatarUrl.isEmpty
                        ? null
                        : CachedNetworkImageProvider(winner.avatarUrl),
                    child: winner.avatarUrl.isEmpty
                        ? Text(winner.name.isEmpty
                            ? '?'
                            : winner.name[0].toUpperCase())
                        : null,
                  ),
                  title: Text(
                    winner.name,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  subtitle: winner.resultLabel.isEmpty
                      ? null
                      : Text(winner.resultLabel),
                  trailing: Text(
                    '${winner.position}º',
                    style: TextStyle(
                      color: branding.secondaryColor,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
            ],
            if (item.deliveryDate != null) ...[
              const SizedBox(height: 12),
              Text(
                'Entrega em ${_dateFormat.format(item.deliveryDate!)}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _viewPhoto(String url) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
          ),
          body: Center(
            child: InteractiveViewer(
              child: CachedNetworkImage(imageUrl: url, fit: BoxFit.contain),
            ),
          ),
        ),
      ),
    );
  }
}

class AwardDefinitionFormPage extends StatefulWidget {
  const AwardDefinitionFormPage({
    super.key,
    required this.uploadImage,
    required this.initialYear,
    required this.initialMonth,
    this.loadProfiles,
    this.definition,
  });

  final AwardDefinition? definition;
  final int initialYear;
  final int initialMonth;
  final Future<String?> Function() uploadImage;
  final Future<List<Map<String, dynamic>>> Function()? loadProfiles;

  @override
  State<AwardDefinitionFormPage> createState() =>
      _AwardDefinitionFormPageState();
}

class _AwardDefinitionFormPageState extends State<AwardDefinitionFormPage> {
  final _formKey = GlobalKey<FormState>();
  final AwardsService _service = AwardsService();
  late final TextEditingController _title;
  late final TextEditingController _description;
  late String _sourceType;
  late int _winnerCount;
  late int _year;
  late int _month;
  late bool _visible;
  late String _coverUrl;
  bool _saving = false;
  bool _uploading = false;
  bool _loadingProfiles = true;
  List<Map<String, dynamic>> _profiles = const [];
  final List<Map<String, dynamic>> _selected = [];
  AwardDefinition? _persistedDefinition;

  @override
  void initState() {
    super.initState();
    final item = widget.definition;
    _title = TextEditingController(text: item?.title ?? '');
    _description = TextEditingController(text: item?.description ?? '');
    _sourceType = item?.sourceType ?? 'manual';
    _winnerCount = item?.winnerCount ?? 1;
    _year = widget.initialYear;
    _month = widget.initialMonth;
    _visible = item?.isVisible ?? true;
    _coverUrl = item?.coverImageUrl ?? '';
    if (item == null) {
      _loadProfiles();
    } else {
      _loadingProfiles = false;
    }
  }

  Future<void> _loadProfiles() async {
    try {
      final profiles = widget.loadProfiles == null
          ? await _service.loadEligibleProfiles()
          : await widget.loadProfiles!();
      if (mounted) setState(() => _profiles = profiles);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível carregar os atletas.')),
      );
    } finally {
      if (mounted) setState(() => _loadingProfiles = false);
    }
  }

  void _updateWinners(List<Map<String, dynamic>> winners) {
    setState(() {
      _selected
        ..clear()
        ..addAll(winners);
    });
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _upload() async {
    setState(() => _uploading = true);
    try {
      final url = await widget.uploadImage();
      if (url != null && mounted) setState(() => _coverUrl = url);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate() || _saving || _uploading) return;
    if (widget.definition == null && _selected.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Escolha o atleta vencedor.')),
      );
      return;
    }
    if (widget.definition == null && _coverUrl.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Adicione a foto da premiação.')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final saved = await _service.saveDefinition(
        id: widget.definition?.id ?? _persistedDefinition?.id,
        title: _title.text,
        description: _description.text,
        sourceType: _sourceType,
        winnerCount: _winnerCount,
        isVisible: _visible,
        coverImageUrl: _coverUrl,
      );
      _persistedDefinition = saved;
      if (widget.definition == null) {
        await _service.saveEdition(
          definition: saved,
          year: _year,
          month: _month,
          caption: _description.text,
          deliveryDate: null,
          deliveryPhotoUrl: _coverUrl,
          isPublished: true,
          isVisible: _visible,
          winners: _selected,
        );
      }
      if (mounted) {
        Navigator.pop(
          context,
          _AwardDefinitionFormResult(
            definition: saved,
            year: _year,
            month: _month,
          ),
        );
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível salvar: $error')),
      );
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final branding = OlympusBrandingController.instance.branding;
    final baseTheme = Theme.of(context);
    final months = DateFormat.MMMM('pt_BR').dateSymbols.MONTHS;
    final formTheme = baseTheme.copyWith(
      textTheme: baseTheme.textTheme.apply(
        bodyColor: branding.textColor,
        displayColor: branding.textColor,
      ),
      inputDecorationTheme: baseTheme.inputDecorationTheme.copyWith(
        fillColor: branding.surfaceColor,
        labelStyle: TextStyle(
          color: branding.textColor.withValues(alpha: 0.76),
        ),
        floatingLabelStyle: TextStyle(
          color: branding.primaryColor,
          fontWeight: FontWeight.w700,
        ),
        hintStyle: TextStyle(
          color: branding.textColor.withValues(alpha: 0.58),
        ),
      ),
    );
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.definition == null
            ? 'Novo tipo de premiação'
            : 'Editar premiação'),
      ),
      body: Theme(
        data: formTheme,
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (widget.definition == null) ...[
                Card(
                  margin: EdgeInsets.zero,
                  color: branding.surfaceColor,
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Mês da premiação',
                          style: TextStyle(
                            color: branding.textColor,
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'A premiação será exibida aos atletas neste período.',
                          style: TextStyle(
                            color: branding.textColor.withValues(alpha: 0.72),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              flex: 2,
                              child: DropdownButtonFormField<int>(
                                key: const Key('award-definition-month'),
                                initialValue: _month,
                                dropdownColor: branding.surfaceColor,
                                style: TextStyle(color: branding.textColor),
                                decoration:
                                    const InputDecoration(hintText: 'Mês'),
                                items: List.generate(
                                  12,
                                  (index) => DropdownMenuItem(
                                    value: index + 1,
                                    child: Text(
                                      '${months[index][0].toUpperCase()}${months[index].substring(1)}',
                                    ),
                                  ),
                                ),
                                onChanged: (value) =>
                                    setState(() => _month = value!),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: DropdownButtonFormField<int>(
                                key: const Key('award-definition-year'),
                                initialValue: _year,
                                dropdownColor: branding.surfaceColor,
                                style: TextStyle(color: branding.textColor),
                                decoration:
                                    const InputDecoration(hintText: 'Ano'),
                                items: List.generate(
                                  6,
                                  (index) {
                                    final year =
                                        DateTime.now().year - 2 + index;
                                    return DropdownMenuItem(
                                      value: year,
                                      child: Text('$year'),
                                    );
                                  },
                                ),
                                onChanged: (value) =>
                                    setState(() => _year = value!),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              _AwardFieldLabel(
                text: 'Nome da premiação',
                color: branding.textColor,
              ),
              const SizedBox(height: 6),
              TextFormField(
                key: const Key('award-title-field'),
                controller: _title,
                style: TextStyle(color: branding.textColor),
                decoration: const InputDecoration(
                  hintText: 'Ex.: Ranking do mês',
                ),
                validator: (value) => (value ?? '').trim().length < 2
                    ? 'Informe o nome da premiação.'
                    : null,
              ),
              const SizedBox(height: 12),
              _AwardFieldLabel(
                text: 'Descrição',
                color: branding.textColor,
              ),
              const SizedBox(height: 6),
              TextFormField(
                key: const Key('award-description-field'),
                controller: _description,
                style: TextStyle(color: branding.textColor),
                maxLines: 3,
                decoration: const InputDecoration(
                  hintText: 'Explique como essa premiação funciona.',
                ),
              ),
              const SizedBox(height: 12),
              _AwardFieldLabel(
                text: 'Tipo de resultado',
                color: branding.textColor,
              ),
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                key: const Key('award-source-field'),
                initialValue: _sourceType,
                dropdownColor: branding.surfaceColor,
                style: TextStyle(color: branding.textColor),
                decoration: const InputDecoration(),
                items: const [
                  'checkin_ranking',
                  'training_highlight',
                  'monthly_evaluation',
                  'manual',
                ]
                    .map((value) => DropdownMenuItem(
                          value: value,
                          child: Text(awardSourceLabel(value)),
                        ))
                    .toList(),
                onChanged: (value) => setState(() => _sourceType = value!),
              ),
              const SizedBox(height: 12),
              _WinnerCountSelector(
                value: _winnerCount,
                onChanged: (value) => setState(() {
                  _winnerCount = value;
                  if (_selected.length > value) {
                    _selected.removeRange(value, _selected.length);
                  }
                }),
              ),
              if (widget.definition == null) ...[
                const SizedBox(height: 14),
                _InlineWinnerPicker(
                  profiles: _profiles,
                  selected: _selected,
                  limit: _winnerCount,
                  loading: _loadingProfiles,
                  onChanged: _updateWinners,
                ),
              ],
              const SizedBox(height: 14),
              _ImageSelector(
                url: _coverUrl,
                title: widget.definition == null
                    ? 'Foto da premiação'
                    : 'Imagem da premiação (opcional)',
                subtitle: widget.definition == null
                    ? 'Esta foto será publicada no mural dos atletas.'
                    : 'Capa usada quando a entrega ainda não tem foto.',
                uploading: _uploading,
                onPick: _upload,
                onRemove: () => setState(() => _coverUrl = ''),
              ),
              const SizedBox(height: 12),
              Card(
                margin: EdgeInsets.zero,
                color: branding.surfaceColor,
                child: SwitchListTile(
                  value: _visible,
                  onChanged: (value) => setState(() => _visible = value),
                  title: Text(
                    'Mostrar este tipo',
                    style: TextStyle(
                      color: branding.textColor,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  subtitle: Text(
                    'Pode ser alterado depois sem excluir.',
                    style: TextStyle(
                      color: branding.textColor.withValues(alpha: 0.72),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_rounded),
                label: Text(widget.definition == null
                    ? 'Salvar e publicar premiação'
                    : 'Salvar alterações'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WinnerCountSelector extends StatelessWidget {
  const _WinnerCountSelector({
    required this.value,
    required this.onChanged,
  });

  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final branding = OlympusBrandingController.instance.branding;
    return Card(
      key: const Key('award-winner-count-selector'),
      margin: EdgeInsets.zero,
      color: branding.surfaceColor,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 10, 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Quantidade de vencedores',
                    style: TextStyle(
                      color: branding.textColor.withValues(alpha: 0.72),
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$value',
                    key: const Key('award-winner-count-value'),
                    style: TextStyle(
                      color: branding.textColor,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              key: const Key('award-winner-count-minus'),
              tooltip: 'Diminuir quantidade',
              onPressed: value > 1 ? () => onChanged(value - 1) : null,
              icon: const Icon(Icons.remove_circle_outline_rounded),
            ),
            IconButton.filled(
              key: const Key('award-winner-count-plus'),
              tooltip: 'Aumentar quantidade',
              onPressed: value < 20 ? () => onChanged(value + 1) : null,
              icon: const Icon(Icons.add_rounded),
            ),
          ],
        ),
      ),
    );
  }
}

class _InlineWinnerPicker extends StatelessWidget {
  const _InlineWinnerPicker({
    required this.profiles,
    required this.selected,
    required this.limit,
    required this.loading,
    required this.onChanged,
  });

  final List<Map<String, dynamic>> profiles;
  final List<Map<String, dynamic>> selected;
  final int limit;
  final bool loading;
  final ValueChanged<List<Map<String, dynamic>>> onChanged;

  bool _isSelected(Map<String, dynamic> profile) => selected.any(
        (item) => item['id'].toString() == profile['id'].toString(),
      );

  void _toggle(
    BuildContext context,
    Map<String, dynamic> profile,
    bool checked,
  ) {
    final updated =
        selected.map((item) => Map<String, dynamic>.from(item)).toList();
    final id = profile['id'].toString();
    if (!checked) {
      updated.removeWhere((item) => item['id'].toString() == id);
      onChanged(updated);
      return;
    }
    if (limit == 1) {
      onChanged([Map<String, dynamic>.from(profile)]);
      return;
    }
    if (updated.length >= limit) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Escolha no máximo $limit atletas.')),
      );
      return;
    }
    updated.add(Map<String, dynamic>.from(profile));
    onChanged(updated);
  }

  @override
  Widget build(BuildContext context) {
    final branding = OlympusBrandingController.instance.branding;
    final ordered = sortAwardProfilesAlphabetically(profiles);
    return Card(
      key: const Key('award-inline-winner-picker'),
      margin: EdgeInsets.zero,
      color: branding.surfaceColor,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                limit == 1
                    ? 'Escolha o atleta vencedor'
                    : 'Escolha até $limit atletas vencedores',
                style: TextStyle(
                  color: branding.textColor,
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const SizedBox(height: 4),
            if (loading)
              const Padding(
                padding: EdgeInsets.all(18),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (ordered.isEmpty)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Nenhum atleta ativo encontrado.',
                  style: TextStyle(color: branding.textColor),
                ),
              )
            else
              ...ordered.map(
                (profile) => CheckboxListTile(
                  key: Key('award-winner-${profile['id']}'),
                  value: _isSelected(profile),
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Text(
                    (profile['full_name'] ?? '').toString(),
                    style: TextStyle(
                      color: branding.textColor,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  onChanged: (value) =>
                      _toggle(context, profile, value == true),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _AwardFieldLabel extends StatelessWidget {
  const _AwardFieldLabel({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 13,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _AwardDefinitionFormResult {
  const _AwardDefinitionFormResult({
    required this.definition,
    required this.year,
    required this.month,
  });

  final AwardDefinition definition;
  final int year;
  final int month;
}

class AwardEditionFormPage extends StatefulWidget {
  const AwardEditionFormPage({
    super.key,
    required this.definitions,
    required this.initialYear,
    required this.initialMonth,
    required this.uploadImage,
    this.initialDefinition,
    this.edition,
  });

  final List<AwardDefinition> definitions;
  final AwardDefinition? initialDefinition;
  final AwardEdition? edition;
  final int initialYear;
  final int initialMonth;
  final Future<String?> Function() uploadImage;

  @override
  State<AwardEditionFormPage> createState() => _AwardEditionFormPageState();
}

class _AwardEditionFormPageState extends State<AwardEditionFormPage> {
  final _formKey = GlobalKey<FormState>();
  final AwardsService _service = AwardsService();
  late AwardDefinition _definition;
  late int _year;
  late int _month;
  late final TextEditingController _caption;
  late DateTime? _deliveryDate;
  late String _photoUrl;
  late bool _published;
  late bool _visible;
  bool _loadingProfiles = true;
  bool _saving = false;
  bool _uploading = false;
  List<Map<String, dynamic>> _profiles = const [];
  final List<Map<String, dynamic>> _selected = [];

  @override
  void initState() {
    super.initState();
    final edition = widget.edition;
    _definition = resolveAwardDefinitionById(
      definitions: widget.definitions,
      preferred: edition?.definition ?? widget.initialDefinition,
    );
    _year = edition?.year ?? widget.initialYear;
    _month = edition?.month ?? widget.initialMonth;
    _caption = TextEditingController(text: edition?.caption ?? '');
    _deliveryDate = edition?.deliveryDate;
    _photoUrl = edition?.deliveryPhotoUrl ?? '';
    _published = edition?.isPublished ?? true;
    _visible = edition?.isVisible ?? true;
    _loadProfiles();
  }

  Future<void> _loadProfiles() async {
    try {
      final profiles = await _service.loadEligibleProfiles();
      for (final winner in widget.edition?.winners ?? const <AwardWinner>[]) {
        final match =
            profiles.where((p) => p['id'].toString() == winner.profileId);
        _selected.add(match.isEmpty
            ? {
                'id': winner.profileId.isEmpty ? null : winner.profileId,
                'full_name': winner.name,
                'avatar_url': winner.avatarUrl,
                'result_label': winner.resultLabel,
              }
            : {...match.first, 'result_label': winner.resultLabel});
      }
      if (mounted) setState(() => _profiles = profiles);
    } finally {
      if (mounted) setState(() => _loadingProfiles = false);
    }
  }

  @override
  void dispose() {
    _caption.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _deliveryDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2200),
    );
    if (date != null) setState(() => _deliveryDate = date);
  }

  Future<void> _upload() async {
    setState(() => _uploading = true);
    try {
      final url = await widget.uploadImage();
      if (url != null && mounted) setState(() => _photoUrl = url);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  void _updateWinners(List<Map<String, dynamic>> winners) {
    setState(() {
      _selected
        ..clear()
        ..addAll(winners);
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate() || _saving || _uploading) return;
    if (_selected.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Escolha pelo menos um vencedor.')),
      );
      return;
    }
    if (_selected.length > _definition.winnerCount) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Este tipo permite ${_definition.winnerCount} vencedor(es).',
          ),
        ),
      );
      return;
    }
    if (_published && _photoUrl.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Adicione a foto da entrega antes de publicar.'),
        ),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await _service.saveEdition(
        id: widget.edition?.id,
        definition: _definition,
        year: _year,
        month: _month,
        caption: _caption.text,
        deliveryDate: _deliveryDate,
        deliveryPhotoUrl: _photoUrl,
        isPublished: _published,
        isVisible: _visible,
        winners: _selected,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      final duplicate = error.toString().contains('23505');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(duplicate
              ? 'Já existe uma edição desta premiação neste mês.'
              : 'Não foi possível salvar a entrega: $error'),
        ),
      );
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final months = DateFormat.MMMM('pt_BR').dateSymbols.MONTHS;
    final branding = OlympusBrandingController.instance.branding;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.edition == null ? 'Nova entrega' : 'Editar entrega'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _AwardFieldLabel(text: 'Premiação', color: branding.textColor),
            const SizedBox(height: 6),
            DropdownButtonFormField<AwardDefinition>(
              initialValue: _definition,
              dropdownColor: branding.surfaceColor,
              style: TextStyle(color: branding.textColor),
              decoration: const InputDecoration(),
              items: widget.definitions
                  .map((item) => DropdownMenuItem(
                        value: item,
                        child: Text(item.title),
                      ))
                  .toList(),
              onChanged: widget.edition != null
                  ? null
                  : (value) => setState(() {
                        _definition = value!;
                        if (_selected.length > value.winnerCount) {
                          _selected.removeRange(
                            value.winnerCount,
                            _selected.length,
                          );
                        }
                      }),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _AwardFieldLabel(text: 'Mês', color: branding.textColor),
                      const SizedBox(height: 6),
                      DropdownButtonFormField<int>(
                        initialValue: _month,
                        dropdownColor: branding.surfaceColor,
                        style: TextStyle(color: branding.textColor),
                        decoration: const InputDecoration(),
                        items: List.generate(
                          12,
                          (index) => DropdownMenuItem(
                            value: index + 1,
                            child: Text(months[index]),
                          ),
                        ),
                        onChanged: (value) => setState(() => _month = value!),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _AwardFieldLabel(text: 'Ano', color: branding.textColor),
                      const SizedBox(height: 6),
                      DropdownButtonFormField<int>(
                        initialValue: _year,
                        dropdownColor: branding.surfaceColor,
                        style: TextStyle(color: branding.textColor),
                        decoration: const InputDecoration(),
                        items: List.generate(
                          6,
                          (index) {
                            final year = DateTime.now().year - 2 + index;
                            return DropdownMenuItem(
                                value: year, child: Text('$year'));
                          },
                        ),
                        onChanged: (value) => setState(() => _year = value!),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _InlineWinnerPicker(
              profiles: _profiles,
              selected: _selected,
              limit: _definition.winnerCount,
              loading: _loadingProfiles,
              onChanged: _updateWinners,
            ),
            const SizedBox(height: 14),
            _ImageSelector(
              url: _photoUrl,
              title: 'Foto da entrega',
              subtitle: 'Esta é a foto publicada no mural.',
              uploading: _uploading,
              onPick: _upload,
              onRemove: () => setState(() => _photoUrl = ''),
            ),
            const SizedBox(height: 12),
            _AwardFieldLabel(text: 'Legenda', color: branding.textColor),
            const SizedBox(height: 6),
            TextFormField(
              controller: _caption,
              style: TextStyle(color: branding.textColor),
              maxLines: 3,
              decoration: const InputDecoration(
                hintText: 'Conte como foi a entrega da premiação.',
              ),
            ),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 12),
              tileColor: Theme.of(context).colorScheme.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15),
              ),
              leading: const Icon(Icons.event_rounded),
              title: Text(_deliveryDate == null
                  ? 'Data da entrega'
                  : DateFormat('dd/MM/yyyy').format(_deliveryDate!)),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: _pickDate,
            ),
            const SizedBox(height: 8),
            Card(
              margin: EdgeInsets.zero,
              color: branding.surfaceColor,
              child: SwitchListTile(
                value: _visible,
                onChanged: (value) => setState(() => _visible = value),
                title: Text(
                  'Mostrar esta entrega',
                  style: TextStyle(color: branding.textColor),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Card(
              margin: EdgeInsets.zero,
              color: branding.surfaceColor,
              child: SwitchListTile(
                value: _published,
                onChanged: (value) => setState(() => _published = value),
                title: Text(
                  'Publicar no mural',
                  style: TextStyle(color: branding.textColor),
                ),
                subtitle: Text(
                  'A publicação exige pelo menos um vencedor e a foto da entrega.',
                  style: TextStyle(
                    color: branding.textColor.withValues(alpha: 0.72),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_rounded),
              label: const Text('Salvar entrega'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ImageSelector extends StatelessWidget {
  const _ImageSelector({
    required this.url,
    required this.title,
    required this.subtitle,
    required this.uploading,
    required this.onPick,
    required this.onRemove,
  });

  final String url;
  final String title;
  final String subtitle;
  final bool uploading;
  final VoidCallback onPick;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (url.isNotEmpty)
            Container(
              width: double.infinity,
              constraints: const BoxConstraints(maxHeight: 320),
              color:
                  Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
              child: CachedNetworkImage(imageUrl: url, fit: BoxFit.contain),
            ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                const Icon(Icons.add_a_photo_rounded),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: const TextStyle(fontWeight: FontWeight.w900)),
                      Text(subtitle,
                          style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
                if (url.isNotEmpty)
                  IconButton(
                    tooltip: 'Remover foto',
                    onPressed: onRemove,
                    icon: const Icon(Icons.delete_outline_rounded),
                  ),
                TextButton(
                  onPressed: uploading ? null : onPick,
                  child: uploading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(url.isEmpty ? 'Adicionar' : 'Trocar'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15),
          const SizedBox(width: 5),
          Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _EmptyPanel extends StatelessWidget {
  const _EmptyPanel({
    required this.icon,
    required this.title,
    this.buttonLabel,
    this.onPressed,
  });

  final IconData icon;
  final String title;
  final String? buttonLabel;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 38),
        child: Column(
          children: [
            Icon(icon, size: 58, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 13),
            Text(title, textAlign: TextAlign.center),
            if (buttonLabel != null && onPressed != null) ...[
              const SizedBox(height: 15),
              FilledButton(onPressed: onPressed, child: Text(buttonLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}
