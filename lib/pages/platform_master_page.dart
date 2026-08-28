import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/platform_admin_service.dart';
import '../theme/olympus_theme.dart';
import 'platform_login_branding_page.dart';

class PlatformMasterPage extends StatefulWidget {
  const PlatformMasterPage({super.key});

  @override
  State<PlatformMasterPage> createState() => _PlatformMasterPageState();
}

class _PlatformMasterPageState extends State<PlatformMasterPage> {
  static const _olympusId = '00000000-0000-4000-8000-000000000001';
  final _service = PlatformAdminService.instance;
  final _searchController = TextEditingController();
  List<Map<String, dynamic>> _organizations = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (mounted)
      setState(() {
        _loading = true;
        _error = null;
      });
    try {
      if (!await _service.isPlatformAdmin(force: true)) {
        throw StateError('Este acesso e exclusivo do Administrador Master.');
      }
      final items = await _service.getOrganizations();
      if (mounted) setState(() => _organizations = items);
    } catch (error) {
      if (mounted) setState(() => _error = _friendlyError(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _friendlyError(Object error) {
    final value = error.toString().replaceFirst('Bad state: ', '');
    return value.contains('permission')
        ? 'Voce nao possui permissao para acessar este painel.'
        : value;
  }

  List<Map<String, dynamic>> get _filteredOrganizations {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) return _organizations;
    return _organizations.where((item) {
      return '${item['name']} ${item['slug']}'.toLowerCase().contains(query);
    }).toList();
  }

  Future<void> _createOrganization() async {
    final created = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => const _CreateOrganizationDialog(),
    );
    if (created == null || !mounted) return;
    await _load();
    if (!mounted) return;
    final email = '${created['admin_email'] ?? ''}';
    final password = '${created['temporary_password'] ?? ''}';
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Clube e administrador criados'),
        content: SelectableText(
          'E-mail: $email\nSenha temporaria: $password\n\n'
          'No primeiro acesso, o administrador sera obrigado a criar uma '
          'senha pessoal.',
        ),
        actions: [
          OutlinedButton.icon(
            onPressed: () async {
              await Clipboard.setData(
                ClipboardData(text: 'E-mail: $email\nSenha: $password'),
              );
              if (dialogContext.mounted) {
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  const SnackBar(content: Text('Acesso copiado.')),
                );
              }
            },
            icon: const Icon(Icons.copy_rounded),
            label: const Text('Copiar acesso'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Concluir'),
          ),
        ],
      ),
    );
  }

  Future<void> _openPublicLoginBranding() async {
    await PublicAppBrandingController.instance.initialize(force: true);
    if (!mounted) return;
    await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => const PlatformLoginBrandingPage(),
      ),
    );
  }

  Future<void> _openOrganization(Map<String, dynamic> organization) async {
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _OrganizationSettingsSheet(
        organization: organization,
        isOlympus: organization['id'] == _olympusId,
      ),
    );
    if (changed == true) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final branding = OlympusBrandingController.instance.branding;
    final active =
        _organizations.where((item) => item['is_active'] != false).length;
    final trial = _organizations.where((item) {
      final subscription = Map<String, dynamic>.from(
        item['subscription'] as Map? ?? const {},
      );
      return subscription['status'] == 'trial';
    }).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Master'),
        actions: [
          IconButton(
            tooltip: 'Atualizar',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _loading ? null : _createOrganization,
        icon: const Icon(Icons.add_business_rounded),
        label: const Text('Novo clube'),
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              branding.backgroundColor,
              Color.lerp(branding.backgroundColor, branding.primaryColor, .12)!,
            ],
          ),
        ),
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 104),
            children: [
              _MasterHeader(
                clubs: _organizations.length,
                active: active,
                trial: trial,
              ),
              const SizedBox(height: 14),
              Card(
                child: ListTile(
                  leading: const CircleAvatar(
                    child: Icon(Icons.phone_android_rounded),
                  ),
                  title: const Text(
                    'Tela inicial do aplicativo',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  subtitle: const Text(
                    'Nome, logotipo, cores e fundo exibidos antes do login.',
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: _openPublicLoginBranding,
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _searchController,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search_rounded),
                  labelText: 'Buscar clube',
                  hintText: 'Nome ou identificador',
                ),
              ),
              const SizedBox(height: 14),
              if (_loading && _organizations.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 64),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_error != null)
                _StatusCard(
                  icon: Icons.cloud_off_rounded,
                  title: 'Nao foi possivel abrir o painel',
                  message: _error!,
                  action: TextButton.icon(
                    onPressed: _load,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Tentar novamente'),
                  ),
                )
              else if (_filteredOrganizations.isEmpty)
                const _StatusCard(
                  icon: Icons.domain_disabled_rounded,
                  title: 'Nenhum clube encontrado',
                  message: 'Ajuste a busca ou cadastre um novo clube.',
                )
              else
                ..._filteredOrganizations.map(
                  (organization) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _OrganizationCard(
                      organization: organization,
                      isOlympus: organization['id'] == _olympusId,
                      onTap: () => _openOrganization(organization),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MasterHeader extends StatelessWidget {
  const _MasterHeader({
    required this.clubs,
    required this.active,
    required this.trial,
  });
  final int clubs;
  final int active;
  final int trial;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      color: colors.primary,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Central de clubes',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: colors.onPrimary,
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              'Cadastros, planos e funcionalidades em um unico lugar.',
              style: TextStyle(color: colors.onPrimary.withValues(alpha: .78)),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _Metric(value: '$clubs', label: 'Clubes'),
                ),
                Expanded(
                  child: _Metric(value: '$active', label: 'Ativos'),
                ),
                Expanded(
                  child: _Metric(value: '$trial', label: 'Testes'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.value, required this.label});
  final String value;
  final String label;
  @override
  Widget build(BuildContext context) => Column(
        children: [
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 22,
            ),
          ),
          Text(label,
              style: TextStyle(color: Colors.white.withValues(alpha: .76))),
        ],
      );
}

class _OrganizationCard extends StatelessWidget {
  const _OrganizationCard({
    required this.organization,
    required this.isOlympus,
    required this.onTap,
  });
  final Map<String, dynamic> organization;
  final bool isOlympus;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final subscription = Map<String, dynamic>.from(
      organization['subscription'] as Map? ?? const {},
    );
    final metrics = Map<String, dynamic>.from(
      organization['metrics'] as Map? ?? const {},
    );
    final invitation = Map<String, dynamic>.from(
      metrics['invitation'] as Map? ?? const {},
    );
    final userCount = (metrics['user_count'] as num?)?.toInt() ?? 0;
    final pendingInvitation = invitation['status'] == 'pending';
    final active = organization['is_active'] != false &&
        organization['status'] == 'active';
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              CircleAvatar(
                radius: 25,
                child: Icon(
                  isOlympus
                      ? Icons.shield_rounded
                      : Icons.sports_volleyball_rounded,
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${organization['name'] ?? 'Clube'}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                            ),
                          ),
                        ),
                        _Pill(
                          label: active ? 'Ativo' : 'Inativo',
                          color: active ? Colors.green : Colors.red,
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '${organization['slug'] ?? ''} • Plano ${subscription['plan_code'] ?? 'starter'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$userCount usuario${userCount == 1 ? '' : 's'} ativo${userCount == 1 ? '' : 's'} â€¢ Limite ${subscription['max_users'] ?? 100}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    if (pendingInvitation) ...[
                      const SizedBox(height: 7),
                      _Pill(
                        label: 'Administrador aguardando cadastro',
                        color: Colors.orange,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 6),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.color});
  final String label;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .12),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
              color: color, fontWeight: FontWeight.w700, fontSize: 11),
        ),
      );
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });
  final IconData icon;
  final String title;
  final String message;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Icon(icon, size: 42),
              const SizedBox(height: 10),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              Text(message, textAlign: TextAlign.center),
              if (action != null) ...[const SizedBox(height: 8), action!],
            ],
          ),
        ),
      );
}

class _CreateOrganizationDialog extends StatefulWidget {
  const _CreateOrganizationDialog();
  @override
  State<_CreateOrganizationDialog> createState() =>
      _CreateOrganizationDialogState();
}

class _CreateOrganizationDialogState extends State<_CreateOrganizationDialog> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _slug = TextEditingController();
  final _adminEmail = TextEditingController();
  final _adminPassword = TextEditingController();
  final _maxUsers = TextEditingController(text: '100');
  final _primaryColor = TextEditingController(text: '#1E3A5F');
  final _secondaryColor = TextEditingController(text: '#D4AF37');
  final _backgroundColor = TextEditingController(text: '#F4F7FB');
  final _surfaceColor = TextEditingController(text: '#FFFDF8');
  final _textColor = TextEditingController(text: '#172338');
  List<Map<String, dynamic>> _catalog = const [];
  Set<String> _enabledFeatures = <String>{};
  String _plan = 'starter';
  bool _saving = false;
  bool _loadingFeatures = true;
  bool _slugEdited = false;
  bool _showAdminPassword = false;
  String? _saveError;

  @override
  void initState() {
    super.initState();
    _loadFeatures();
  }

  Future<void> _loadFeatures() async {
    try {
      final catalog = await PlatformAdminService.instance.getFeatureCatalog();
      if (!mounted) return;
      setState(() {
        _catalog = catalog;
        _loadingFeatures = false;
        _applyPlanDefaults();
      });
    } catch (_) {
      if (mounted) setState(() => _loadingFeatures = false);
    }
  }

  void _applyPlanDefaults() {
    final all = _catalog.map((item) => '${item['key']}').toSet();
    const starter = <String>{
      'agenda',
      'checkin',
      'chat',
      'messages',
      'birthdays',
      'push_notifications',
    };
    const professionalExcluded = <String>{'exports'};
    _enabledFeatures = switch (_plan) {
      'starter' => all.intersection(starter),
      'professional' => all.difference(professionalExcluded),
      _ => all,
    };
  }

  String _slugFromName(String value) {
    const accents = 'aaaaaeeeeiiiiooooouuuuc';
    const originals = '\u00E1\u00E0\u00E3\u00E2\u00E4\u00E9\u00E8\u00EA\u00EB'
        '\u00ED\u00EC\u00EE\u00EF\u00F3\u00F2\u00F5\u00F4\u00F6'
        '\u00FA\u00F9\u00FB\u00FC\u00E7';
    var normalized = value.toLowerCase();
    for (var index = 0; index < originals.length; index++) {
      normalized = normalized.replaceAll(originals[index], accents[index]);
    }
    return normalized
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
  }

  @override
  void dispose() {
    _name.dispose();
    _slug.dispose();
    _adminEmail.dispose();
    _adminPassword.dispose();
    _maxUsers.dispose();
    _primaryColor.dispose();
    _secondaryColor.dispose();
    _backgroundColor.dispose();
    _surfaceColor.dispose();
    _textColor.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate() || _saving) return;
    setState(() {
      _saving = true;
      _saveError = null;
    });
    try {
      final result = await PlatformAdminService.instance.createOrganization(
        name: _name.text.trim(),
        slug: _slug.text.trim(),
        planCode: _plan,
        maxUsers: int.parse(_maxUsers.text),
        adminEmail: _adminEmail.text.trim().toLowerCase(),
        adminPassword: _adminPassword.text,
        enabledFeatures: _enabledFeatures.toList()..sort(),
        branding: {
          'primary_color': _primaryColor.text.trim(),
          'secondary_color': _secondaryColor.text.trim(),
          'background_color': _backgroundColor.text.trim(),
          'surface_color': _surfaceColor.text.trim(),
          'text_color': _textColor.text.trim(),
        },
      );
      if (mounted) Navigator.pop(context, result);
    } catch (error) {
      if (mounted) {
        final rawMessage = error.toString();
        final messageMatch = RegExp(r'message:\s*([^,}]+)')
            .firstMatch(rawMessage)
            ?.group(1)
            ?.trim();
        setState(() {
          _saveError = messageMatch?.isNotEmpty == true
              ? messageMatch
              : rawMessage
                  .replaceFirst('Exception: ', '')
                  .replaceFirst('Bad state: ', '');
        });
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.add_business_rounded),
            SizedBox(width: 10),
            Expanded(child: Text('Cadastrar novo clube')),
          ],
        ),
        content: SingleChildScrollView(
          child: SizedBox(
            width: 680,
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const _DialogSectionTitle(
                    icon: Icons.shield_rounded,
                    title: 'Clube e primeiro administrador',
                    subtitle:
                        'O e-mail informado recebera o perfil de Admin ao criar a conta.',
                  ),
                  TextFormField(
                    controller: _name,
                    decoration:
                        const InputDecoration(labelText: 'Nome do clube'),
                    textCapitalization: TextCapitalization.words,
                    onChanged: (value) {
                      if (!_slugEdited) _slug.text = _slugFromName(value);
                    },
                    validator: (v) => v == null || v.trim().length < 3
                        ? 'Informe o nome do clube.'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _slug,
                    decoration: const InputDecoration(
                      labelText: 'Identificador',
                      hintText: 'ex.: clube-exemplo',
                    ),
                    onChanged: (_) => _slugEdited = true,
                    validator: (v) => RegExp(r'^[a-z0-9][a-z0-9-]{2,}$')
                            .hasMatch(v?.trim() ?? '')
                        ? null
                        : 'Use letras minusculas, numeros e hifens.',
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _adminEmail,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    decoration: const InputDecoration(
                      labelText: 'E-mail do primeiro administrador',
                      prefixIcon: Icon(Icons.alternate_email_rounded),
                      helperText:
                          'Use um e-mail que ainda nao possui conta no app.',
                    ),
                    validator: (value) => RegExp(
                      r'^[^@\s]+@[^@\s]+\.[^@\s]+$',
                    ).hasMatch(value?.trim() ?? '')
                        ? null
                        : 'Informe um e-mail valido.',
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _adminPassword,
                    obscureText: !_showAdminPassword,
                    enableSuggestions: false,
                    autocorrect: false,
                    autofillHints: const [AutofillHints.newPassword],
                    decoration: InputDecoration(
                      labelText: 'Senha temporaria do administrador',
                      prefixIcon: const Icon(Icons.password_rounded),
                      helperText:
                          'A conta sera criada pronta para entrar no app.',
                      suffixIcon: IconButton(
                        tooltip: _showAdminPassword
                            ? 'Ocultar senha'
                            : 'Mostrar senha',
                        onPressed: () => setState(
                          () => _showAdminPassword = !_showAdminPassword,
                        ),
                        icon: Icon(
                          _showAdminPassword
                              ? Icons.visibility_off_rounded
                              : Icons.visibility_rounded,
                        ),
                      ),
                    ),
                    validator: (value) {
                      final password = value ?? '';
                      if (password.length < 8) {
                        return 'Use pelo menos 8 caracteres.';
                      }
                      if (!RegExp(r'[A-Za-z]').hasMatch(password) ||
                          !RegExp(r'[0-9]').hasMatch(password)) {
                        return 'Inclua pelo menos uma letra e um numero.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 22),
                  const _DialogSectionTitle(
                    icon: Icons.workspace_premium_rounded,
                    title: 'Plano e capacidade',
                    subtitle: 'Defina o pacote inicial e o limite de usuarios.',
                  ),
                  DropdownButtonFormField<String>(
                    initialValue: _plan,
                    decoration: const InputDecoration(labelText: 'Plano'),
                    items: const [
                      DropdownMenuItem(
                          value: 'starter', child: Text('Starter')),
                      DropdownMenuItem(
                        value: 'professional',
                        child: Text('Professional'),
                      ),
                      DropdownMenuItem(
                        value: 'enterprise',
                        child: Text('Enterprise'),
                      ),
                    ],
                    onChanged: (value) => setState(() {
                      _plan = value ?? _plan;
                      _applyPlanDefaults();
                    }),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _maxUsers,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Limite de usuarios',
                    ),
                    validator: (v) {
                      final n = int.tryParse(v ?? '');
                      return n == null || n < 1
                          ? 'Informe um limite valido.'
                          : null;
                    },
                  ),
                  const SizedBox(height: 22),
                  const _DialogSectionTitle(
                    icon: Icons.widgets_rounded,
                    title: 'Funcionalidades liberadas',
                    subtitle: 'Voce podera alterar estas permissoes depois.',
                  ),
                  if (_loadingFeatures)
                    const Center(child: CircularProgressIndicator())
                  else if (_catalog.isEmpty)
                    const Text('Catalogo de funcionalidades indisponivel.')
                  else
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: _catalog.map((feature) {
                        final key = '${feature['key']}';
                        final selected = _enabledFeatures.contains(key);
                        final colors = Theme.of(context).colorScheme;
                        final selectedForeground =
                            ThemeData.estimateBrightnessForColor(
                                        colors.primary) ==
                                    Brightness.dark
                                ? Colors.white
                                : Colors.black;
                        return FilterChip(
                          label: Text('${feature['name']}'),
                          selected: selected,
                          selectedColor: colors.primary,
                          checkmarkColor: selectedForeground,
                          labelStyle: TextStyle(
                            color: selected
                                ? selectedForeground
                                : colors.onSurface,
                            fontWeight: FontWeight.w700,
                          ),
                          onSelected: (selected) => setState(() {
                            if (selected) {
                              _enabledFeatures.add(key);
                            } else {
                              _enabledFeatures.remove(key);
                            }
                          }),
                        );
                      }).toList(),
                    ),
                  const SizedBox(height: 22),
                  const _DialogSectionTitle(
                    icon: Icons.palette_rounded,
                    title: 'Identidade visual inicial',
                    subtitle:
                        'Cores em hexadecimal. Podem ser refinadas depois.',
                  ),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final compact = constraints.maxWidth < 520;
                      final fields = <Widget>[
                        _ColorCodeField(
                          label: 'Principal',
                          controller: _primaryColor,
                        ),
                        _ColorCodeField(
                          label: 'Destaque',
                          controller: _secondaryColor,
                        ),
                        _ColorCodeField(
                          label: 'Fundo',
                          controller: _backgroundColor,
                        ),
                        _ColorCodeField(
                          label: 'Cartoes',
                          controller: _surfaceColor,
                        ),
                        _ColorCodeField(label: 'Texto', controller: _textColor),
                      ];
                      if (compact) {
                        return Column(
                          children: fields
                              .expand(
                                (field) => [field, const SizedBox(height: 10)],
                              )
                              .toList(),
                        );
                      }
                      return Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: fields
                            .map((field) => SizedBox(width: 205, child: field))
                            .toList(),
                      );
                    },
                  ),
                  if (_saveError != null) ...[
                    const SizedBox(height: 18),
                    Semantics(
                      liveRegion: true,
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.errorContainer,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.error_outline_rounded,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onErrorContainer,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Nao foi possivel criar o clube.\n$_saveError',
                                style: TextStyle(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onErrorContainer,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _saving ? null : () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check_rounded),
            label: const Text('Criar clube'),
          ),
        ],
      );
}

class _DialogSectionTitle extends StatelessWidget {
  const _DialogSectionTitle({
    required this.icon,
    required this.title,
    required this.subtitle,
  });
  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(radius: 20, child: Icon(icon, size: 20)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 2),
                  Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
          ],
        ),
      );
}

class _ColorCodeField extends StatelessWidget {
  const _ColorCodeField({required this.label, required this.controller});
  final String label;
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) => TextFormField(
        controller: controller,
        textCapitalization: TextCapitalization.characters,
        decoration: InputDecoration(labelText: label, prefixText: ''),
        validator: (value) =>
            RegExp(r'^#[0-9A-Fa-f]{6}$').hasMatch(value?.trim() ?? '')
                ? null
                : 'Use o formato #RRGGBB.',
      );
}

class _OrganizationSettingsSheet extends StatefulWidget {
  const _OrganizationSettingsSheet({
    required this.organization,
    required this.isOlympus,
  });
  final Map<String, dynamic> organization;
  final bool isOlympus;
  @override
  State<_OrganizationSettingsSheet> createState() =>
      _OrganizationSettingsSheetState();
}

class _OrganizationSettingsSheetState
    extends State<_OrganizationSettingsSheet> {
  final _service = PlatformAdminService.instance;
  List<Map<String, dynamic>> _catalog = const [];
  Map<String, Map<String, dynamic>> _features = const {};
  List<Map<String, dynamic>> _admins = const [];
  late String _organizationStatus;
  late String _subscriptionStatus;
  late String _plan;
  late TextEditingController _maxUsers;
  late Map<String, dynamic> _metrics;
  late Map<String, dynamic> _invitation;
  bool _loading = true;
  bool _saving = false;
  bool _invitationBusy = false;
  final Set<String> _resettingPasswords = {};
  final Set<String> _updatingFeatures = {};

  @override
  void initState() {
    super.initState();
    final subscription = Map<String, dynamic>.from(
      widget.organization['subscription'] as Map? ?? const {},
    );
    _organizationStatus = widget.organization['status']?.toString() ?? 'active';
    _subscriptionStatus = subscription['status']?.toString() ?? 'active';
    _plan = subscription['plan_code']?.toString() ?? 'starter';
    _maxUsers = TextEditingController(
      text: '${subscription['max_users'] ?? 100}',
    );
    _metrics = Map<String, dynamic>.from(
      widget.organization['metrics'] as Map? ?? const {},
    );
    _invitation = Map<String, dynamic>.from(
      _metrics['invitation'] as Map? ?? const {},
    );
    _load();
  }

  @override
  void dispose() {
    _maxUsers.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        _service.getFeatureCatalog(),
        _service.getOrganizationFeatures('${widget.organization['id']}'),
        _service.getOrganizationAdmins('${widget.organization['id']}'),
      ]);
      if (mounted)
        setState(() {
          _catalog = results[0] as List<Map<String, dynamic>>;
          _features = results[1] as Map<String, Map<String, dynamic>>;
          _admins = results[2] as List<Map<String, dynamic>>;
        });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool _featureEnabled(Map<String, dynamic> feature) {
    final key = '${feature['key']}';
    return _features[key]?['enabled'] as bool? ??
        feature['default_enabled'] != false;
  }

  Future<void> _toggleFeature(
    Map<String, dynamic> feature,
    bool enabled,
  ) async {
    final key = '${feature['key']}';
    if (_updatingFeatures.contains(key)) return;
    final previous = _features[key];
    setState(() {
      _updatingFeatures.add(key);
      _features = {
        ..._features,
        key: {...?previous, 'feature_key': key, 'enabled': enabled},
      };
    });
    try {
      await _service.setFeature(
        organizationId: '${widget.organization['id']}',
        featureKey: key,
        enabled: enabled,
      );
    } catch (error) {
      if (mounted) {
        setState(() {
          final copy = {..._features};
          if (previous == null) {
            copy.remove(key);
          } else {
            copy[key] = previous;
          }
          _features = copy;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Nao foi possivel alterar o modulo: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _updatingFeatures.remove(key));
    }
  }

  Future<void> _savePlan() async {
    if (_saving) return;
    final maxUsers = int.tryParse(_maxUsers.text);
    if (maxUsers == null || maxUsers < 1) return;
    setState(() => _saving = true);
    try {
      await _service.updateOrganization(
        organizationId: '${widget.organization['id']}',
        organizationStatus: widget.isOlympus ? 'active' : _organizationStatus,
        subscriptionStatus: _subscriptionStatus,
        planCode: _plan,
        maxUsers: maxUsers,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Nao foi possivel salvar: $error')),
        );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _dateLabel(Object? value) {
    final parsed = DateTime.tryParse('${value ?? ''}')?.toLocal();
    if (parsed == null) return 'sem data';
    final day = parsed.day.toString().padLeft(2, '0');
    final month = parsed.month.toString().padLeft(2, '0');
    return '$day/$month/${parsed.year}';
  }

  Future<void> _resetAdminPassword(Map<String, dynamic> admin) async {
    final userId = '${admin['user_id'] ?? ''}';
    if (userId.isEmpty || _resettingPasswords.contains(userId)) return;
    final name = '${admin['full_name'] ?? ''}'.trim();
    final email = '${admin['email'] ?? ''}'.trim();
    final label =
        name.isNotEmpty ? name : (email.isNotEmpty ? email : 'administrador');
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Redefinir senha?'),
        content: Text(
          'Uma nova senha temporaria sera gerada para $label. A senha atual '
          'deixara de funcionar e a troca sera obrigatoria no proximo login.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: const Icon(Icons.lock_reset_rounded),
            label: const Text('Gerar senha'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _resettingPasswords.add(userId));
    try {
      final password = await _service.resetUserPassword(userId);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Senha temporaria gerada'),
          content: SelectableText(
            '${email.isEmpty ? '' : 'E-mail: $email\n'}Senha: $password\n\n'
            'No proximo login, o usuario devera criar uma senha pessoal.',
          ),
          actions: [
            OutlinedButton.icon(
              onPressed: () async {
                await Clipboard.setData(
                  ClipboardData(
                    text:
                        '${email.isEmpty ? '' : 'E-mail: $email\n'}Senha temporaria: $password',
                  ),
                );
                if (dialogContext.mounted) {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    const SnackBar(content: Text('Acesso copiado.')),
                  );
                }
              },
              icon: const Icon(Icons.copy_rounded),
              label: const Text('Copiar acesso'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Concluir'),
            ),
          ],
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Nao foi possivel redefinir: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _resettingPasswords.remove(userId));
    }
  }

  Future<void> _createPendingAdminAccess() async {
    final email = '${_invitation['email'] ?? ''}'.trim();
    if (email.isEmpty || _invitationBusy) return;
    final password = await showDialog<String>(
      context: context,
      builder: (_) => _CreateAdminAccessDialog(email: email),
    );
    if (password == null || !mounted) return;
    setState(() => _invitationBusy = true);
    try {
      await _service.createInvitedAdminAccount(
        organizationId: '${widget.organization['id']}',
        email: email,
        password: password,
      );
      final admins = await _service.getOrganizationAdmins(
        '${widget.organization['id']}',
      );
      if (!mounted) return;
      final currentUsers = (_metrics['user_count'] as num?)?.toInt() ?? 0;
      setState(() {
        _admins = admins;
        _invitation = {..._invitation, 'status': 'accepted'};
        _metrics = {
          ..._metrics,
          'user_count': currentUsers < 1 ? 1 : currentUsers,
          'admin_count': admins.length,
        };
      });
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Acesso criado'),
          content: SelectableText(
            'E-mail: $email\nSenha temporaria: $password\n\n'
            'No primeiro login, o administrador devera criar uma senha pessoal.',
          ),
          actions: [
            OutlinedButton.icon(
              onPressed: () async {
                await Clipboard.setData(
                  ClipboardData(
                      text: 'E-mail: $email\nSenha temporaria: $password'),
                );
                if (dialogContext.mounted) {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    const SnackBar(content: Text('Acesso copiado.')),
                  );
                }
              },
              icon: const Icon(Icons.copy_rounded),
              label: const Text('Copiar acesso'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Concluir'),
            ),
          ],
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Nao foi possivel criar o acesso: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _invitationBusy = false);
    }
  }

  Future<void> _copyInvitationInstructions() async {
    final email = '${_invitation['email'] ?? ''}'.trim();
    if (email.isEmpty) return;
    final club = '${widget.organization['name']}';
    await Clipboard.setData(
      ClipboardData(
        text:
            'Voce foi convidado para administrar o clube $club no aplicativo. '
            'Crie sua conta usando exatamente o e-mail $email. Ao concluir o '
            'cadastro, o acesso de Administrador sera liberado automaticamente.',
      ),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Instrucoes do convite copiadas.')),
    );
  }

  Future<void> _renewInvitation() async {
    final id = '${_invitation['id'] ?? ''}';
    if (id.isEmpty || _invitationBusy) return;
    setState(() => _invitationBusy = true);
    try {
      final updated = await _service.renewAdminInvitation(id);
      if (mounted) {
        setState(() => _invitation = updated);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Convite renovado por mais 30 dias.')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Nao foi possivel renovar: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _invitationBusy = false);
    }
  }

  Future<void> _cancelInvitation() async {
    final id = '${_invitation['id'] ?? ''}';
    if (id.isEmpty || _invitationBusy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancelar convite?'),
        content: const Text(
          'O e-mail deixara de receber o perfil de Administrador neste clube.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Voltar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Cancelar convite'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _invitationBusy = true);
    try {
      await _service.cancelAdminInvitation(id);
      if (mounted) {
        setState(() => _invitation = {..._invitation, 'status': 'cancelled'});
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Nao foi possivel cancelar: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _invitationBusy = false);
    }
  }

  Future<void> _replaceInvitation() async {
    if (_invitationBusy) return;
    final controller = TextEditingController();
    final email = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Novo e-mail de administrador'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(
            labelText: 'E-mail',
            helperText: 'O e-mail nao pode possuir conta no aplicativo.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Criar convite'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (email == null || email.isEmpty || !mounted) return;
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Informe um e-mail valido.')),
      );
      return;
    }
    setState(() => _invitationBusy = true);
    try {
      final created = await _service.replaceAdminInvitation(
        organizationId: '${widget.organization['id']}',
        adminEmail: email,
      );
      if (mounted) setState(() => _invitation = created);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Nao foi possivel criar o convite: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _invitationBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final grouped = <String, List<Map<String, dynamic>>>{};
    final userCount = (_metrics['user_count'] as num?)?.toInt() ?? 0;
    final adminCount = (_metrics['admin_count'] as num?)?.toInt() ?? 0;
    final invitationStatus = '${_invitation['status'] ?? ''}';
    final invitationPending = invitationStatus == 'pending';
    final invitationAccepted = invitationStatus == 'accepted';
    for (final feature in _catalog) {
      grouped
          .putIfAbsent('${feature['category'] ?? 'Geral'}', () => [])
          .add(feature);
    }
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: .92,
      minChildSize: .58,
      maxChildSize: .97,
      builder: (context, controller) => Material(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
        child: ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 34),
          children: [
            Center(
              child: Container(
                width: 46,
                height: 5,
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: .4),
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                const CircleAvatar(child: Icon(Icons.apartment_rounded)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${widget.organization['name']}',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w900,
                            ),
                      ),
                      Text(
                        widget.isOlympus
                            ? 'Clube principal • protegido'
                            : '${widget.organization['slug']}',
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Card(
              color: Theme.of(context).colorScheme.primaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.groups_rounded),
                        const SizedBox(width: 9),
                        Expanded(
                          child: Text(
                            'Usuarios e administrador',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                        ),
                        _Pill(
                          label: '$userCount / ${_maxUsers.text}',
                          color:
                              userCount >= (int.tryParse(_maxUsers.text) ?? 100)
                                  ? Colors.red
                                  : Colors.green,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '$userCount usuario${userCount == 1 ? '' : 's'} ativo${userCount == 1 ? '' : 's'} â€¢ '
                      '$adminCount administrador${adminCount == 1 ? '' : 'es'}',
                    ),
                    if (_admins.isNotEmpty) ...[
                      const Divider(height: 24),
                      ..._admins.map((admin) {
                        final userId = '${admin['user_id'] ?? ''}';
                        final name = '${admin['full_name'] ?? ''}'.trim();
                        final email = '${admin['email'] ?? ''}'.trim();
                        final resetting = _resettingPasswords.contains(userId);
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const CircleAvatar(
                            child: Icon(Icons.admin_panel_settings_rounded),
                          ),
                          title: Text(
                            name.isEmpty ? 'Administrador' : name,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          subtitle: email.isEmpty ? null : Text(email),
                          trailing: OutlinedButton.icon(
                            onPressed: resetting
                                ? null
                                : () => _resetAdminPassword(admin),
                            icon: resetting
                                ? const SizedBox.square(
                                    dimension: 16,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
                                  )
                                : const Icon(Icons.lock_reset_rounded),
                            label: const Text('Resetar senha'),
                          ),
                        );
                      }),
                    ] else if (!_loading && adminCount > 0) ...[
                      const SizedBox(height: 10),
                      const Text(
                        'Nao foi possivel carregar os administradores deste clube.',
                      ),
                    ],
                    if (!widget.isOlympus) ...[
                      const Divider(height: 24),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            invitationAccepted
                                ? Icons.verified_user_rounded
                                : invitationPending
                                    ? Icons.mark_email_unread_rounded
                                    : Icons.person_add_alt_1_rounded,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  invitationAccepted
                                      ? 'Administrador vinculado'
                                      : invitationPending
                                          ? 'Convite aguardando cadastro'
                                          : 'Sem convite ativo',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                if ('${_invitation['email'] ?? ''}'.isNotEmpty)
                                  Text('${_invitation['email']}'),
                                if (invitationPending)
                                  Text(
                                    'Valido ate ${_dateLabel(_invitation['expires_at'])}',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodySmall,
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      if (_invitationBusy)
                        const LinearProgressIndicator()
                      else
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            if (invitationPending)
                              OutlinedButton.icon(
                                onPressed: _copyInvitationInstructions,
                                icon: const Icon(Icons.copy_rounded),
                                label: const Text('Copiar instrucoes'),
                              ),
                            if (invitationPending)
                              FilledButton.icon(
                                onPressed: _createPendingAdminAccess,
                                icon:
                                    const Icon(Icons.person_add_alt_1_rounded),
                                label: const Text('Criar acesso'),
                              ),
                            if (invitationPending ||
                                invitationStatus == 'expired' ||
                                invitationStatus == 'cancelled')
                              OutlinedButton.icon(
                                onPressed: _renewInvitation,
                                icon: const Icon(Icons.update_rounded),
                                label: const Text('Renovar 30 dias'),
                              ),
                            OutlinedButton.icon(
                              onPressed: _replaceInvitation,
                              icon: const Icon(Icons.alternate_email_rounded),
                              label: Text(
                                invitationPending
                                    ? 'Trocar e-mail'
                                    : 'Novo convite',
                              ),
                            ),
                            if (invitationPending)
                              TextButton.icon(
                                onPressed: _cancelInvitation,
                                icon: const Icon(Icons.cancel_outlined),
                                label: const Text('Cancelar convite'),
                              ),
                          ],
                        ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Plano e acesso',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _plan,
                    decoration: const InputDecoration(labelText: 'Plano'),
                    items: const [
                      DropdownMenuItem(
                        value: 'starter',
                        child: Text('Starter'),
                      ),
                      DropdownMenuItem(
                        value: 'professional',
                        child: Text('Professional'),
                      ),
                      DropdownMenuItem(
                        value: 'enterprise',
                        child: Text('Enterprise'),
                      ),
                    ],
                    onChanged: (v) => setState(() => _plan = v ?? _plan),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _maxUsers,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Usuarios'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _subscriptionStatus,
                    decoration: const InputDecoration(labelText: 'Assinatura'),
                    items: const [
                      DropdownMenuItem(value: 'trial', child: Text('Teste')),
                      DropdownMenuItem(value: 'active', child: Text('Ativa')),
                      DropdownMenuItem(
                        value: 'past_due',
                        child: Text('Pendente'),
                      ),
                      DropdownMenuItem(
                        value: 'suspended',
                        child: Text('Suspensa'),
                      ),
                      DropdownMenuItem(
                        value: 'cancelled',
                        child: Text('Cancelada'),
                      ),
                    ],
                    onChanged: (v) => setState(
                      () => _subscriptionStatus = v ?? _subscriptionStatus,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _organizationStatus,
                    decoration: const InputDecoration(labelText: 'Clube'),
                    items: const [
                      DropdownMenuItem(value: 'active', child: Text('Ativo')),
                      DropdownMenuItem(
                        value: 'suspended',
                        child: Text('Suspenso'),
                      ),
                      DropdownMenuItem(
                        value: 'archived',
                        child: Text('Arquivado'),
                      ),
                    ],
                    onChanged: widget.isOlympus
                        ? null
                        : (v) => setState(
                              () => _organizationStatus =
                                  v ?? _organizationStatus,
                            ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _saving ? null : _savePlan,
                icon: const Icon(Icons.save_rounded),
                label: Text(_saving ? 'Salvando...' : 'Salvar plano e acesso'),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Funcionalidades',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            const Text('Escolha exatamente o que este clube podera utilizar.'),
            const SizedBox(height: 10),
            if (_loading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(30),
                  child: CircularProgressIndicator(),
                ),
              )
            else
              ...grouped.entries.expand(
                (group) => [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 14, 4, 6),
                    child: Text(
                      _categoryLabel(group.key),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  Card(
                    child: Column(
                      children: group.value.map((feature) {
                        final key = '${feature['key']}';
                        return SwitchListTile.adaptive(
                          value: _featureEnabled(feature),
                          onChanged: _updatingFeatures.contains(key)
                              ? null
                              : (value) => _toggleFeature(feature, value),
                          title: Text(
                            '${feature['name']}',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          subtitle: Text('${feature['description'] ?? ''}'),
                          secondary: _updatingFeatures.contains(key)
                              ? const SizedBox.square(
                                  dimension: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : Icon(_featureIcon(key)),
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  String _categoryLabel(String category) =>
      const {
        'sports': 'Esporte',
        'communication': 'Comunicacao',
        'management': 'Gestao',
        'experience': 'Experiencia',
      }[category] ??
      category;
  IconData _featureIcon(String key) =>
      const {
        'agenda': Icons.calendar_month_rounded,
        'checkin': Icons.how_to_reg_rounded,
        'training_plans': Icons.menu_book_rounded,
        'competitions': Icons.emoji_events_rounded,
        'statistics': Icons.query_stats_rounded,
        'evaluations': Icons.rate_review_rounded,
        'chat': Icons.chat_rounded,
        'messages': Icons.mark_email_unread_rounded,
        'birthdays': Icons.cake_rounded,
        'financial': Icons.account_balance_wallet_rounded,
        'custom_branding': Icons.palette_rounded,
        'exports': Icons.download_rounded,
        'advanced_media': Icons.perm_media_rounded,
        'push_notifications': Icons.notifications_active_rounded,
      }[key] ??
      Icons.extension_rounded;
}

class _CreateAdminAccessDialog extends StatefulWidget {
  const _CreateAdminAccessDialog({required this.email});

  final String email;

  @override
  State<_CreateAdminAccessDialog> createState() =>
      _CreateAdminAccessDialogState();
}

class _CreateAdminAccessDialogState extends State<_CreateAdminAccessDialog> {
  final _formKey = GlobalKey<FormState>();
  final _password = TextEditingController();
  bool _showPassword = false;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Criar acesso do administrador'),
        content: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.email,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _password,
                obscureText: !_showPassword,
                enableSuggestions: false,
                autocorrect: false,
                decoration: InputDecoration(
                  labelText: 'Senha temporaria',
                  helperText: 'Minimo de 8 caracteres, com letra e numero.',
                  prefixIcon: const Icon(Icons.password_rounded),
                  suffixIcon: IconButton(
                    onPressed: () => setState(
                      () => _showPassword = !_showPassword,
                    ),
                    icon: Icon(
                      _showPassword
                          ? Icons.visibility_off_rounded
                          : Icons.visibility_rounded,
                    ),
                  ),
                ),
                validator: (value) {
                  final candidate = value ?? '';
                  if (candidate.length < 8) {
                    return 'Use pelo menos 8 caracteres.';
                  }
                  if (!RegExp(r'[A-Za-z]').hasMatch(candidate) ||
                      !RegExp(r'[0-9]').hasMatch(candidate)) {
                    return 'Inclua pelo menos uma letra e um numero.';
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton.icon(
            onPressed: () {
              if (_formKey.currentState!.validate()) {
                Navigator.pop(context, _password.text);
              }
            },
            icon: const Icon(Icons.person_add_alt_1_rounded),
            label: const Text('Criar acesso'),
          ),
        ],
      );
}
