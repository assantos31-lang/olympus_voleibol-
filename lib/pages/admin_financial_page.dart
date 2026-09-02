import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/financial_record_model.dart';
import '../services/financial_access_service.dart';
import '../services/olympus_memory_cache.dart';
import '../services/organization_context_service.dart';
import '../theme/olympus_theme.dart';

class AdminFinancialPage extends StatefulWidget {
  const AdminFinancialPage({super.key});

  @override
  State<AdminFinancialPage> createState() => _AdminFinancialPageState();
}

class _AdminFinancialPageState extends State<AdminFinancialPage> {
  OlympusBranding get _branding => OlympusBrandingController.instance.branding;
  final _supabase = Supabase.instance.client;
  final FinancialAccessService _financialAccessService =
      FinancialAccessService();
  List<FinancialRecord> _records = [];
  List<FinancialRecord> _dashboardRecords = [];
  Map<String, Map<String, dynamic>> _athleteData = {};
  List<Map<String, dynamic>> _athletes = [];
  final List<Map<String, String>> _pixKeyModels = [];
  RealtimeChannel? _financialRecordsChannel;
  final Set<String> _notifiedReceiptRecordIds = {};
  bool _isLoading = true;
  int _selectedMonth = DateTime.now().month;
  int _selectedYear = 2026;
  String _selectedStatus = 'all';
  String _selectedType = 'all';
  String _selectedAthleteId = 'all';
  bool _onlyWithReceipt = false;
  DateTime? _customStartDate;
  DateTime? _customEndDate;
  bool _showDashboardPage = true;
  bool _loadingRecords = false;
  bool _blockOverdueAthletes = false;
  bool _loadingAccessSetting = true;
  bool _savingAccessSetting = false;

  @override
  void initState() {
    super.initState();
    _initializePage();
    _listenForReceiptNotifications();
    _loadFinancialAccessSetting();
  }

  Future<void> _loadFinancialAccessSetting() async {
    try {
      final enabled = await _financialAccessService.getBlockOverdueAthletes();
      if (!mounted) return;
      setState(() {
        _blockOverdueAthletes = enabled;
        _loadingAccessSetting = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loadingAccessSetting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível carregar a regra: $error')),
      );
    }
  }

  Future<void> _setFinancialAccessSetting(bool enabled) async {
    if (_savingAccessSetting) return;
    setState(() => _savingAccessSetting = true);
    try {
      await _financialAccessService.setBlockOverdueAthletes(enabled);
      if (!mounted) return;
      setState(() => _blockOverdueAthletes = enabled);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            enabled
                ? 'Bloqueio por mensalidade atrasada ativado.'
                : 'Bloqueio por mensalidade atrasada desativado.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível alterar a regra: $error')),
      );
    } finally {
      if (mounted) setState(() => _savingAccessSetting = false);
    }
  }

  Widget _buildFinancialAccessControlCard() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF9E8),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2BB5B)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 2),
            child: Icon(
              Icons.sports_volleyball_rounded,
              color: Color(0xFF123463),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Controle de acesso por mensalidade',
                  style: TextStyle(
                    color: Color(0xFF123463),
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Ative a regra e escolha individualmente quais atletas inadimplentes serão bloqueados.',
                  style: TextStyle(
                    color: Color(0xFF52657C),
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: _showOverdueAthleteBlockPicker,
                  icon: const Icon(Icons.manage_accounts_rounded, size: 18),
                  label: const Text('Escolher atletas'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF123463),
                    side: const BorderSide(color: Color(0xFFE2BB5B)),
                    visualDensity: VisualDensity.compact,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (_loadingAccessSetting || _savingAccessSetting)
            const SizedBox(
              width: 28,
              height: 28,
              child: Padding(
                padding: EdgeInsets.all(5),
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            Switch.adaptive(
              value: _blockOverdueAthletes,
              onChanged: _setFinancialAccessSetting,
              activeThumbColor: const Color(0xFF0F9D58),
            ),
        ],
      ),
    );
  }

  Future<void> _showOverdueAthleteBlockPicker() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _OverdueAthleteBlockSheet(
        service: _financialAccessService,
        enforcementEnabled: _blockOverdueAthletes,
      ),
    );
  }

  Future<void> _initializePage() async {
    await _loadSavedFinancialFilters();
    _restoreFinancialCache();
    await _loadAthletes();
    await _loadPixKeyModels();
    await _loadDashboardRecords();
    await _loadRecords();
  }

  String get _financialCacheKey =>
      'admin_financial:${_supabase.auth.currentUser?.id ?? 'guest'}:'
      '$_selectedYear:$_selectedMonth:$_selectedStatus:$_selectedType:'
      '$_selectedAthleteId:$_onlyWithReceipt:'
      '${_customStartDate?.toIso8601String() ?? 'none'}:'
      '${_customEndDate?.toIso8601String() ?? 'none'}';

  void _restoreFinancialCache() {
    final cached = OlympusMemoryCache.read<Map<String, dynamic>>(
      _financialCacheKey,
    );
    if (cached == null) return;
    final records =
        (cached['records'] as List?)?.whereType<FinancialRecord>().toList() ??
            <FinancialRecord>[];
    if (records.isEmpty) return;
    setState(() {
      _records = records;
      _isLoading = false;
    });
  }

  void _saveFinancialCache() {
    OlympusMemoryCache.write<Map<String, dynamic>>(_financialCacheKey, {
      'records': List<FinancialRecord>.from(_records),
    });
  }

  Future<void> _loadSavedFinancialFilters() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;

      setState(() {
        _selectedMonth =
            prefs.getInt('admin_financial_selected_month') ?? _selectedMonth;
        _selectedYear =
            prefs.getInt('admin_financial_selected_year') ?? _selectedYear;
        _selectedType =
            prefs.getString('admin_financial_selected_type') ?? _selectedType;
        _selectedAthleteId =
            prefs.getString('admin_financial_selected_athlete_id') ??
                _selectedAthleteId;
        _onlyWithReceipt = prefs.getBool('admin_financial_only_with_receipt') ??
            _onlyWithReceipt;
        final savedStartDate = prefs.getString(
          'admin_financial_custom_start_date',
        );
        final savedEndDate = prefs.getString('admin_financial_custom_end_date');
        _customStartDate =
            savedStartDate == null ? null : DateTime.tryParse(savedStartDate);
        _customEndDate =
            savedEndDate == null ? null : DateTime.tryParse(savedEndDate);
      });
    } catch (e) {
      debugPrint('Erro ao carregar filtros financeiros: $e');
    }
  }

  Future<void> _saveFinancialFilters() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('admin_financial_selected_month', _selectedMonth);
      await prefs.setInt('admin_financial_selected_year', _selectedYear);
      await prefs.setString('admin_financial_selected_type', _selectedType);
      await prefs.setString(
        'admin_financial_selected_athlete_id',
        _selectedAthleteId,
      );
      await prefs.setBool(
        'admin_financial_only_with_receipt',
        _onlyWithReceipt,
      );
      if (_customStartDate == null) {
        await prefs.remove('admin_financial_custom_start_date');
      } else {
        await prefs.setString(
          'admin_financial_custom_start_date',
          _customStartDate!.toIso8601String(),
        );
      }
      if (_customEndDate == null) {
        await prefs.remove('admin_financial_custom_end_date');
      } else {
        await prefs.setString(
          'admin_financial_custom_end_date',
          _customEndDate!.toIso8601String(),
        );
      }
    } catch (e) {
      debugPrint('Erro ao salvar filtros financeiros: $e');
    }
  }

  bool get _hasCustomPeriodFilter =>
      _customStartDate != null && _customEndDate != null;

  Future<void> _applyFinancialFilterChanges() async {
    await _saveFinancialFilters();
    await _loadRecords();
  }

  DateTime _recordDueDate(FinancialRecord record) {
    return DateTime(record.year, record.month, record.day);
  }

  bool _recordMatchesCustomPeriod(FinancialRecord record) {
    if (!_hasCustomPeriodFilter) return true;
    final dueDate = _recordDueDate(record);
    final start = DateTime(
      _customStartDate!.year,
      _customStartDate!.month,
      _customStartDate!.day,
    );
    final end = DateTime(
      _customEndDate!.year,
      _customEndDate!.month,
      _customEndDate!.day,
      23,
      59,
      59,
    );
    return !dueDate.isBefore(start) && !dueDate.isAfter(end);
  }

  String _formatDateShort(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }

  String _getCustomPeriodLabel() {
    if (!_hasCustomPeriodFilter) return 'Periodo customizado';
    return '${_formatDateShort(_customStartDate!)} ate ${_formatDateShort(_customEndDate!)}';
  }

  Future<void> _selectCustomPeriod() async {
    final now = DateTime.now();
    final initialRange = _hasCustomPeriodFilter
        ? DateTimeRange(start: _customStartDate!, end: _customEndDate!)
        : DateTimeRange(
            start: DateTime(_selectedYear, _selectedMonth, 1),
            end: now,
          );

    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020, 1, 1),
      lastDate: DateTime(2035, 12, 31),
      initialDateRange: initialRange,
      helpText: 'Selecionar periodo',
      cancelText: 'Cancelar',
      confirmText: 'Aplicar',
      saveText: 'Aplicar',
    );

    if (range == null || !mounted) return;

    setState(() {
      _customStartDate = range.start;
      _customEndDate = range.end;
    });
    await _applyFinancialFilterChanges();
  }

  String _sanitizePhoneForWhatsApp(String? phone) {
    final digits = (phone ?? '').replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return '';
    if (digits.startsWith('55')) return digits;
    if (digits.length == 10 || digits.length == 11) return '55$digits';
    return digits;
  }

  String _getAthletePhone(String athleteId) {
    final athlete = _athleteData[athleteId];
    return athlete?['phone']?.toString() ?? '';
  }

  String _extractPixKeyFromDescription(String? description) {
    final text = description ?? '';
    final match = RegExp(r'Chave Pix \([^)]*\):\s*([^\n]+)').firstMatch(text);
    if (match != null) return match.group(1)?.trim() ?? '';
    return '';
  }

  String _buildChargeMessage(FinancialRecord record) {
    final athleteName = _getAthleteName(record.athleteId);
    final dueDate =
        '${record.day.toString().padLeft(2, '0')}/${record.month.toString().padLeft(2, '0')}/${record.year}';
    final pixKey = _extractPixKeyFromDescription(record.description);
    final pixLine = pixKey.isEmpty ? '' : '\nChave Pix: $pixKey\n';

    return '''Ola $athleteName,

Tudo bem?

Identificamos uma cobranca em aberto no ${OrganizationContextService.instance.currentName}:

Tipo: ${record.typeLabel}
Valor: R\$ ${record.value.toStringAsFixed(2).replaceAll('.', ',')}
Vencimento: $dueDate
$pixLine
Por favor, regularize quando puder. Se ja realizou o pagamento, envie o comprovante pelo aplicativo ou desconsidere esta mensagem.''';
  }

  Future<void> _sendRecordChargeWhatsApp(FinancialRecord record) async {
    final phone = _sanitizePhoneForWhatsApp(_getAthletePhone(record.athleteId));

    if (phone.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Telefone de ${_getAthleteName(record.athleteId)} nao encontrado.',
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final message = Uri.encodeComponent(_buildChargeMessage(record));
    final uri = Uri.parse('https://wa.me/$phone?text=$message');

    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Nao foi possivel abrir o WhatsApp.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _sendOverdueChargesWhatsApp() async {
    final overdueRecords = _getDashboardOverdueRecords();
    if (overdueRecords.isEmpty || !mounted) return;

    final grouped = <String, List<FinancialRecord>>{};
    for (final record in overdueRecords) {
      grouped.putIfAbsent(record.athleteId, () => []).add(record);
    }

    final entries = grouped.entries.toList()
      ..sort((a, b) {
        final valueA = a.value.fold<double>(
          0,
          (sum, record) => sum + record.value,
        );
        final valueB = b.value.fold<double>(
          0,
          (sum, record) => sum + record.value,
        );
        return valueB.compareTo(valueA);
      });

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return SafeArea(
          top: false,
          child: Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.82,
            ),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 42,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Color(0xFFE0E0E0),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(9),
                      decoration: BoxDecoration(
                        color: const Color(0xFF25D366).withOpacity(0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.chat_rounded,
                        color: Color(0xFF25D366),
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Cobrar atrasados no WhatsApp',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF2C3E5A),
                            ),
                          ),
                          Text(
                            'Escolha um atleta para abrir a mensagem pronta.',
                            style: TextStyle(
                              fontSize: 11,
                              color: Color(0xFF757575),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: entries.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final entry = entries[index];
                      final records = entry.value;
                      final total = records.fold<double>(
                        0,
                        (sum, record) => sum + record.value,
                      );
                      final oldest = records.reduce(
                        (a, b) => _recordDueDate(a).isBefore(_recordDueDate(b))
                            ? a
                            : b,
                      );
                      final hasPhone = _sanitizePhoneForWhatsApp(
                        _getAthletePhone(entry.key),
                      ).isNotEmpty;

                      return Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF6F8FB),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFFE1E6ED)),
                        ),
                        child: Row(
                          children: [
                            CircleAvatar(
                              backgroundColor: Colors.red.withOpacity(0.10),
                              child: const Icon(
                                Icons.person,
                                color: Colors.red,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _getAthleteName(entry.key),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      color: Color(0xFF2C3E5A),
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  Text(
                                    '${records.length} registro(s) | ${_formatCurrencyCompact(total)} | desde ${_formatDateShort(_recordDueDate(oldest))}',
                                    style: const TextStyle(
                                      fontSize: 10,
                                      color: Color(0xFF757575),
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            ElevatedButton.icon(
                              onPressed: hasPhone
                                  ? () {
                                      Navigator.pop(context);
                                      _sendRecordChargeWhatsApp(oldest);
                                    }
                                  : null,
                              icon: const Icon(Icons.chat_rounded, size: 15),
                              label: Text(hasPhone ? 'Cobrar' : 'Sem tel.'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF25D366),
                                foregroundColor: Colors.white,
                                disabledBackgroundColor: Colors.grey[300],
                                disabledForegroundColor: Colors.grey[600],
                                textStyle: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          ],
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
  }

  @override
  void dispose() {
    if (_financialRecordsChannel != null) {
      _supabase.removeChannel(_financialRecordsChannel!);
    }
    super.dispose();
  }

  void _listenForReceiptNotifications() {
    _financialRecordsChannel = _supabase
        .channel('admin_financial_receipts_channel')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'financial_records',
          callback: (payload) {
            final record = payload.newRecord;
            _handleReceiptAttachedNotification(record);
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'financial_records',
          callback: (payload) {
            final record = payload.newRecord;
            _handleReceiptAttachedNotification(record);
          },
        )
        .subscribe();
  }

  Future<void> _handleReceiptAttachedNotification(
    Map<String, dynamic> record,
  ) async {
    final recordId = record['id']?.toString();
    final receiptUrl = record['receipt_url']?.toString();

    if (!mounted ||
        recordId == null ||
        recordId.isEmpty ||
        receiptUrl == null ||
        receiptUrl.isEmpty ||
        _notifiedReceiptRecordIds.contains(recordId)) {
      return;
    }

    _notifiedReceiptRecordIds.add(recordId);

    final athleteId = record['athlete_id']?.toString();
    String athleteName =
        athleteId == null ? 'Atleta' : _getAthleteName(athleteId);

    if ((athleteName == 'Atleta não encontrado' || athleteName == 'Atleta') &&
        athleteId != null &&
        athleteId.isNotEmpty) {
      try {
        final athlete = await _supabase
            .from('profiles')
            .select('id, full_name, phone, gender')
            .eq('id', athleteId)
            .maybeSingle();

        if (athlete != null) {
          _athleteData[athleteId] = Map<String, dynamic>.from(athlete);
          athleteName = athlete['full_name']?.toString() ?? 'Atleta';
        }
      } catch (e) {
        debugPrint('Erro ao buscar atleta da notificação: $e');
      }
    }

    if (!mounted) return;

    await _loadRecords();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('📎 $athleteName anexou um comprovante.'),
        backgroundColor: Colors.blue,
        duration: const Duration(seconds: 6),
        action: SnackBarAction(
          label: 'VER',
          textColor: Colors.white,
          onPressed: () {
            final updatedRecords =
                _records.where((item) => item.id == recordId).toList();

            if (updatedRecords.isNotEmpty) {
              _showRecordDetails(updatedRecords.first);
            }
          },
        ),
      ),
    );

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Novo comprovante anexado'),
        content: Text(
          '$athleteName anexou um comprovante em um registro financeiro. '
          'Deseja visualizar agora?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Depois'),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(context);
              final updatedRecords =
                  _records.where((item) => item.id == recordId).toList();

              if (updatedRecords.isNotEmpty) {
                _showRecordDetails(updatedRecords.first);
              }
            },
            icon: const Icon(Icons.visibility),
            label: const Text('Visualizar'),
          ),
        ],
      ),
    );
  }

  Future<void> _savePixKeyModelsLocally() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final encodedModels = _pixKeyModels
          .map(
            (model) =>
                '${Uri.encodeComponent(model['name'] ?? '')}|${Uri.encodeComponent(model['type'] ?? '')}|${Uri.encodeComponent(model['key'] ?? '')}',
          )
          .toList();
      await prefs.setStringList(
        'admin_financial_pix_key_models',
        encodedModels,
      );
    } catch (e) {
      debugPrint('Erro ao salvar modelos Pix localmente: $e');
    }
  }

  Future<List<Map<String, String>>> _loadPixKeyModelsLocally() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final encodedModels =
          prefs.getStringList('admin_financial_pix_key_models') ?? [];

      return encodedModels.map((item) {
        final parts = item.split('|');
        if (parts.length != 3) return <String, String>{};
        return {
          'name': Uri.decodeComponent(parts[0]),
          'type': Uri.decodeComponent(parts[1]),
          'key': Uri.decodeComponent(parts[2]),
        };
      }).where((model) {
        return (model['name'] ?? '').isNotEmpty &&
            (model['type'] ?? '').isNotEmpty &&
            (model['key'] ?? '').isNotEmpty;
      }).toList();
    } catch (e) {
      debugPrint('Erro ao carregar modelos Pix locais: $e');
      return [];
    }
  }

  Future<void> _addOrUpdatePixKeyModel({
    required String name,
    required String type,
    required String key,
    bool persist = true,
  }) async {
    final cleanName = name.trim();
    final cleanKey = key.trim();
    if (cleanName.isEmpty || cleanKey.isEmpty) return;

    final existingIndex = _pixKeyModels.indexWhere((model) {
      final sameKey = model['key'] == cleanKey && model['type'] == type;
      final sameName =
          (model['name'] ?? '').toLowerCase() == cleanName.toLowerCase();
      return sameKey || sameName;
    });

    final model = {'name': cleanName, 'type': type, 'key': cleanKey};

    if (existingIndex >= 0) {
      _pixKeyModels[existingIndex] = model;
    } else {
      _pixKeyModels.add(model);
    }

    _pixKeyModels.sort(
      (a, b) => (a['name'] ?? '').toLowerCase().compareTo(
            (b['name'] ?? '').toLowerCase(),
          ),
    );

    if (persist) {
      await _savePixKeyModelsLocally();
    }
  }

  Future<void> _loadPixKeyModels() async {
    try {
      final loadedModels = <Map<String, String>>[];
      final usedKeys = <String>{};

      void addModel(Map<String, String> model) {
        final pixKey = model['key']?.trim() ?? '';
        final pixKeyType = model['type']?.trim().isNotEmpty == true
            ? model['type']!.trim()
            : 'cpf';
        final modelName = model['name']?.trim().isNotEmpty == true
            ? model['name']!.trim()
            : 'Chave Pix cadastrada';
        if (pixKey.isEmpty) return;

        final uniqueKey = '$pixKeyType|$pixKey';
        if (usedKeys.contains(uniqueKey)) return;
        usedKeys.add(uniqueKey);

        loadedModels.add({
          'name': modelName,
          'type': pixKeyType,
          'key': pixKey,
        });
      }

      final localModels = await _loadPixKeyModelsLocally();
      for (final model in localModels) {
        addModel(model);
      }

      final response = await _supabase
          .from('financial_records')
          .select('pix_key, pix_key_type, description, type')
          .not('pix_key', 'is', null)
          .order('created_at', ascending: false);

      for (final item in response as List) {
        final pixKey = item['pix_key']?.toString().trim() ?? '';
        if (pixKey.isEmpty) continue;

        final pixKeyType =
            item['pix_key_type']?.toString().trim().isNotEmpty == true
                ? item['pix_key_type'].toString().trim()
                : 'cpf';
        final recordType = item['type']?.toString() ?? '';
        final typeLabel = _getTypeLabel(recordType);

        addModel({
          'name':
              typeLabel == 'Todos' ? 'Chave Pix cadastrada' : 'Pix $typeLabel',
          'type': pixKeyType,
          'key': pixKey,
        });
      }

      if (mounted) {
        setState(() {
          _pixKeyModels
            ..clear()
            ..addAll(loadedModels);
        });
      }
    } catch (e) {
      debugPrint('Erro modelos Pix: $e');
    }
  }

  Future<void> _loadAthletes() async {
    try {
      final athleteIds = <String>{};

      try {
        final rolesResponse = await _supabase
            .from('user_roles')
            .select('user_id')
            .eq('role', 'athlete')
            .eq('is_active', true);

        for (final row in rolesResponse as List) {
          final userId = (row['user_id'] ?? '').toString();
          if (userId.isNotEmpty) athleteIds.add(userId);
        }
      } catch (e) {
        debugPrint('Papéis de atleta indisponíveis no financeiro: $e');
      }

      final profileAthletes = await _supabase
          .from('profiles')
          .select('id')
          .eq('user_type', 'athlete')
          .eq('is_active', true);

      for (final row in profileAthletes as List) {
        final userId = (row['id'] ?? '').toString();
        if (userId.isNotEmpty) athleteIds.add(userId);
      }

      dynamic response;
      if (athleteIds.isEmpty) {
        response = const [];
      } else {
        response = await _supabase
            .from('profiles')
            .select('id, full_name, phone, gender')
            .eq('is_active', true)
            .inFilter('id', athleteIds.toList())
            .order('full_name');
      }

      if (mounted) {
        setState(() {
          _athletes = List<Map<String, dynamic>>.from(response)
            ..sort(
              (a, b) => (a['full_name'] ?? '')
                  .toString()
                  .toLowerCase()
                  .compareTo((b['full_name'] ?? '').toString().toLowerCase()),
            );
        });
      }
    } catch (e) {
      debugPrint('Erro atletas: $e');
    }
  }

  bool get _isViewingOverdueRecords => _selectedStatus == 'overdue';

  Future<void> _loadRecords() async {
    if (!mounted || _loadingRecords) return;
    _loadingRecords = true;
    setState(() => _isLoading = _records.isEmpty);

    try {
      debugPrint(
        '🔍 BUSCANDO: mês=$_selectedMonth, ano=$_selectedYear, tipo=$_selectedType',
      );

      var query = _supabase
          .from('financial_records')
          .select()
          .eq('year', _selectedYear);

      // Ao visualizar atrasados, buscamos o ano inteiro.
      // Assim débitos vencidos em meses anteriores continuam aparecendo,
      // mesmo que o filtro de mês esteja no mês atual.
      if (!_isViewingOverdueRecords && !_hasCustomPeriodFilter) {
        query = query.eq('month', _selectedMonth);
      }

      if (_isViewingOverdueRecords) {
        query = query.eq('status', 'pending');
      }

      if (_onlyWithReceipt) {
        query = query.not('receipt_url', 'is', null);
      }

      if (_selectedType != 'all') {
        query = query.eq('type', _selectedType);
      }

      if (_selectedAthleteId != 'all') {
        query = query.eq('athlete_id', _selectedAthleteId);
      }

      debugPrint('📊 Executando query...');
      final response = await query.order('created_at', ascending: false);
      final responseRows = response as List;
      debugPrint('✅ RETORNO DO BANCO: ${responseRows.length} registros');

      final records =
          responseRows.map((r) => FinancialRecord.fromMap(r)).toList();
      debugPrint('📋 Após mapeamento: ${records.length} registros');

      final athleteIds = records.map((r) => r.athleteId).toSet().toList();
      if (athleteIds.isNotEmpty) {
        final athletesResponse = await _supabase
            .from('profiles')
            .select('id, full_name, phone, gender')
            .filter('id', 'in', "(${athleteIds.join(',')})");

        _athleteData = {
          for (var athlete in athletesResponse as List) athlete['id']: athlete,
        };
      }

      if (mounted) {
        setState(() {
          _records = records;
          _isLoading = false;
        });
        _saveFinancialCache();
        debugPrint('🎯 FINAL: ${_records.length} registros na tela');
        await _loadDashboardRecords();
      }
    } catch (e) {
      debugPrint('❌ ERRO: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        if (_records.isNotEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Não foi possível atualizar. Dados anteriores mantidos.',
              ),
            ),
          );
        }
      }
    } finally {
      _loadingRecords = false;
    }
  }

  Future<void> _loadDashboardRecords() async {
    try {
      var query = _supabase
          .from('financial_records')
          .select()
          .eq('year', _selectedYear);

      if (_selectedType != 'all') {
        query = query.eq('type', _selectedType);
      }

      if (_selectedAthleteId != 'all') {
        query = query.eq('athlete_id', _selectedAthleteId);
      }

      final response = await query.order('month', ascending: true);

      final records =
          (response as List).map((r) => FinancialRecord.fromMap(r)).toList();

      final athleteIds = records.map((r) => r.athleteId).toSet().toList();
      if (athleteIds.isNotEmpty) {
        final athletesResponse = await _supabase
            .from('profiles')
            .select('id, full_name, phone, gender')
            .filter('id', 'in', "(${athleteIds.join(',')})");

        for (final athlete in athletesResponse as List) {
          _athleteData[athlete['id']] = Map<String, dynamic>.from(athlete);
        }
      }

      if (mounted) {
        setState(() {
          _dashboardRecords = records;
        });
      }
    } catch (e) {
      debugPrint('Erro dashboard financeiro: $e');
    }
  }

  Future<void> _deleteRecord(String recordId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar Exclusão'),
        content: const Text('Tem certeza que deseja excluir este registro?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      try {
        await _supabase.from('financial_records').delete().eq('id', recordId);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ Registro excluído!'),
              backgroundColor: Colors.green,
            ),
          );
          await _loadRecords();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Erro ao excluir: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  void _editRecord(FinancialRecord record) {
    final valueController = TextEditingController(
      text: 'R\$ ${record.value.toStringAsFixed(2).replaceAll('.', ',')}',
    );
    final descriptionController = TextEditingController(
      text: record.description ?? '',
    );
    int selectedDay = record.day;
    int selectedMonth = record.month;
    int selectedYear = record.year;
    String selectedType = record.type;
    final formKey = GlobalKey<FormState>();

    InputDecoration editDecoration({
      required String label,
      required IconData icon,
      String? hintText,
      String? prefixText,
    }) {
      return InputDecoration(
        labelText: label,
        hintText: hintText,
        prefixText: prefixText,
        labelStyle: TextStyle(
          fontSize: 11,
          color: olympusBlue,
          fontWeight: FontWeight.w700,
        ),
        prefixIcon: Icon(icon, size: 18, color: olympusBlue),
        filled: true,
        fillColor: const Color(0xFFF6F8FB),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 12,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFE1E6ED)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFF2C3E5A), width: 1.4),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Colors.red),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Colors.red, width: 1.4),
        ),
      );
    }

    double? parseCurrencyValue(String value) {
      final cleaned = value
          .replaceAll('R\$', '')
          .replaceAll(RegExp(r'\s'), '')
          .replaceAll('.', '')
          .replaceAll(',', '.');
      return double.tryParse(cleaned);
    }

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => Dialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 18,
            vertical: 24,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 520),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Colors.white, Color(0xFFF8F9FA)],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.12),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
              child: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF2C3E5A), Color(0xFF4A6FA5)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(
                            Icons.edit_note_rounded,
                            color: Colors.white,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Editar registro',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF2C3E5A),
                                ),
                              ),
                              SizedBox(height: 2),
                              Text(
                                'Atualize o débito financeiro do atleta',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Color(0xFF757575),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close_rounded),
                          color: const Color(0xFF757575),
                          tooltip: 'Fechar',
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: const Color(0xFFE3E8EF)),
                      ),
                      child: Column(
                        children: [
                          DropdownButtonFormField<String>(
                            value: selectedType,
                            decoration: editDecoration(
                              label: 'Tipo *',
                              icon: _getTypeIcon(selectedType),
                            ),
                            isExpanded: true,
                            borderRadius: BorderRadius.circular(14),
                            items: const [
                              DropdownMenuItem(
                                value: 'monthly',
                                child: Text('Mensalidade'),
                              ),
                              DropdownMenuItem(
                                value: 'games',
                                child: Text('Jogos'),
                              ),
                              DropdownMenuItem(
                                value: 'maintenance',
                                child: Text('Manutenção'),
                              ),
                              DropdownMenuItem(
                                value: 'other',
                                child: Text('Outros'),
                              ),
                            ],
                            onChanged: (value) {
                              setDialogState(() {
                                selectedType = value!;
                              });
                            },
                          ),
                          const SizedBox(height: 10),
                          TextFormField(
                            controller: valueController,
                            decoration: editDecoration(
                              label: 'Valor (R\$) *',
                              icon: Icons.attach_money_rounded,
                              hintText: 'R\$ 0,00',
                            ),
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                              CurrencyInputFormatter(),
                            ],
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return 'Campo obrigatório';
                              }
                              if (parseCurrencyValue(value) == null) {
                                return 'Valor inválido';
                              }
                              return null;
                            },
                          ),
                          if (selectedType == 'other') ...[
                            const SizedBox(height: 10),
                            TextFormField(
                              controller: descriptionController,
                              decoration: editDecoration(
                                label: 'Descrição *',
                                icon: Icons.description_rounded,
                                hintText: 'Informe do que se trata',
                              ),
                              maxLines: 2,
                              validator: (value) {
                                if (selectedType == 'other' &&
                                    (value == null || value.trim().isEmpty)) {
                                  return 'Campo obrigatório para "Outros"';
                                }
                                return null;
                              },
                            ),
                          ],
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: DropdownButtonFormField<int>(
                                  value: selectedDay,
                                  decoration: editDecoration(
                                    label: 'Dia *',
                                    icon: Icons.today_rounded,
                                  ),
                                  isExpanded: true,
                                  borderRadius: BorderRadius.circular(14),
                                  items: List.generate(31, (i) => i + 1)
                                      .map(
                                        (d) => DropdownMenuItem(
                                          value: d,
                                          child: Text(d.toString()),
                                        ),
                                      )
                                      .toList(),
                                  onChanged: (value) {
                                    setDialogState(() {
                                      selectedDay = value!;
                                    });
                                  },
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: DropdownButtonFormField<int>(
                                  value: selectedMonth,
                                  decoration: editDecoration(
                                    label: 'Mês *',
                                    icon: Icons.calendar_month_rounded,
                                  ),
                                  isExpanded: true,
                                  borderRadius: BorderRadius.circular(14),
                                  items: List.generate(12, (i) => i + 1)
                                      .map(
                                        (m) => DropdownMenuItem(
                                          value: m,
                                          child: Text(
                                            DateFormat.MMM('pt_BR')
                                                .format(DateTime(2024, m))
                                                .replaceAll('.', ''),
                                          ),
                                        ),
                                      )
                                      .toList(),
                                  onChanged: (value) {
                                    setDialogState(() {
                                      selectedMonth = value!;
                                    });
                                  },
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: DropdownButtonFormField<int>(
                                  value: selectedYear,
                                  decoration: editDecoration(
                                    label: 'Ano *',
                                    icon: Icons.event_rounded,
                                  ),
                                  isExpanded: true,
                                  borderRadius: BorderRadius.circular(14),
                                  items: [2026, 2027, 2028, 2029, 2030]
                                      .map(
                                        (y) => DropdownMenuItem(
                                          value: y,
                                          child: Text(y.toString()),
                                        ),
                                      )
                                      .toList(),
                                  onChanged: (value) {
                                    setDialogState(() {
                                      selectedYear = value!;
                                    });
                                  },
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(Icons.close_rounded, size: 18),
                            label: const Text('Cancelar'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: olympusBlue,
                              side: BorderSide(color: olympusBlue),
                              padding: const EdgeInsets.symmetric(vertical: 13),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () async {
                              if (formKey.currentState!.validate()) {
                                try {
                                  final parsedValue = parseCurrencyValue(
                                    valueController.text,
                                  )!;

                                  await _supabase
                                      .from('financial_records')
                                      .update({
                                    'type': selectedType,
                                    'value': parsedValue,
                                    'description': selectedType == 'other'
                                        ? descriptionController.text.trim()
                                        : null,
                                    'day': selectedDay,
                                    'month': selectedMonth,
                                    'year': selectedYear,
                                  }).eq('id', record.id);

                                  if (mounted) {
                                    Navigator.pop(context);
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('✅ Registro atualizado!'),
                                        backgroundColor: Colors.green,
                                      ),
                                    );
                                    await _loadRecords();
                                  }
                                } catch (e) {
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text('Erro ao atualizar: $e'),
                                        backgroundColor: Colors.red,
                                      ),
                                    );
                                  }
                                }
                              }
                            },
                            icon: const Icon(Icons.save_rounded, size: 18),
                            label: const Text('Salvar'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: olympusBlue,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 13),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  IconData _getTypeIcon(String type) {
    switch (type) {
      case 'monthly':
        return Icons.account_balance_wallet;
      case 'games':
        return Icons.sports_soccer;
      case 'maintenance':
        return Icons.build;
      case 'other':
        return Icons.receipt_long;
      default:
        return Icons.receipt_long;
    }
  }

  Color _getTypeColor(String type) {
    switch (type) {
      case 'monthly':
        return const Color(0xFF667eea);
      case 'games':
        return const Color(0xFFf093fb);
      case 'maintenance':
        return const Color(0xFF4facfe);
      case 'other':
        return const Color(0xFFfa709a);
      default:
        return olympusBlue;
    }
  }

  String _getTypeLabel(String type) {
    switch (type) {
      case 'monthly':
        return 'Mensalidade';
      case 'games':
        return 'Jogos';
      case 'maintenance':
        return 'Manutenção';
      case 'other':
        return 'Outros';
      default:
        return 'Todos';
    }
  }

  String _getPixTypeLabel(String type) {
    switch (type) {
      case 'phone':
        return 'Telefone';
      case 'cpf':
        return 'CPF';
      case 'cnpj':
        return 'CNPJ';
      default:
        return 'CPF';
    }
  }

  String _getPixHintText(String type) {
    switch (type) {
      case 'phone':
        return 'Informe o telefone da chave Pix';
      case 'cpf':
        return 'Informe o CPF da chave Pix';
      case 'cnpj':
        return 'Informe o CNPJ da chave Pix';
      default:
        return 'Informe a chave Pix';
    }
  }

  String _getGenderLabel(String? gender) {
    switch (gender) {
      case 'Masculino':
        return 'Masculino';
      case 'Feminino':
        return 'Feminino';
      default:
        return 'Não informado';
    }
  }

  String _getSelectedAthleteFilterLabel() {
    if (_selectedAthleteId == 'all') return 'Todos os atletas';

    final athlete = _athletes.firstWhere(
      (item) => item['id']?.toString() == _selectedAthleteId,
      orElse: () => {},
    );

    if (athlete.isNotEmpty) {
      return athlete['full_name']?.toString() ?? 'Atleta selecionado';
    }

    return _getAthleteName(_selectedAthleteId);
  }

  Future<void> _showAthleteFilterPicker() async {
    final searchController = TextEditingController();
    String searchText = '';

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) {
          final filteredAthletes = _athletes.where((athlete) {
            final name = athlete['full_name']?.toString().toLowerCase() ?? '';
            return name.contains(searchText.toLowerCase().trim());
          }).toList();

          return SafeArea(
            top: false,
            child: Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.82,
              ),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 12,
                bottom: MediaQuery.of(context).viewInsets.bottom + 16,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 42,
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE0E0E0),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      const Icon(
                        Icons.person_search_rounded,
                        color: Color(0xFF2C3E5A),
                      ),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Buscar atleta',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF2C3E5A),
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: searchController,
                    autofocus: true,
                    decoration: InputDecoration(
                      hintText: 'Digite o nome do atleta...',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: searchText.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                searchController.clear();
                                setSheetState(() => searchText = '');
                              },
                            ),
                      filled: true,
                      fillColor: const Color(0xFFF6F8FB),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: Color(0xFFE1E6ED)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: Color(0xFFE1E6ED)),
                      ),
                    ),
                    onChanged: (value) {
                      setSheetState(() => searchText = value);
                    },
                  ),
                  const SizedBox(height: 10),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      backgroundColor: olympusBlue.withOpacity(0.1),
                      child: Icon(
                        Icons.groups_rounded,
                        color: olympusBlue,
                      ),
                    ),
                    title: const Text(
                      'Todos os atletas',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    trailing: _selectedAthleteId == 'all'
                        ? const Icon(Icons.check_circle, color: Colors.green)
                        : null,
                    onTap: () {
                      setState(() {
                        _selectedAthleteId = 'all';
                      });
                      _saveFinancialFilters();
                      Navigator.pop(context);
                      _loadRecords();
                    },
                  ),
                  const Divider(height: 1),
                  Flexible(
                    child: filteredAthletes.isEmpty
                        ? const Padding(
                            padding: EdgeInsets.symmetric(vertical: 28),
                            child: Text(
                              'Nenhum atleta encontrado',
                              style: TextStyle(color: Color(0xFF757575)),
                            ),
                          )
                        : ListView.separated(
                            shrinkWrap: true,
                            itemCount: filteredAthletes.length,
                            separatorBuilder: (_, __) =>
                                const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final athlete = filteredAthletes[index];
                              final athleteId = athlete['id']?.toString() ?? '';
                              final isSelected =
                                  athleteId == _selectedAthleteId;

                              return ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: CircleAvatar(
                                  backgroundColor: const Color(
                                    0xFF4A6FA5,
                                  ).withOpacity(0.12),
                                  child: const Icon(
                                    Icons.person,
                                    color: Color(0xFF4A6FA5),
                                  ),
                                ),
                                title: Text(
                                  athlete['full_name']?.toString() ??
                                      'Sem nome',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF2C3E5A),
                                  ),
                                ),
                                subtitle: Text(
                                  _getGenderLabel(
                                    athlete['gender']?.toString(),
                                  ),
                                ),
                                trailing: isSelected
                                    ? const Icon(
                                        Icons.check_circle,
                                        color: Colors.green,
                                      )
                                    : null,
                                onTap: athleteId.isEmpty
                                    ? null
                                    : () {
                                        setState(() {
                                          _selectedAthleteId = athleteId;
                                        });
                                        _saveFinancialFilters();
                                        Navigator.pop(context);
                                        _loadRecords();
                                      },
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  List<TextInputFormatter> _getPixInputFormatters(String type) {
    switch (type) {
      case 'phone':
        return [FilteringTextInputFormatter.allow(RegExp(r'[0-9()\-\s+]'))];
      case 'cpf':
      case 'cnpj':
        return [FilteringTextInputFormatter.allow(RegExp(r'[0-9./\-]'))];
      default:
        return [];
    }
  }

  String? _validatePixKey(String? value, String type) {
    if (value == null || value.trim().isEmpty) {
      return 'Campo obrigatório';
    }

    final digits = value.replaceAll(RegExp(r'\D'), '');

    switch (type) {
      case 'phone':
        if (digits.length < 10 || digits.length > 11) {
          return 'Telefone Pix inválido';
        }
        break;
      case 'cpf':
        if (digits.length != 11) {
          return 'CPF Pix inválido';
        }
        break;
      case 'cnpj':
        if (digits.length != 14) {
          return 'CNPJ Pix inválido';
        }
        break;
    }

    return null;
  }

  void _showCreateRecordDialog() {
    String? selectedAthleteId = 'all';
    final Set<String> selectedAthleteIds = {};
    bool selectMultipleUsers = false;
    String selectedGenderFilter = 'all';
    String selectedType = 'monthly';
    final valueController = TextEditingController();
    final descriptionController = TextEditingController();
    final pixKeyController = TextEditingController();
    String? selectedPixKeyModel;
    String selectedPixKeyType = 'cpf';

    Future<void> showAddPixKeyModelDialog(StateSetter setDialogState) async {
      final modelNameController = TextEditingController();
      final modelPixKeyController = TextEditingController();
      String modelPixKeyType = selectedPixKeyType;
      final modelFormKey = GlobalKey<FormState>();

      await showDialog(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setModelDialogState) => AlertDialog(
            title: const Text('Cadastrar modelo de chave Pix'),
            content: Form(
              key: modelFormKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: modelNameController,
                    decoration: const InputDecoration(
                      labelText: 'Nome do modelo *',
                      border: OutlineInputBorder(),
                      hintText: 'Ex: Pix mensalidade',
                    ),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? 'Campo obrigatório'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: modelPixKeyType,
                    decoration: const InputDecoration(
                      labelText: 'Tipo da chave Pix *',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'phone', child: Text('Telefone')),
                      DropdownMenuItem(value: 'cpf', child: Text('CPF')),
                      DropdownMenuItem(value: 'cnpj', child: Text('CNPJ')),
                    ],
                    onChanged: (value) {
                      setModelDialogState(() {
                        modelPixKeyType = value!;
                        modelPixKeyController.clear();
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: modelPixKeyController,
                    decoration: InputDecoration(
                      labelText: 'Chave Pix *',
                      border: const OutlineInputBorder(),
                      hintText: _getPixHintText(modelPixKeyType),
                    ),
                    keyboardType: modelPixKeyType == 'phone'
                        ? TextInputType.phone
                        : TextInputType.number,
                    inputFormatters: _getPixInputFormatters(modelPixKeyType),
                    validator: (value) =>
                        _validatePixKey(value, modelPixKeyType),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                onPressed: () async {
                  if (modelFormKey.currentState!.validate()) {
                    final newModelName = modelNameController.text.trim();
                    final newModelKey = modelPixKeyController.text.trim();

                    await _addOrUpdatePixKeyModel(
                      name: newModelName,
                      type: modelPixKeyType,
                      key: newModelKey,
                    );
                    if (!mounted) return;
                    setState(() {});
                    setDialogState(() {
                      selectedPixKeyModel = newModelName;
                      selectedPixKeyType = modelPixKeyType;
                      pixKeyController.text = newModelKey;
                    });
                    Navigator.pop(context);
                  }
                },
                child: const Text('Salvar'),
              ),
            ],
          ),
        ),
      );
    }

    int selectedMonth = _selectedMonth;
    int selectedYear = _selectedYear;
    int selectedDay = DateTime.now().day;
    bool showOtherDescription = false;
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
          titlePadding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
          contentPadding: const EdgeInsets.fromLTRB(18, 8, 18, 10),
          actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          title: const Row(
            children: [
              Icon(Icons.add_card_rounded, color: Color(0xFF2C3E5A), size: 20),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Cadastrar Registro Financeiro',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFE3F2FD), Color(0xFFBBDEFB)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFF90CAF9)),
                    ),
                    child: DropdownButtonFormField<String>(
                      value: selectedAthleteId,
                      decoration: const InputDecoration(
                        labelText: 'Atleta *',
                        labelStyle: TextStyle(
                          fontSize: 11,
                          color: Color(0xFF1565C0),
                        ),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 8,
                        ),
                      ),
                      hint: const Text(
                        'Selecione um atleta',
                        style: TextStyle(fontSize: 12),
                      ),
                      isExpanded: true,
                      icon: const Icon(
                        Icons.keyboard_arrow_down,
                        color: Color(0xFF1976D2),
                        size: 18,
                      ),
                      style: const TextStyle(fontSize: 12),
                      items: [
                        const DropdownMenuItem<String>(
                          value: 'all',
                          child: Text(
                            'Todos',
                            style: TextStyle(
                              fontSize: 12,
                              color: Color(0xFF424242),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        ..._athletes.map((athlete) {
                          return DropdownMenuItem<String>(
                            value: athlete['id'] as String,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  athlete['full_name'] ?? 'Sem nome',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF424242),
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                Text(
                                  _getGenderLabel(
                                    athlete['gender']?.toString(),
                                  ),
                                  style: const TextStyle(
                                    fontSize: 9,
                                    color: Color(0xFF757575),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                      ],
                      onChanged: (value) {
                        setDialogState(() {
                          selectedAthleteId = value;
                          if (value != 'all') {
                            selectMultipleUsers = false;
                            selectedAthleteIds.clear();
                            selectedGenderFilter = 'all';
                          }
                        });
                      },
                      validator: (value) {
                        if (value == null) return 'Campo obrigatório';
                        if (selectedAthleteId == 'all' &&
                            selectMultipleUsers &&
                            selectedAthleteIds.isEmpty) {
                          return 'Selecione ao menos um usuário';
                        }
                        return null;
                      },
                    ),
                  ),
                  if (selectedAthleteId == 'all') ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFFFFF8E1), Color(0xFFFFECB3)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFFFD54F)),
                      ),
                      child: CheckboxListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        value: selectMultipleUsers,
                        controlAffinity: ListTileControlAffinity.leading,
                        title: const Text(
                          'Selecionar mais de um usuário',
                          style: TextStyle(
                            fontSize: 12,
                            color: Color(0xFF424242),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        onChanged: (checked) {
                          setDialogState(() {
                            selectMultipleUsers = checked ?? false;
                            if (!selectMultipleUsers) {
                              selectedAthleteIds.clear();
                              selectedGenderFilter = 'all';
                            }
                          });
                        },
                      ),
                    ),
                  ],
                  if (selectedAthleteId == 'all' && selectMultipleUsers) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFFE0F7FA), Color(0xFFB2EBF2)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFF80DEEA)),
                      ),
                      child: DropdownButtonFormField<String>(
                        value: selectedGenderFilter,
                        decoration: const InputDecoration(
                          labelText: 'Filtrar por gênero',
                          labelStyle: TextStyle(
                            fontSize: 11,
                            color: Color(0xFF00838F),
                          ),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 8,
                          ),
                        ),
                        isExpanded: true,
                        icon: const Icon(
                          Icons.keyboard_arrow_down,
                          color: Color(0xFF0097A7),
                          size: 18,
                        ),
                        style: const TextStyle(fontSize: 12),
                        items: const [
                          DropdownMenuItem(
                            value: 'all',
                            child: Text('Todos os gêneros'),
                          ),
                          DropdownMenuItem(
                            value: 'Masculino',
                            child: Text('Masculino'),
                          ),
                          DropdownMenuItem(
                            value: 'Feminino',
                            child: Text('Feminino'),
                          ),
                          DropdownMenuItem(
                            value: 'not_informed',
                            child: Text('Não informado'),
                          ),
                        ],
                        onChanged: (value) {
                          setDialogState(() {
                            selectedGenderFilter = value!;
                            selectedAthleteIds.removeWhere((id) {
                              final athlete = _athletes.firstWhere(
                                (item) => item['id'] == id,
                                orElse: () => {},
                              );
                              final gender = athlete['gender']?.toString();
                              if (selectedGenderFilter == 'all') return false;
                              if (selectedGenderFilter == 'not_informed') {
                                return gender != null && gender.isNotEmpty;
                              }
                              return gender != selectedGenderFilter;
                            });
                          });
                        },
                      ),
                    ),
                    const SizedBox(height: 8),
                    Builder(
                      builder: (context) {
                        final filteredAthletes = _athletes.where((athlete) {
                          final gender = athlete['gender']?.toString();
                          if (selectedGenderFilter == 'all') return true;
                          if (selectedGenderFilter == 'not_informed') {
                            return gender == null || gender.isEmpty;
                          }
                          return gender == selectedGenderFilter;
                        }).toList();
                        final filteredAthleteIds = filteredAthletes
                            .map((athlete) => athlete['id'] as String)
                            .toList();
                        final allFilteredSelected =
                            filteredAthleteIds.isNotEmpty &&
                                filteredAthleteIds.every(
                                  selectedAthleteIds.contains,
                                );

                        return Column(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                              ),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [
                                    Color(0xFFE8F5E9),
                                    Color(0xFFC8E6C9),
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: const Color(0xFFA5D6A7),
                                ),
                              ),
                              child: CheckboxListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                value: allFilteredSelected,
                                controlAffinity:
                                    ListTileControlAffinity.leading,
                                title: const Text(
                                  'Selecionar todos os usuários',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF424242),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                subtitle: Text(
                                  '${filteredAthletes.length} usuário(s) no filtro atual',
                                  style: const TextStyle(fontSize: 10),
                                ),
                                onChanged: (checked) {
                                  setDialogState(() {
                                    if (checked == true) {
                                      selectedAthleteIds.addAll(
                                        filteredAthleteIds,
                                      );
                                    } else {
                                      selectedAthleteIds.removeAll(
                                        filteredAthleteIds,
                                      );
                                    }
                                  });
                                },
                              ),
                            ),
                            const SizedBox(height: 8),
                            Container(
                              constraints: const BoxConstraints(maxHeight: 180),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                              ),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [
                                    Color(0xFFF1F8E9),
                                    Color(0xFFDCEDC8),
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: const Color(0xFFC5E1A5),
                                ),
                              ),
                              child: SingleChildScrollView(
                                child: Column(
                                  children: filteredAthletes.map((athlete) {
                                    final athleteId = athlete['id'] as String;
                                    return CheckboxListTile(
                                      dense: true,
                                      contentPadding: EdgeInsets.zero,
                                      value: selectedAthleteIds.contains(
                                        athleteId,
                                      ),
                                      title: Text(
                                        athlete['full_name'] ?? 'Sem nome',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: Color(0xFF424242),
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      subtitle: Text(
                                        _getGenderLabel(
                                          athlete['gender']?.toString(),
                                        ),
                                        style: const TextStyle(fontSize: 10),
                                      ),
                                      controlAffinity:
                                          ListTileControlAffinity.leading,
                                      onChanged: (checked) {
                                        setDialogState(() {
                                          if (checked == true) {
                                            selectedAthleteIds.add(athleteId);
                                          } else {
                                            selectedAthleteIds.remove(
                                              athleteId,
                                            );
                                          }
                                        });
                                      },
                                    );
                                  }).toList(),
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ],
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFF3E5F5), Color(0xFFE1BEE7)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFCE93D8)),
                    ),
                    child: DropdownButtonFormField<String>(
                      value: selectedType,
                      decoration: const InputDecoration(
                        labelText: 'Tipo *',
                        labelStyle: TextStyle(
                          fontSize: 11,
                          color: Color(0xFF7B1FA2),
                        ),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 8,
                        ),
                      ),
                      isExpanded: true,
                      icon: const Icon(
                        Icons.keyboard_arrow_down,
                        color: Color(0xFF8E24AA),
                        size: 18,
                      ),
                      style: const TextStyle(fontSize: 12),
                      items: const [
                        DropdownMenuItem(
                          value: 'monthly',
                          child: Text(
                            'Mensalidade',
                            style: TextStyle(
                              fontSize: 12,
                              color: Color(0xFF424242),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        DropdownMenuItem(
                          value: 'games',
                          child: Text(
                            'Jogos',
                            style: TextStyle(
                              fontSize: 12,
                              color: Color(0xFF424242),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        DropdownMenuItem(
                          value: 'maintenance',
                          child: Text(
                            'Manutenção',
                            style: TextStyle(
                              fontSize: 12,
                              color: Color(0xFF424242),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        DropdownMenuItem(
                          value: 'other',
                          child: Text(
                            'Outros',
                            style: TextStyle(
                              fontSize: 12,
                              color: Color(0xFF424242),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                      onChanged: (value) {
                        setDialogState(() {
                          selectedType = value!;
                          showOtherDescription = value == 'other';
                        });
                      },
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFE8F5E9), Color(0xFFC8E6C9)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFA5D6A7)),
                    ),
                    child: TextFormField(
                      controller: valueController,
                      decoration: const InputDecoration(
                        labelText: 'Valor (R\$) *',
                        labelStyle: TextStyle(
                          fontSize: 11,
                          color: Color(0xFF388E3C),
                        ),
                        border: InputBorder.none,
                        prefixText: 'R\$ ',
                        hintText: '0,00',
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 8,
                        ),
                      ),
                      style: const TextStyle(fontSize: 12),
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        CurrencyInputFormatter(),
                      ],
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Campo obrigatório';
                        }
                        final numericValue = value
                            .replaceAll(RegExp(r'[^\d,]'), '')
                            .replaceAll(',', '.');
                        if (double.tryParse(numericValue) == null) {
                          return 'Valor inválido';
                        }
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFFFFDE7), Color(0xFFFFF9C4)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFFFEE58)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        DropdownButtonFormField<String>(
                          value: selectedPixKeyModel,
                          decoration: const InputDecoration(
                            labelText: 'Usar chave Pix cadastrada',
                            labelStyle: TextStyle(
                              fontSize: 11,
                              color: Color(0xFFF9A825),
                            ),
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 8,
                            ),
                          ),
                          isExpanded: true,
                          hint: const Text(
                            'Selecione uma chave já cadastrada',
                            style: TextStyle(fontSize: 12),
                          ),
                          items: _pixKeyModels.map((model) {
                            return DropdownMenuItem<String>(
                              value: model['name'],
                              child: Text(
                                '${model['name']} - ${_getPixTypeLabel(model['type']!)}',
                                style: const TextStyle(fontSize: 12),
                              ),
                            );
                          }).toList(),
                          onChanged: (value) {
                            setDialogState(() {
                              selectedPixKeyModel = value;
                              final model = _pixKeyModels.firstWhere(
                                (item) => item['name'] == value,
                                orElse: () => {},
                              );
                              if (model.isNotEmpty) {
                                selectedPixKeyType = model['type']!;
                                pixKeyController.text = model['key']!;
                              }
                            });
                          },
                        ),
                        SizedBox(
                          width: double.infinity,
                          child: TextButton.icon(
                            onPressed: () =>
                                showAddPixKeyModelDialog(setDialogState),
                            icon: const Icon(Icons.add, size: 16),
                            label: const Text(
                              'Cadastrar modelo de chave Pix',
                              style: TextStyle(fontSize: 12),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFE8EAF6), Color(0xFFC5CAE9)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFF9FA8DA)),
                    ),
                    child: DropdownButtonFormField<String>(
                      value: selectedPixKeyType,
                      decoration: const InputDecoration(
                        labelText: 'Tipo da Chave Pix *',
                        labelStyle: TextStyle(
                          fontSize: 11,
                          color: Color(0xFF3949AB),
                        ),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 8,
                        ),
                      ),
                      isExpanded: true,
                      icon: const Icon(
                        Icons.keyboard_arrow_down,
                        color: Color(0xFF5C6BC0),
                        size: 18,
                      ),
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF424242),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'phone',
                          child: Text(
                            'Telefone',
                            style: TextStyle(
                              fontSize: 12,
                              color: Color(0xFF424242),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        DropdownMenuItem(
                          value: 'cpf',
                          child: Text(
                            'CPF',
                            style: TextStyle(
                              fontSize: 12,
                              color: Color(0xFF424242),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        DropdownMenuItem(
                          value: 'cnpj',
                          child: Text(
                            'CNPJ',
                            style: TextStyle(
                              fontSize: 12,
                              color: Color(0xFF424242),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                      onChanged: (value) {
                        setDialogState(() {
                          selectedPixKeyType = value!;
                          pixKeyController.clear();
                        });
                      },
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFE1F5FE), Color(0xFFB3E5FC)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFF81D4FA)),
                    ),
                    child: TextFormField(
                      controller: pixKeyController,
                      decoration: InputDecoration(
                        labelText: 'Chave Pix *',
                        labelStyle: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF0277BD),
                        ),
                        border: InputBorder.none,
                        hintText: _getPixHintText(selectedPixKeyType),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 8,
                        ),
                      ),
                      style: const TextStyle(fontSize: 12),
                      keyboardType: selectedPixKeyType == 'phone'
                          ? TextInputType.phone
                          : TextInputType.number,
                      inputFormatters: _getPixInputFormatters(
                        selectedPixKeyType,
                      ),
                      validator: (value) =>
                          _validatePixKey(value, selectedPixKeyType),
                    ),
                  ),
                  if (showOtherDescription) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFFFFF3E0), Color(0xFFFFE0B2)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFFFCC80)),
                      ),
                      child: TextFormField(
                        controller: descriptionController,
                        decoration: const InputDecoration(
                          labelText: 'Descrição *',
                          labelStyle: TextStyle(
                            fontSize: 11,
                            color: Color(0xFFF57C00),
                          ),
                          border: InputBorder.none,
                          hintText: 'Informe do que se trata',
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 8,
                          ),
                        ),
                        style: const TextStyle(fontSize: 12),
                        maxLines: 2,
                        validator: (value) {
                          if (showOtherDescription &&
                              (value == null || value.isEmpty)) {
                            return 'Campo obrigatório para "Outros"';
                          }
                          return null;
                        },
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFFFAFAFA), Color(0xFFF5F5F5)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFFE0E0E0)),
                          ),
                          child: DropdownButtonFormField<int>(
                            value: selectedDay,
                            decoration: const InputDecoration(
                              labelText: 'Dia *',
                              labelStyle: TextStyle(
                                fontSize: 11,
                                color: Color(0xFF616161),
                              ),
                              border: InputBorder.none,
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 8,
                              ),
                            ),
                            isExpanded: true,
                            icon: const Icon(
                              Icons.keyboard_arrow_down,
                              color: Color(0xFF757575),
                              size: 18,
                            ),
                            style: const TextStyle(fontSize: 12),
                            items: List.generate(31, (i) => i + 1).map((d) {
                              return DropdownMenuItem(
                                value: d,
                                child: Text(
                                  d.toString(),
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF424242),
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              );
                            }).toList(),
                            onChanged: (value) {
                              selectedDay = value!;
                            },
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFFFAFAFA), Color(0xFFF5F5F5)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFFE0E0E0)),
                          ),
                          child: DropdownButtonFormField<int>(
                            value: selectedMonth,
                            decoration: const InputDecoration(
                              labelText: 'Mês *',
                              labelStyle: TextStyle(
                                fontSize: 11,
                                color: Color(0xFF616161),
                              ),
                              border: InputBorder.none,
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 8,
                              ),
                            ),
                            isExpanded: true,
                            icon: const Icon(
                              Icons.keyboard_arrow_down,
                              color: Color(0xFF757575),
                              size: 18,
                            ),
                            style: const TextStyle(fontSize: 12),
                            items: List.generate(12, (i) => i + 1).map((m) {
                              return DropdownMenuItem(
                                value: m,
                                child: Text(
                                  DateFormat.MMMM(
                                    'pt_BR',
                                  ).format(DateTime(2024, m)),
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF424242),
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              );
                            }).toList(),
                            onChanged: (value) {
                              selectedMonth = value!;
                            },
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFFFAFAFA), Color(0xFFF5F5F5)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFFE0E0E0)),
                          ),
                          child: DropdownButtonFormField<int>(
                            value: selectedYear,
                            decoration: const InputDecoration(
                              labelText: 'Ano *',
                              labelStyle: TextStyle(
                                fontSize: 11,
                                color: Color(0xFF616161),
                              ),
                              border: InputBorder.none,
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 8,
                              ),
                            ),
                            isExpanded: true,
                            icon: const Icon(
                              Icons.keyboard_arrow_down,
                              color: Color(0xFF757575),
                              size: 18,
                            ),
                            style: const TextStyle(fontSize: 12),
                            items: [2026, 2027, 2028, 2029, 2030].map((y) {
                              return DropdownMenuItem(
                                value: y,
                                child: Text(
                                  y.toString(),
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF424242),
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              );
                            }).toList(),
                            onChanged: (value) {
                              selectedYear = value!;
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar', style: TextStyle(fontSize: 12)),
            ),
            ElevatedButton(
              onPressed: () async {
                if (formKey.currentState!.validate()) {
                  try {
                    final numericValue = valueController.text
                        .replaceAll(RegExp(r'[^\d,]'), '')
                        .replaceAll(',', '.');

                    final pixDescription =
                        'Chave Pix (${_getPixTypeLabel(selectedPixKeyType)}): ${pixKeyController.text.trim()}';
                    final finalDescription = selectedType == 'other' &&
                            descriptionController.text.trim().isNotEmpty
                        ? '${descriptionController.text.trim()}\n$pixDescription'
                        : pixDescription;

                    List<Map<String, dynamic>> insertedRecords = [];

                    if (selectedAthleteId == 'all') {
                      final targetAthletes = selectMultipleUsers
                          ? _athletes
                              .where(
                                (athlete) => selectedAthleteIds.contains(
                                  athlete['id'] as String,
                                ),
                              )
                              .toList()
                          : _athletes;

                      final records = targetAthletes
                          .map(
                            (athlete) => {
                              'athlete_id': athlete['id'],
                              'type': selectedType,
                              'value': double.parse(numericValue),
                              'description': finalDescription,
                              'pix_key': pixKeyController.text.trim(),
                              'pix_key_type': selectedPixKeyType,
                              'day': selectedDay,
                              'month': selectedMonth,
                              'year': selectedYear,
                              'status': 'pending',
                              'created_at': DateTime.now().toIso8601String(),
                            },
                          )
                          .toList();

                      final response = await _supabase
                          .from('financial_records')
                          .insert(records)
                          .select();

                      insertedRecords = List<Map<String, dynamic>>.from(
                        response,
                      );
                    } else {
                      final response =
                          await _supabase.from('financial_records').insert({
                        'athlete_id': selectedAthleteId,
                        'type': selectedType,
                        'value': double.parse(numericValue),
                        'description': finalDescription,
                        'pix_key': pixKeyController.text.trim(),
                        'pix_key_type': selectedPixKeyType,
                        'day': selectedDay,
                        'month': selectedMonth,
                        'year': selectedYear,
                        'status': 'pending',
                        'created_at': DateTime.now().toIso8601String(),
                      }).select();

                      insertedRecords = List<Map<String, dynamic>>.from(
                        response,
                      );
                    }

                    final userIds = insertedRecords
                        .map((record) => record['athlete_id']?.toString())
                        .whereType<String>()
                        .where((id) => id.isNotEmpty)
                        .toSet()
                        .toList();

                    if (userIds.isNotEmpty) {
                      try {
                        await _supabase.functions.invoke(
                          'send-push-notification',
                          body: {
                            'userIds': userIds,
                            'title': 'Nova pendencia financeira',
                            'body':
                                'Uma nova pendencia financeira foi cadastrada. Confira no app.',
                            'type': 'financial',
                            'recordId': insertedRecords.length == 1
                                ? insertedRecords.first['id']?.toString() ?? ''
                                : '',
                          },
                        );
                      } catch (e) {
                        debugPrint('Erro ao enviar notificacao financeira: $e');
                      }
                    }

                    if (mounted) {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('✅ Registro cadastrado!'),
                          backgroundColor: Colors.green,
                        ),
                      );
                      _loadPixKeyModels();
                      _loadRecords();
                    }
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Erro: $e'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  }
                }
              },
              child: const Text('Cadastrar', style: TextStyle(fontSize: 12)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmAdminView(String recordId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar visualização'),
        content: const Text(
          'Deseja confirmar que este registro foi visualizado pelo Admin?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      try {
        await _supabase.from('financial_records').update({
          'admin_viewed': true,
          'admin_viewed_by': _supabase.auth.currentUser?.id,
          'admin_viewed_at': DateTime.now().toIso8601String(),
        }).eq('id', recordId);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ Visualização confirmada pelo Admin!'),
              backgroundColor: Colors.green,
            ),
          );
          await _loadRecords();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Erro ao confirmar visualização: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Future<void> _notifyPaymentStatus({
    required String athleteId,
    required String recordId,
    required bool approved,
  }) async {
    if (athleteId.isEmpty) return;

    try {
      await _supabase.functions.invoke(
        'send-push-notification',
        body: {
          'userId': athleteId,
          'title': approved ? 'Pagamento aprovado' : 'Pagamento recusado',
          'body': approved
              ? 'Seu comprovante foi aprovado. Consulte os detalhes no aplicativo.'
              : 'Seu comprovante nao foi aprovado. Consulte os detalhes no aplicativo.',
          'type': approved
              ? 'financial_payment_approved'
              : 'financial_payment_rejected',
          'recordId': recordId,
        },
      );
    } catch (e) {
      debugPrint('Erro ao enviar notificacao do pagamento: $e');
    }
  }

  Future<void> _approvePayment(String recordId) async {
    try {
      final updated = await _supabase
          .from('financial_records')
          .update({
            'status': 'approved',
            'approved_by': _supabase.auth.currentUser!.id,
            'approved_at': DateTime.now().toIso8601String(),
          })
          .eq('id', recordId)
          .select('athlete_id')
          .single();

      await _notifyPaymentStatus(
        athleteId: updated['athlete_id']?.toString() ?? '',
        recordId: recordId,
        approved: true,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Aprovado!'),
            backgroundColor: Colors.green,
          ),
        );
        _loadRecords();
      }
    } catch (e) {
      debugPrint('Erro aprovar: $e');
    }
  }

  Future<void> _rejectPayment(String recordId) async {
    try {
      final updated = await _supabase
          .from('financial_records')
          .update({
            'status': 'rejected',
            'approved_by': _supabase.auth.currentUser!.id,
            'approved_at': DateTime.now().toIso8601String(),
          })
          .eq('id', recordId)
          .select('athlete_id')
          .single();

      await _notifyPaymentStatus(
        athleteId: updated['athlete_id']?.toString() ?? '',
        recordId: recordId,
        approved: false,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Rejeitado!'),
            backgroundColor: Colors.red,
          ),
        );
        _loadRecords();
      }
    } catch (e) {
      debugPrint('Erro rejeitar: $e');
    }
  }

  Future<void> _viewReceipt(String receiptUrl) async {
    try {
      debugPrint('🔍 Tentando visualizar comprovante: $receiptUrl');

      String imageUrl;

      try {
        final signedUrl = await _supabase.storage
            .from('receipts')
            .createSignedUrl(receiptUrl, 300);

        debugPrint('✅ URL assinada criada com sucesso');
        imageUrl = signedUrl;
      } catch (e) {
        debugPrint('❌ Erro ao criar URL assinada: $e');

        try {
          imageUrl =
              _supabase.storage.from('receipts').getPublicUrl(receiptUrl);
          debugPrint('✅ URL pública usada como fallback');
        } catch (e2) {
          debugPrint('❌ Erro ao obter URL pública: $e2');
          throw Exception('Não foi possível acessar o comprovante');
        }
      }

      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => Dialog(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppBar(
                  title: const Text('Comprovante'),
                  automaticallyImplyLeading: false,
                  backgroundColor: Colors.transparent,
                  elevation: 0,
                  actions: [
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.black),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Image.network(
                    imageUrl,
                    errorBuilder: (context, error, stackTrace) {
                      debugPrint('❌ Erro ao carregar imagem: $error');
                      debugPrint('Stack trace: $stackTrace');

                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.error_outline,
                            size: 64,
                            color: Colors.red[300],
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'Erro ao carregar comprovante',
                            style: TextStyle(
                              color: Colors.red,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Verifique se:\n• O arquivo existe no bucket\n• As políticas de RLS estão corretas\n• O caminho do arquivo está correto',
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 12,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      );
                    },
                    loadingBuilder: (context, child, loadingProgress) {
                      if (loadingProgress == null) return child;
                      return const Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(),
                          SizedBox(height: 16),
                          Text('Carregando comprovante...'),
                        ],
                      );
                    },
                    fit: BoxFit.contain,
                  ),
                ),
              ],
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint('❌ Erro ao visualizar comprovante: $e');
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Erro'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 48, color: Colors.red),
                const SizedBox(height: 16),
                const Text(
                  'Não foi possível carregar o comprovante',
                  style: TextStyle(fontWeight: FontWeight.w600),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Erro: $e',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    }
  }

  Future<void> _navigateToAthleteProfile(FinancialRecord record) async {
    final athlete = _athleteData[record.athleteId];
    if (athlete == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Atleta não encontrado'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    Navigator.pushNamed(
      context,
      '/athlete-profile',
      arguments: {
        'athleteId': record.athleteId,
        'athleteName': athlete['full_name'],
        'recordId': record.id,
      },
    );
  }

  Map<String, dynamic>? _getAthleteDataById(String athleteId) {
    final loadedAthlete = _athleteData[athleteId];
    if (loadedAthlete != null) return loadedAthlete;

    final listedAthlete = _athletes.firstWhere(
      (item) => item['id']?.toString() == athleteId,
      orElse: () => {},
    );

    return listedAthlete.isEmpty ? null : listedAthlete;
  }

  List<FinancialRecord> _getAthleteFinancialHistoryRecords(String athleteId) {
    final records = _dashboardRecords
        .where((record) => record.athleteId == athleteId)
        .where(_recordMatchesCustomPeriod)
        .toList();

    records.sort((a, b) {
      final dateA = DateTime(a.year, a.month, a.day);
      final dateB = DateTime(b.year, b.month, b.day);
      return dateB.compareTo(dateA);
    });

    return records;
  }

  ({String label, Color color, IconData icon}) _getAthletePaymentScore(
    String athleteId,
  ) {
    final records = _getAthleteFinancialHistoryRecords(athleteId);
    if (records.isEmpty) {
      return (
        label: 'Sem histórico',
        color: Colors.grey,
        icon: Icons.remove_circle_outline,
      );
    }

    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);
    final overdueCount = records.where((record) {
      if (record.status != 'pending') return false;
      final dueDate = DateTime(record.year, record.month, record.day);
      return dueDate.isBefore(todayDate);
    }).length;
    final paidCount =
        records.where((record) => record.status == 'approved').length;
    final totalRelevant = records.length;

    if (overdueCount >= 2 ||
        (totalRelevant > 0 && overdueCount / totalRelevant >= 0.35)) {
      return (
        label: 'Inadimplente',
        color: Colors.red,
        icon: Icons.error_rounded,
      );
    }

    if (overdueCount == 1 ||
        (totalRelevant > 0 && paidCount / totalRelevant < 0.70)) {
      return (
        label: 'Oscilando',
        color: Colors.orange,
        icon: Icons.warning_amber_rounded,
      );
    }

    return (
      label: 'Bom pagador',
      color: Colors.green,
      icon: Icons.verified_rounded,
    );
  }

  Widget _buildAthleteScoreChip(String athleteId, {bool compact = false}) {
    final score = _getAthletePaymentScore(athleteId);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 7 : 9,
        vertical: compact ? 3 : 4,
      ),
      decoration: BoxDecoration(
        color: score.color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: score.color.withOpacity(0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(score.icon, size: compact ? 10 : 12, color: score.color),
          SizedBox(width: compact ? 3 : 4),
          Text(
            score.label,
            style: TextStyle(
              fontSize: compact ? 9 : 10,
              color: score.color,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  String _getMonthShortName(int month) {
    final label = DateFormat.MMM(
      'pt_BR',
    ).format(DateTime(_selectedYear, month)).replaceAll('.', '');
    return label.isEmpty
        ? month.toString().padLeft(2, '0')
        : '${label[0].toUpperCase()}${label.substring(1)}';
  }

  List<Map<String, dynamic>> _buildAthleteTimelineItems(String athleteId) {
    final records = _getAthleteFinancialHistoryRecords(athleteId);
    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);
    final months = <int, List<FinancialRecord>>{};

    for (final record in records) {
      months.putIfAbsent(record.month, () => []).add(record);
    }

    final items = <Map<String, dynamic>>[];
    for (final entry in months.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key))) {
      final monthRecords = entry.value;
      final paidValue = monthRecords
          .where((record) => record.status == 'approved')
          .fold<double>(0, (sum, record) => sum + record.value);
      final overdue = monthRecords.where((record) {
        if (record.status != 'pending') return false;
        final dueDate = DateTime(record.year, record.month, record.day);
        return dueDate.isBefore(todayDate);
      }).toList();
      final pending = monthRecords.where((record) {
        if (record.status != 'pending') return false;
        final dueDate = DateTime(record.year, record.month, record.day);
        return !dueDate.isBefore(todayDate);
      }).toList();
      final rejected =
          monthRecords.where((record) => record.status == 'rejected').toList();

      late String statusLabel;
      late IconData icon;
      late Color color;
      late double value;

      if (overdue.isNotEmpty) {
        statusLabel = 'Atrasado';
        icon = Icons.cancel_rounded;
        color = Colors.red;
        value = overdue.fold<double>(0, (sum, record) => sum + record.value);
      } else if (pending.isNotEmpty) {
        statusLabel = 'Pendente';
        icon = Icons.schedule_rounded;
        color = Colors.orange;
        value = pending.fold<double>(0, (sum, record) => sum + record.value);
      } else if (paidValue > 0) {
        statusLabel = 'Pago';
        icon = Icons.check_circle_rounded;
        color = Colors.green;
        value = paidValue;
      } else if (rejected.isNotEmpty) {
        statusLabel = 'Rejeitado';
        icon = Icons.block_rounded;
        color = Colors.red;
        value = rejected.fold<double>(0, (sum, record) => sum + record.value);
      } else {
        statusLabel = 'Sem movimento';
        icon = Icons.remove_circle_outline;
        color = Colors.grey;
        value = 0;
      }

      items.add({
        'month': entry.key,
        'label': '${_getMonthShortName(entry.key)} — $statusLabel',
        'icon': icon,
        'color': color,
        'value': value,
        'records': monthRecords.length,
      });
    }

    return items;
  }

  void _showAthleteFinancialHistory(String athleteId) {
    final athleteName = _getAthleteName(athleteId);
    final records = _getAthleteFinancialHistoryRecords(athleteId);
    final timelineItems = _buildAthleteTimelineItems(athleteId);
    final score = _getAthletePaymentScore(athleteId);
    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);

    final paidValue = records
        .where((record) => record.status == 'approved')
        .fold<double>(0, (sum, record) => sum + record.value);
    final overdueRecords = records.where((record) {
      if (record.status != 'pending') return false;
      final dueDate = DateTime(record.year, record.month, record.day);
      return dueDate.isBefore(todayDate);
    }).toList();
    final overdueValue = overdueRecords.fold<double>(
      0,
      (sum, record) => sum + record.value,
    );
    final pendingRecords = records.where((record) {
      if (record.status != 'pending') return false;
      final dueDate = DateTime(record.year, record.month, record.day);
      return !dueDate.isBefore(todayDate);
    }).toList();
    final pendingValue = pendingRecords.fold<double>(
      0,
      (sum, record) => sum + record.value,
    );

    Widget summaryCard({
      required String label,
      required double value,
      required IconData icon,
      required Color color,
    }) {
      return Expanded(
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: color.withOpacity(0.08),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color.withOpacity(0.22)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: color, size: 18),
              const SizedBox(height: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  color: color.withOpacity(0.9),
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                _formatCurrencyCompact(value),
                style: TextStyle(
                  fontSize: 14,
                  color: color,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      );
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => SafeArea(
        top: false,
        child: Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.90,
          ),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.white, Color(0xFFF7F8FA)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: SingleChildScrollView(
            padding: EdgeInsets.only(
              left: 18,
              right: 18,
              top: 12,
              bottom: MediaQuery.of(context).viewPadding.bottom + 24,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(
                  child: Container(
                    width: 42,
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE0E0E0),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    CircleAvatar(
                      radius: 24,
                      backgroundColor: score.color.withOpacity(0.12),
                      child: Icon(score.icon, color: score.color, size: 24),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            athleteName,
                            style: const TextStyle(
                              fontSize: 18,
                              color: Color(0xFF2C3E5A),
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 6),
                          _buildAthleteScoreChip(athleteId),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    summaryCard(
                      label: 'Pago',
                      value: paidValue,
                      icon: Icons.check_circle_rounded,
                      color: Colors.green,
                    ),
                    const SizedBox(width: 8),
                    summaryCard(
                      label: 'Atrasado',
                      value: overdueValue,
                      icon: Icons.warning_rounded,
                      color: Colors.red,
                    ),
                    const SizedBox(width: 8),
                    summaryCard(
                      label: 'Pendente',
                      value: pendingValue,
                      icon: Icons.schedule_rounded,
                      color: Colors.orange,
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                const Text(
                  'Linha do tempo financeira',
                  style: TextStyle(
                    fontSize: 14,
                    color: Color(0xFF2C3E5A),
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 10),
                if (timelineItems.isEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF6F8FB),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFE1E6ED)),
                    ),
                    child: const Text(
                      'Nenhum registro financeiro no período selecionado.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Color(0xFF757575),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  )
                else
                  ...timelineItems.map((item) {
                    final color = item['color'] as Color;
                    final isLast = timelineItems.last == item;
                    return IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(
                            width: 34,
                            child: Column(
                              children: [
                                Container(
                                  width: 28,
                                  height: 28,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: color.withOpacity(0.12),
                                    border: Border.all(
                                      color: color.withOpacity(0.35),
                                    ),
                                  ),
                                  child: Icon(
                                    item['icon'] as IconData,
                                    color: color,
                                    size: 16,
                                  ),
                                ),
                                if (!isLast)
                                  Expanded(
                                    child: Container(
                                      width: 2,
                                      margin: const EdgeInsets.symmetric(
                                        vertical: 3,
                                      ),
                                      color: color.withOpacity(0.18),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 10),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: color.withOpacity(0.16),
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.04),
                                    blurRadius: 8,
                                    offset: const Offset(0, 3),
                                  ),
                                ],
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          item['label'] as String,
                                          style: TextStyle(
                                            fontSize: 13,
                                            color: color,
                                            fontWeight: FontWeight.w900,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          '${item['records']} registro(s) no mês',
                                          style: const TextStyle(
                                            fontSize: 10,
                                            color: Color(0xFF757575),
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Text(
                                    _formatCurrencyCompact(
                                      item['value'] as double,
                                    ),
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Color(0xFF2C3E5A),
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _getAthleteName(String athleteId) {
    if (athleteId == 'all') return 'Todos';
    final athlete = _athleteData[athleteId];
    if (athlete != null && athlete['full_name'] != null) {
      return athlete['full_name'].toString();
    }

    final listedAthlete = _athletes.firstWhere(
      (item) => item['id']?.toString() == athleteId,
      orElse: () => {},
    );

    if (listedAthlete.isNotEmpty && listedAthlete['full_name'] != null) {
      return listedAthlete['full_name'].toString();
    }

    return 'Atleta não encontrado';
  }

  bool _isOverdue(FinancialRecord record) {
    if (record.status != 'pending') return false;
    final dueDate = DateTime(record.year, record.month, record.day);
    final today = DateTime.now();
    return dueDate.isBefore(DateTime(today.year, today.month, today.day));
  }

  Widget _buildStatusBadge(String status, {bool isOverdue = false}) {
    Color bgColor;
    Color textColor;
    IconData icon;
    String label;

    if (isOverdue) {
      bgColor = Colors.red;
      textColor = Colors.white;
      icon = Icons.warning;
      label = 'Atrasado';
    } else {
      switch (status) {
        case 'approved':
          bgColor = Colors.green;
          textColor = Colors.white;
          icon = Icons.check_circle;
          label = 'Aprovado';
          break;
        case 'pending':
          bgColor = Colors.orange;
          textColor = Colors.white;
          icon = Icons.schedule;
          label = 'Pendente';
          break;
        case 'rejected':
          bgColor = Colors.red;
          textColor = Colors.white;
          icon = Icons.cancel;
          label = 'Rejeitado';
          break;
        default:
          bgColor = Colors.grey;
          textColor = Colors.white;
          icon = Icons.help_outline;
          label = 'Desconhecido';
      }
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: textColor),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: textColor,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  double _getDashboardReceivedValue() {
    return _dashboardRecords
        .where((record) => record.status == 'approved')
        .fold<double>(0, (sum, record) => sum + record.value);
  }

  double _getDashboardPendingValue() {
    return _dashboardRecords
        .where((record) => record.status == 'pending')
        .fold<double>(0, (sum, record) => sum + record.value);
  }

  List<FinancialRecord> _getDashboardOverdueRecords() {
    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);

    final overdueRecords = _dashboardRecords.where((record) {
      if (!_recordMatchesCustomPeriod(record)) return false;
      if (_onlyWithReceipt &&
          (record.receiptUrl == null || record.receiptUrl!.trim().isEmpty)) {
        return false;
      }
      if (record.status != 'pending') return false;
      final dueDate = DateTime(record.year, record.month, record.day);
      return dueDate.isBefore(todayDate);
    }).toList();

    overdueRecords.sort((a, b) {
      final dateA = DateTime(a.year, a.month, a.day);
      final dateB = DateTime(b.year, b.month, b.day);
      return dateA.compareTo(dateB);
    });

    return overdueRecords;
  }

  double _getDashboardOverdueValue() {
    return _getDashboardOverdueRecords().fold<double>(
      0,
      (sum, record) => sum + record.value,
    );
  }

  Map<String, List<FinancialRecord>> _getDashboardOverdueRecordsByAthlete() {
    final groupedRecords = <String, List<FinancialRecord>>{};

    for (final record in _getDashboardOverdueRecords()) {
      groupedRecords.putIfAbsent(record.athleteId, () => []).add(record);
    }

    return groupedRecords;
  }

  List<FinancialRecord> _getDashboardPendingReceiptRecords() {
    final receiptRecords = _dashboardRecords.where((record) {
      if (!_recordMatchesCustomPeriod(record)) return false;
      return record.status == 'pending' &&
          record.receiptUrl != null &&
          record.receiptUrl!.trim().isNotEmpty;
    }).toList();

    receiptRecords.sort((a, b) {
      final dateA = DateTime(a.year, a.month, a.day);
      final dateB = DateTime(b.year, b.month, b.day);
      return dateA.compareTo(dateB);
    });

    return receiptRecords;
  }

  double _getDashboardPendingReceiptsValue() {
    return _getDashboardPendingReceiptRecords().fold<double>(
      0,
      (sum, record) => sum + record.value,
    );
  }

  Map<int, double> _getMonthlyRevenueValues() {
    final values = {for (var month = 1; month <= 12; month++) month: 0.0};

    for (final record in _dashboardRecords) {
      if (record.status == 'approved') {
        values[record.month] = (values[record.month] ?? 0) + record.value;
      }
    }

    return values;
  }

  Map<String, double> _getRevenueByTypeValues() {
    final values = <String, double>{
      'monthly': 0,
      'games': 0,
      'maintenance': 0,
      'other': 0,
    };

    for (final record in _dashboardRecords) {
      if (record.status == 'approved') {
        values[record.type] = (values[record.type] ?? 0) + record.value;
      }
    }

    return values;
  }

  String _formatCurrencyCompact(double value) {
    return 'R\$ ${value.toStringAsFixed(0)}';
  }

  Widget _buildDashboardValueCard({
    required String label,
    required double value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color.withOpacity(0.12), color.withOpacity(0.04)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 10,
                    color: Color(0xFF757575),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _formatCurrencyCompact(value),
                  style: TextStyle(
                    fontSize: 16,
                    color: color,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMonthlyRevenueChart() {
    final monthlyValues = _getMonthlyRevenueValues();
    final maxValue = monthlyValues.values.fold<double>(
      0,
      (max, value) => value > max ? value : max,
    );

    return SizedBox(
      height: 140,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(12, (index) {
          final month = index + 1;
          final value = monthlyValues[month] ?? 0;
          final heightFactor = maxValue == 0 ? 0.05 : (value / maxValue);
          final monthLabel = DateFormat.MMM(
            'pt_BR',
          ).format(DateTime(_selectedYear, month)).replaceAll('.', '');

          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    value > 0 ? value.toStringAsFixed(0) : '',
                    style: const TextStyle(
                      fontSize: 8,
                      color: Color(0xFF2C3E5A),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    height: 85 * heightFactor,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF2C3E5A), Color(0xFF4A6FA5)],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    monthLabel,
                    style: const TextStyle(
                      fontSize: 8,
                      color: Color(0xFF757575),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildRevenueByType() {
    final typeValues = _getRevenueByTypeValues();
    final total = typeValues.values.fold<double>(
      0,
      (sum, value) => sum + value,
    );

    return Column(
      children: typeValues.entries.map((entry) {
        final color = _getTypeColor(entry.key);
        final percent = total == 0 ? 0.0 : entry.value / total;

        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              Icon(_getTypeIcon(entry.key), color: color, size: 16),
              const SizedBox(width: 6),
              SizedBox(
                width: 82,
                child: Text(
                  _getTypeLabel(entry.key),
                  style: const TextStyle(
                    fontSize: 10,
                    color: Color(0xFF424242),
                    fontWeight: FontWeight.w700,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: LinearProgressIndicator(
                    value: percent,
                    minHeight: 8,
                    backgroundColor: color.withOpacity(0.12),
                    valueColor: AlwaysStoppedAnimation<Color>(color),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 56,
                child: Text(
                  _formatCurrencyCompact(entry.value),
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    fontSize: 10,
                    color: Color(0xFF2C3E5A),
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildDashboardAlertsCard() {
    final overdueRecords = _getDashboardOverdueRecords();
    final overdueAthletes =
        overdueRecords.map((record) => record.athleteId).toSet().length;
    final overdueValue = _getDashboardOverdueValue();
    final pendingRecords = _dashboardRecords
        .where((record) => record.status == 'pending')
        .toList();
    final pendingValue = pendingRecords.fold<double>(
      0,
      (sum, record) => sum + record.value,
    );
    final pendingReceiptRecords = _getDashboardPendingReceiptRecords();
    final pendingReceiptValue = _getDashboardPendingReceiptsValue();

    final hasAlerts = overdueRecords.isNotEmpty ||
        pendingRecords.isNotEmpty ||
        pendingReceiptRecords.isNotEmpty;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: hasAlerts
              ? const [Color(0xFFFFF3E0), Color(0xFFFFF8E1)]
              : const [Color(0xFFE8F5E9), Color(0xFFF1F8E9)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: hasAlerts ? const Color(0xFFFFCC80) : const Color(0xFFA5D6A7),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            spreadRadius: 1,
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: hasAlerts
                      ? Colors.orange.withOpacity(0.14)
                      : Colors.green.withOpacity(0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  hasAlerts
                      ? Icons.notifications_active_rounded
                      : Icons.verified_rounded,
                  color: hasAlerts ? Colors.orange[800] : Colors.green,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Alertas financeiros',
                      style: TextStyle(
                        fontSize: 14,
                        color: Color(0xFF2C3E5A),
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      hasAlerts
                          ? '$overdueAthletes atleta(s) em atraso • ${_formatCurrencyCompact(pendingValue)} pendente(s) • ${pendingReceiptRecords.length} comprovante(s)'
                          : 'Tudo certo no filtro atual',
                      style: const TextStyle(
                        fontSize: 10,
                        color: Color(0xFF757575),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              if (hasAlerts)
                TextButton(
                  onPressed: () {
                    _openFinancialRecords(
                      status: overdueRecords.isNotEmpty ? 'overdue' : 'pending',
                    );
                  },
                  child: const Text(
                    'Resolver',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildAlertMetric(
                  label: 'Atrasados',
                  value: '$overdueAthletes atleta(s)',
                  subtitle: _formatCurrencyCompact(overdueValue),
                  icon: Icons.warning_rounded,
                  color: Colors.red,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildAlertMetric(
                  label: 'Pendentes',
                  value: '${pendingRecords.length} cobrança(s)',
                  subtitle: _formatCurrencyCompact(pendingValue),
                  icon: Icons.schedule_rounded,
                  color: Colors.orange,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildAlertMetric(
                  label: 'Comprovantes',
                  value: '${pendingReceiptRecords.length} pendente(s)',
                  subtitle: _formatCurrencyCompact(pendingReceiptValue),
                  icon: Icons.attach_file_rounded,
                  color: Colors.blue,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAlertMetric({
    required String label,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.88),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.14)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 10,
                    color: Color(0xFF757575),
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 12,
                    color: color,
                    fontWeight: FontWeight.w900,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 10,
                    color: Color(0xFF2C3E5A),
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPendingReceiptsCard() {
    final pendingReceiptRecords = _getDashboardPendingReceiptRecords();

    if (pendingReceiptRecords.isEmpty) {
      return Container(
        width: double.infinity,
        margin: const EdgeInsets.only(top: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFE3F2FD), Color(0xFFF5FAFF)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Color(0xFFBBDEFB)),
        ),
        child: const Row(
          children: [
            Icon(Icons.attach_file_rounded, color: Colors.blue, size: 22),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Nenhum comprovante aguardando aprovação.',
                style: TextStyle(
                  fontSize: 12,
                  color: Color(0xFF1565C0),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      );
    }

    final visibleRecords = pendingReceiptRecords.take(4).toList();

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFE3F2FD), Color(0xFFF5FAFF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Color(0xFF90CAF9)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.attach_file_rounded,
                  color: Colors.blue,
                  size: 18,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Aguardando aprovação',
                      style: TextStyle(
                        fontSize: 13,
                        color: Color(0xFF1565C0),
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      '${pendingReceiptRecords.length} comprovante(s) enviado(s)',
                      style: const TextStyle(
                        fontSize: 10,
                        color: Color(0xFF42A5F5),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: () {
                  _openFinancialRecords(
                    status: 'pending',
                    onlyWithReceipt: true,
                  );
                },
                child: const Text(
                  'Revisar',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...visibleRecords.map((record) {
            final dueDate =
                '${record.day.toString().padLeft(2, '0')}/${record.month.toString().padLeft(2, '0')}/${record.year}';

            return InkWell(
              onTap: () => _showRecordDetails(record),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.9),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blue.withOpacity(0.12)),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 15,
                      backgroundColor: Colors.blue.withOpacity(0.1),
                      child: Text(
                        _getAthleteName(record.athleteId).trim().isNotEmpty
                            ? _getAthleteName(
                                record.athleteId,
                              ).trim()[0].toUpperCase()
                            : 'A',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.blue,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${_getAthleteName(record.athleteId)} enviou comprovante',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF2C3E5A),
                              fontWeight: FontWeight.w800,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            '${record.typeLabel} • vencimento $dueDate',
                            style: const TextStyle(
                              fontSize: 10,
                              color: Color(0xFF757575),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _formatCurrencyCompact(record.value),
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.blue,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
          if (pendingReceiptRecords.length > visibleRecords.length)
            Text(
              '+ ${pendingReceiptRecords.length - visibleRecords.length} comprovante(s) aguardando revisão',
              style: const TextStyle(
                fontSize: 10,
                color: Color(0xFF1565C0),
                fontWeight: FontWeight.w700,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildOverdueAthletesCard() {
    final groupedRecords = _getDashboardOverdueRecordsByAthlete();
    final overdueEntries = groupedRecords.entries.toList()
      ..sort((a, b) {
        final valueA = a.value.fold<double>(
          0,
          (sum, record) => sum + record.value,
        );
        final valueB = b.value.fold<double>(
          0,
          (sum, record) => sum + record.value,
        );
        return valueB.compareTo(valueA);
      });
    final overdueValue = _getDashboardOverdueValue();

    if (overdueEntries.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFE8F5E9), Color(0xFFF1F8E9)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Color(0xFFA5D6A7)),
        ),
        child: const Row(
          children: [
            Icon(Icons.check_circle, color: Colors.green, size: 22),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Nenhum atleta em atraso no filtro atual.',
                style: TextStyle(
                  fontSize: 12,
                  color: Color(0xFF2E7D32),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      );
    }

    final visibleEntries = overdueEntries.take(5).toList();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFFEBEE), Color(0xFFFFF8F8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Color(0xFFFFCDD2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.warning_rounded,
                  color: Colors.red,
                  size: 18,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Top devedores',
                      style: TextStyle(
                        fontSize: 13,
                        color: Color(0xFFB71C1C),
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      '${overdueEntries.length} atleta(s) • ${_formatCurrencyCompact(overdueValue)} em aberto',
                      style: const TextStyle(
                        fontSize: 10,
                        color: Color(0xFFD32F2F),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () {
                      _openFinancialRecords(status: 'overdue');
                    },
                    child: const Text(
                      'Ver todos',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _sendOverdueChargesWhatsApp,
                    icon: const Icon(Icons.chat_rounded, size: 14),
                    label: const Text(
                      'Cobrar',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...visibleEntries.map((entry) {
            final records = entry.value;
            final total = records.fold<double>(
              0,
              (sum, record) => sum + record.value,
            );
            final oldestRecord = records.reduce((a, b) {
              final dateA = DateTime(a.year, a.month, a.day);
              final dateB = DateTime(b.year, b.month, b.day);
              return dateA.isBefore(dateB) ? a : b;
            });
            final oldestDueDate =
                '${oldestRecord.day.toString().padLeft(2, '0')}/${oldestRecord.month.toString().padLeft(2, '0')}/${oldestRecord.year}';

            return InkWell(
              onTap: () => _showAthleteFinancialHistory(entry.key),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.9),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.red.withOpacity(0.12)),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 15,
                      backgroundColor: Colors.red.withOpacity(0.1),
                      child: Text(
                        _getAthleteName(entry.key).trim().isNotEmpty
                            ? _getAthleteName(entry.key).trim()[0].toUpperCase()
                            : 'A',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.red,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _getAthleteName(entry.key),
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF2C3E5A),
                              fontWeight: FontWeight.w800,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            '${records.length} registro(s) • mais antigo: $oldestDueDate',
                            style: const TextStyle(
                              fontSize: 10,
                              color: Color(0xFF757575),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          _formatCurrencyCompact(total),
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.red,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        IconButton(
                          constraints: const BoxConstraints(),
                          padding: EdgeInsets.zero,
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(
                            Icons.chat_rounded,
                            size: 18,
                            color: Color(0xFF25D366),
                          ),
                          onPressed: () =>
                              _sendRecordChargeWhatsApp(oldestRecord),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          }),
          if (overdueEntries.length > visibleEntries.length)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                '+ ${overdueEntries.length - visibleEntries.length} atleta(s) em atraso',
                style: const TextStyle(
                  fontSize: 10,
                  color: Color(0xFFD32F2F),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildIntelligentFiltersPanel() {
    Widget chip({
      required String label,
      required IconData icon,
      required bool selected,
      required VoidCallback onTap,
      Color? color,
    }) {
      final chipColor = color ?? olympusBlue;
      return FilterChip(
        selected: selected,
        label: Text(label),
        avatar:
            Icon(icon, size: 16, color: selected ? Colors.white : chipColor),
        selectedColor: chipColor,
        checkmarkColor: Colors.white,
        labelStyle: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: selected ? Colors.white : chipColor,
        ),
        backgroundColor: chipColor.withOpacity(0.08),
        side: BorderSide(color: chipColor.withOpacity(0.22)),
        onSelected: (_) => onTap(),
      );
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE3E8EF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.filter_alt_rounded,
                size: 16,
                color: Color(0xFF2C3E5A),
              ),
              SizedBox(width: 6),
              Text(
                'Filtro inteligente',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF2C3E5A),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              chip(
                label: 'Somente atrasados',
                icon: Icons.warning_rounded,
                selected: _selectedStatus == 'overdue',
                color: Colors.red,
                onTap: () {
                  setState(() {
                    _selectedStatus =
                        _selectedStatus == 'overdue' ? 'all' : 'overdue';
                  });
                  _applyFinancialFilterChanges();
                },
              ),
              chip(
                label: 'Com comprovante',
                icon: Icons.attach_file_rounded,
                selected: _onlyWithReceipt,
                color: Colors.blue,
                onTap: () {
                  setState(() {
                    _onlyWithReceipt = !_onlyWithReceipt;
                  });
                  _applyFinancialFilterChanges();
                },
              ),
              chip(
                label: _getSelectedAthleteFilterLabel(),
                icon: Icons.person_search_rounded,
                selected: _selectedAthleteId != 'all',
                onTap: _showAthleteFilterPicker,
              ),
              chip(
                label: _getCustomPeriodLabel(),
                icon: Icons.date_range_rounded,
                selected: _hasCustomPeriodFilter,
                color: Colors.deepPurple,
                onTap: _selectCustomPeriod,
              ),
              if (_hasCustomPeriodFilter ||
                  _onlyWithReceipt ||
                  _selectedStatus != 'all' ||
                  _selectedAthleteId != 'all')
                ActionChip(
                  label: const Text('Limpar filtros'),
                  avatar: const Icon(Icons.clear, size: 16),
                  onPressed: () {
                    setState(() {
                      _selectedStatus = 'all';
                      _selectedAthleteId = 'all';
                      _onlyWithReceipt = false;
                      _customStartDate = null;
                      _customEndDate = null;
                    });
                    _applyFinancialFilterChanges();
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAutomaticInsightsCard() {
    final approved = _dashboardRecords
        .where((record) => record.status == 'approved')
        .toList();
    final overdue = _getDashboardOverdueRecords();
    final insights = <String>[];

    final typeValues = _getRevenueByTypeValues();
    final totalApprovedValue = typeValues.values.fold<double>(
      0,
      (sum, value) => sum + value,
    );
    final typeEntries = typeValues.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    if (typeEntries.isNotEmpty &&
        typeEntries.first.value > 0 &&
        totalApprovedValue > 0) {
      final percent =
          ((typeEntries.first.value / totalApprovedValue) * 100).round();
      insights.add(
        '${_getTypeLabel(typeEntries.first.key)} representa $percent% da receita recebida (${_formatCurrencyCompact(typeEntries.first.value)}).',
      );
    }

    final monthlyValues = _getMonthlyRevenueValues();
    final monthEntries = monthlyValues.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    if (monthEntries.isNotEmpty && monthEntries.first.value > 0) {
      final monthName = DateFormat.MMMM(
        'pt_BR',
      ).format(DateTime(_selectedYear, monthEntries.first.key));
      final formattedMonth =
          '${monthName[0].toUpperCase()}${monthName.substring(1)}';
      insights.add(
        '$formattedMonth foi o melhor mês do ano (${_formatCurrencyCompact(monthEntries.first.value)}).',
      );
    }

    final currentMonthValue = monthlyValues[_selectedMonth] ?? 0;
    final previousMonth = _selectedMonth == 1 ? 12 : _selectedMonth - 1;
    final previousMonthValue = monthlyValues[previousMonth] ?? 0;
    if (previousMonthValue > 0) {
      final variation =
          (((currentMonthValue - previousMonthValue) / previousMonthValue) *
                  100)
              .round();
      final direction = variation >= 0 ? 'subiu' : 'caiu';
      insights.add(
        'Este mês $direction ${variation.abs()}% vs mês anterior (${_formatCurrencyCompact(currentMonthValue)} vs ${_formatCurrencyCompact(previousMonthValue)}).',
      );
    }

    if (overdue.isNotEmpty) {
      final totalOverdue = overdue.fold<double>(
        0,
        (sum, record) => sum + record.value,
      );
      final grouped = _getDashboardOverdueRecordsByAthlete().entries.toList()
        ..sort((a, b) {
          final valueA = a.value.fold<double>(
            0,
            (sum, record) => sum + record.value,
          );
          final valueB = b.value.fold<double>(
            0,
            (sum, record) => sum + record.value,
          );
          return valueB.compareTo(valueA);
        });
      if (grouped.isNotEmpty) {
        final topAthleteValue = grouped.first.value.fold<double>(
          0,
          (sum, record) => sum + record.value,
        );
        final topAthleteName = _getAthleteName(grouped.first.key);
        insights.add(
          '$topAthleteName é o atleta com mais atraso (${_formatCurrencyCompact(topAthleteValue)}).',
        );
      }
      final topThree = grouped.take(3).fold<double>(0, (sum, entry) {
        return sum +
            entry.value.fold<double>(
              0,
              (innerSum, record) => innerSum + record.value,
            );
      });
      final percent =
          totalOverdue == 0 ? 0 : ((topThree / totalOverdue) * 100).round();
      insights.add(
        'Top 3 atletas representam $percent% do atraso (${_formatCurrencyCompact(topThree)}).',
      );
    }

    if (approved.isEmpty && overdue.isEmpty) {
      insights.add(
        'Ainda não há dados suficientes para gerar insights no filtro atual.',
      );
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFEDE7F6), Color(0xFFF8F5FF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Color(0xFFD1C4E9)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.psychology_alt_rounded,
                color: Colors.deepPurple,
                size: 20,
              ),
              SizedBox(width: 8),
              Text(
                'Insights inteligentes',
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.deepPurple,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...insights.map(
            (text) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.auto_awesome_rounded,
                    size: 13,
                    color: Colors.deepPurple,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      text,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF4527A0),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFinancialDashboard() {
    final receivedValue = _getDashboardReceivedValue();
    final pendingValue = _getDashboardPendingValue();
    final totalValue = receivedValue + pendingValue;
    final receivedPercent = totalValue == 0 ? 0.0 : receivedValue / totalValue;
    final pendingPercent = totalValue == 0 ? 0.0 : pendingValue / totalValue;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE3E8EF)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            spreadRadius: 1,
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildFinancialAccessControlCard(),
          _buildDashboardAlertsCard(),
          Row(
            children: [
              const Icon(
                Icons.dashboard_rounded,
                size: 16,
                color: Color(0xFF2C3E5A),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Dashboard financeiro $_selectedYear',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF2C3E5A),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _buildDashboardValueCard(
                  label: 'Recebido',
                  value: receivedValue,
                  icon: Icons.check_circle,
                  color: Colors.green,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildDashboardValueCard(
                  label: 'Pendente',
                  value: pendingValue,
                  icon: Icons.schedule,
                  color: Colors.orange,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Row(
              children: [
                Expanded(
                  flex: (receivedPercent * 100).round().clamp(1, 100).toInt(),
                  child: Container(height: 10, color: Colors.green),
                ),
                Expanded(
                  flex: (pendingPercent * 100).round().clamp(1, 100).toInt(),
                  child: Container(height: 10, color: Colors.orange),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Gráfico mensal - recebido',
            style: TextStyle(
              fontSize: 11,
              color: Color(0xFF2C3E5A),
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          _buildMonthlyRevenueChart(),
          const SizedBox(height: 12),
          const Text(
            'Receita por tipo',
            style: TextStyle(
              fontSize: 11,
              color: Color(0xFF2C3E5A),
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          _buildRevenueByType(),
          _buildAutomaticInsightsCard(),
          const SizedBox(height: 12),
          _buildOverdueAthletesCard(),
          _buildPendingReceiptsCard(),
        ],
      ),
    );
  }

  Widget _buildDashboardHomePage() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFFF7F8FA), Color(0xFFEEF2F7)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildIntelligentFiltersPanel(),
              const SizedBox(height: 12),
              _buildFinancialDashboard(),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFFE3E8EF)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.06),
                      spreadRadius: 1,
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Acesso rápido',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF2C3E5A),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          _openFinancialRecords(status: 'all');
                        },
                        icon: const Icon(Icons.list_alt_rounded),
                        label: const Text('Ir para registros financeiros'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: olympusBlue,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _showCreateRecordDialog,
                        icon: const Icon(Icons.add_rounded),
                        label: const Text('Cadastrar novo registro'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: olympusBlue,
                          side: BorderSide(color: olympusBlue),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openFinancialDashboard() {
    if (!mounted) return;
    setState(() {
      _showDashboardPage = true;
    });
  }

  void _openFinancialRecords({
    String? status,
    String? type,
    String? athleteId,
    bool onlyWithReceipt = false,
  }) {
    if (!mounted) return;
    setState(() {
      if (status != null) _selectedStatus = status;
      if (type != null) _selectedType = type;
      if (athleteId != null) _selectedAthleteId = athleteId;
      _onlyWithReceipt = onlyWithReceipt;
      _showDashboardPage = false;
    });
    _saveFinancialFilters();
    _loadRecords();
  }

  Future<bool> _handleFinancialBack() async {
    if (!_showDashboardPage) {
      _openFinancialDashboard();
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final totalRecords = _records.length;
    final approvedRecords =
        _records.where((r) => r.status == 'approved').length;
    final pendingRecords = _records.where((r) {
      if (r.status != 'pending') return false;
      final dueDate = DateTime(r.year, r.month, r.day);
      final today = DateTime.now();
      return !dueDate.isBefore(DateTime(today.year, today.month, today.day));
    }).length;
    final overdueRecords = _records.where((r) {
      if (r.status != 'pending') return false;
      final dueDate = DateTime(r.year, r.month, r.day);
      final today = DateTime.now();
      return dueDate.isBefore(DateTime(today.year, today.month, today.day));
    }).length;

    final totalValue = _records.fold<double>(0, (sum, r) => sum + r.value);
    final approvedValue = _records
        .where((r) => r.status == 'approved')
        .fold<double>(0, (sum, r) => sum + r.value);
    final pendingValue = _records.where((r) {
      if (r.status != 'pending') return false;
      final dueDate = DateTime(r.year, r.month, r.day);
      final today = DateTime.now();
      return !dueDate.isBefore(
        DateTime(today.year, today.month, today.day),
      );
    }).fold<double>(0, (sum, r) => sum + r.value);
    final overdueValue = _records.where((r) {
      if (r.status != 'pending') return false;
      final dueDate = DateTime(r.year, r.month, r.day);
      final today = DateTime.now();
      return dueDate.isBefore(DateTime(today.year, today.month, today.day));
    }).fold<double>(0, (sum, r) => sum + r.value);
    final filteredRecords = _getFilteredRecords();

    return WillPopScope(
      onWillPop: _handleFinancialBack,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            _showDashboardPage ? 'Dashboard Financeiro' : 'Financeiro - Admin',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 20),
          ),
          elevation: 0,
          leading: !_showDashboardPage
              ? IconButton(
                  icon: const Icon(Icons.arrow_back_rounded),
                  tooltip: 'Voltar para o início do financeiro',
                  onPressed: _openFinancialDashboard,
                )
              : null,
          actions: [
            if (!_showDashboardPage)
              IconButton(
                icon: const Icon(Icons.dashboard_rounded),
                tooltip: 'Dashboard',
                onPressed: _openFinancialDashboard,
              ),
            if (_showDashboardPage)
              IconButton(
                icon: const Icon(Icons.list_alt_rounded),
                tooltip: 'Registros',
                onPressed: () => _openFinancialRecords(status: _selectedStatus),
              ),
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _loadRecords,
            ),
          ],
        ),
        floatingActionButton: _showDashboardPage
            ? null
            : FloatingActionButton.extended(
                onPressed: _showCreateRecordDialog,
                icon: const Icon(Icons.add, color: Colors.white),
                label: const Text(
                  'Cadastrar',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                backgroundColor: _branding.primaryColor,
              ),
        body: _showDashboardPage
            ? _buildDashboardHomePage()
            : Column(
                children: [
                  if (_loadingRecords && _records.isNotEmpty)
                    const LinearProgressIndicator(minHeight: 3),
                  Container(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xFFF7F8FA), Color(0xFFEEF2F7)],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: GestureDetector(
                                onTap: () {
                                  setState(() {
                                    _selectedStatus = 'all';
                                    _loadRecords();
                                  });
                                },
                                child: _buildCompactCard(
                                  'Total',
                                  totalRecords,
                                  Icons.receipt_long,
                                  _branding.premiumCardColor,
                                  totalValue,
                                  _selectedStatus == 'all',
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: GestureDetector(
                                onTap: () {
                                  setState(() {
                                    _selectedStatus = 'approved';
                                    _loadRecords();
                                  });
                                },
                                child: _buildCompactCard(
                                  'Pagos',
                                  approvedRecords,
                                  Icons.check_circle,
                                  Colors.green,
                                  approvedValue,
                                  _selectedStatus == 'approved',
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: GestureDetector(
                                onTap: () {
                                  setState(() {
                                    _selectedStatus = 'pending';
                                    _loadRecords();
                                  });
                                },
                                child: _buildCompactCard(
                                  'Pendentes',
                                  pendingRecords,
                                  Icons.schedule,
                                  Colors.orange,
                                  pendingValue,
                                  _selectedStatus == 'pending',
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: GestureDetector(
                                onTap: () {
                                  setState(() {
                                    _selectedStatus = 'overdue';
                                    _loadRecords();
                                  });
                                },
                                child: _buildCompactCard(
                                  'Atrasados',
                                  overdueRecords,
                                  Icons.warning,
                                  Colors.red,
                                  overdueValue,
                                  _selectedStatus == 'overdue',
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: const Color(0xFFE3E8EF)),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.06),
                                spreadRadius: 1,
                                blurRadius: 8,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  const Icon(
                                    Icons.tune_rounded,
                                    size: 16,
                                    color: Color(0xFF2C3E5A),
                                  ),
                                  const SizedBox(width: 6),
                                  const Text(
                                    'Filtros',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF2C3E5A),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          'Mês',
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: Color(0xFF757575),
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                          ),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFF6F8FB),
                                            borderRadius: BorderRadius.circular(
                                              10,
                                            ),
                                            border: Border.all(
                                              color: const Color(0xFFE1E6ED),
                                            ),
                                          ),
                                          child: DropdownButton<int>(
                                            value: _selectedMonth,
                                            isExpanded: true,
                                            underline: const SizedBox(),
                                            icon: const Icon(
                                              Icons.keyboard_arrow_down,
                                              color: Color(0xFF757575),
                                              size: 16,
                                            ),
                                            items:
                                                List.generate(12, (i) => i + 1)
                                                    .map(
                                                      (m) => DropdownMenuItem(
                                                        value: m,
                                                        child: Text(
                                                          DateFormat.MMMM(
                                                            'pt_BR',
                                                          ).format(
                                                            DateTime(2024, m),
                                                          ),
                                                          style:
                                                              const TextStyle(
                                                            fontSize: 12,
                                                            color: Color(
                                                              0xFF424242,
                                                            ),
                                                            fontWeight:
                                                                FontWeight.w500,
                                                          ),
                                                        ),
                                                      ),
                                                    )
                                                    .toList(),
                                            onChanged: (v) => setState(() {
                                              _selectedMonth = v!;
                                              _saveFinancialFilters();
                                              _loadRecords();
                                            }),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          'Ano',
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: Color(0xFF757575),
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                          ),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFF6F8FB),
                                            borderRadius: BorderRadius.circular(
                                              10,
                                            ),
                                            border: Border.all(
                                              color: const Color(0xFFE1E6ED),
                                            ),
                                          ),
                                          child: DropdownButton<int>(
                                            value: _selectedYear,
                                            isExpanded: true,
                                            underline: const SizedBox(),
                                            icon: const Icon(
                                              Icons.keyboard_arrow_down,
                                              color: Color(0xFF757575),
                                              size: 16,
                                            ),
                                            items: [
                                              2026,
                                              2027,
                                              2028,
                                              2029,
                                              2030
                                            ]
                                                .map(
                                                  (y) => DropdownMenuItem(
                                                    value: y,
                                                    child: Text(
                                                      y.toString(),
                                                      style: const TextStyle(
                                                        fontSize: 12,
                                                        color: Color(
                                                          0xFF424242,
                                                        ),
                                                        fontWeight:
                                                            FontWeight.w500,
                                                      ),
                                                    ),
                                                  ),
                                                )
                                                .toList(),
                                            onChanged: (v) => setState(() {
                                              _selectedYear = v!;
                                              _saveFinancialFilters();
                                              _loadRecords();
                                            }),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Tipo',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: Color(0xFF757575),
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF6F8FB),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: const Color(0xFFE1E6ED),
                                      ),
                                    ),
                                    child: DropdownButton<String>(
                                      value: _selectedType,
                                      isExpanded: true,
                                      underline: const SizedBox(),
                                      icon: const Icon(
                                        Icons.keyboard_arrow_down,
                                        color: Color(0xFF757575),
                                        size: 16,
                                      ),
                                      items: const [
                                        DropdownMenuItem(
                                          value: 'all',
                                          child: Text(
                                            'Todos',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Color(0xFF424242),
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ),
                                        DropdownMenuItem(
                                          value: 'monthly',
                                          child: Text(
                                            'Mensalidade',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Color(0xFF424242),
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ),
                                        DropdownMenuItem(
                                          value: 'games',
                                          child: Text(
                                            'Jogos',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Color(0xFF424242),
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ),
                                        DropdownMenuItem(
                                          value: 'maintenance',
                                          child: Text(
                                            'Manutenção',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Color(0xFF424242),
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ),
                                        DropdownMenuItem(
                                          value: 'other',
                                          child: Text(
                                            'Outros',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Color(0xFF424242),
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ),
                                      ],
                                      onChanged: (v) => setState(() {
                                        _selectedType = v!;
                                        _saveFinancialFilters();
                                        _loadRecords();
                                      }),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Atleta',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: Color(0xFF757575),
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF6F8FB),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: const Color(0xFFE1E6ED),
                                      ),
                                    ),
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(10),
                                      onTap: _showAthleteFilterPicker,
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 12,
                                        ),
                                        child: Row(
                                          children: [
                                            const Icon(
                                              Icons.search,
                                              color: Color(0xFF757575),
                                              size: 16,
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Text(
                                                _getSelectedAthleteFilterLabel(),
                                                style: const TextStyle(
                                                  fontSize: 12,
                                                  color: Color(0xFF424242),
                                                  fontWeight: FontWeight.w500,
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            const Icon(
                                              Icons.keyboard_arrow_down,
                                              color: Color(0xFF757575),
                                              size: 16,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: _isLoading
                        ? const Center(child: CircularProgressIndicator())
                        : _records.isEmpty
                            ? Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.receipt_long_outlined,
                                      size: 64,
                                      color: const Color(0xFFBDBDBD),
                                    ),
                                    const SizedBox(height: 16),
                                    Text(
                                      'Nenhum registro encontrado',
                                      style: TextStyle(
                                        color: const Color(0xFF757575),
                                        fontSize: 16,
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            : ListView.builder(
                                padding: const EdgeInsets.all(12),
                                itemCount: filteredRecords.length,
                                itemBuilder: (context, index) {
                                  final record = filteredRecords[index];
                                  final typeColor = _getTypeColor(record.type);
                                  final dueDate =
                                      '${record.day.toString().padLeft(2, '0')}/${record.month.toString().padLeft(2, '0')}/${record.year}';
                                  final isOverdue = _isOverdue(record);

                                  return Container(
                                    margin: const EdgeInsets.only(bottom: 8),
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: [
                                          Colors.white,
                                          const Color(0xFFFAFAFA),
                                        ],
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                      ),
                                      borderRadius: BorderRadius.circular(12),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.grey.withOpacity(0.1),
                                          spreadRadius: 1,
                                          blurRadius: 6,
                                          offset: const Offset(0, 2),
                                        ),
                                      ],
                                    ),
                                    child: Material(
                                      color: Colors.transparent,
                                      child: InkWell(
                                        onTap: () => _showRecordDetails(record),
                                        borderRadius: BorderRadius.circular(12),
                                        child: Padding(
                                          padding: const EdgeInsets.all(12),
                                          child: Row(
                                            children: [
                                              Container(
                                                width: 40,
                                                height: 40,
                                                decoration: BoxDecoration(
                                                  color: typeColor
                                                      .withOpacity(0.1),
                                                  borderRadius:
                                                      BorderRadius.circular(10),
                                                ),
                                                child: Icon(
                                                  _getTypeIcon(record.type),
                                                  color: typeColor,
                                                  size: 20,
                                                ),
                                              ),
                                              const SizedBox(width: 10),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      record.typeLabel,
                                                      style: const TextStyle(
                                                        fontWeight:
                                                            FontWeight.w600,
                                                        fontSize: 14,
                                                        color:
                                                            Color(0xFF2C3E5A),
                                                      ),
                                                    ),
                                                    const SizedBox(height: 2),
                                                    Row(
                                                      children: [
                                                        Expanded(
                                                          child: Text(
                                                            'Atleta: ${_getAthleteName(record.athleteId)}',
                                                            style:
                                                                const TextStyle(
                                                              color: Color(
                                                                0xFF757575,
                                                              ),
                                                              fontSize: 11,
                                                            ),
                                                            maxLines: 1,
                                                            overflow:
                                                                TextOverflow
                                                                    .ellipsis,
                                                          ),
                                                        ),
                                                        const SizedBox(
                                                            width: 6),
                                                        _buildAthleteScoreChip(
                                                          record.athleteId,
                                                          compact: true,
                                                        ),
                                                      ],
                                                    ),
                                                    Text(
                                                      'Vencimento: $dueDate',
                                                      style: TextStyle(
                                                        color: isOverdue
                                                            ? Colors.red
                                                            : const Color(
                                                                0xFF757575,
                                                              ),
                                                        fontSize: 10,
                                                        fontWeight: isOverdue
                                                            ? FontWeight.w600
                                                            : FontWeight.normal,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.end,
                                                children: [
                                                  Text(
                                                    'R\$ ${record.value.toStringAsFixed(2)}',
                                                    style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      fontSize: 14,
                                                      color: Color(0xFF2C3E5A),
                                                    ),
                                                  ),
                                                  if (record.receiptUrl !=
                                                      null) ...[
                                                    const SizedBox(height: 4),
                                                    Container(
                                                      padding: const EdgeInsets
                                                          .symmetric(
                                                        horizontal: 8,
                                                        vertical: 3,
                                                      ),
                                                      decoration: BoxDecoration(
                                                        color: Colors.blue
                                                            .withOpacity(0.1),
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(
                                                          20,
                                                        ),
                                                        border: Border.all(
                                                          color: Colors.blue
                                                              .withOpacity(
                                                                  0.25),
                                                        ),
                                                      ),
                                                      child: const Row(
                                                        mainAxisSize:
                                                            MainAxisSize.min,
                                                        children: [
                                                          Icon(
                                                            Icons.attach_file,
                                                            size: 11,
                                                            color: Colors.blue,
                                                          ),
                                                          SizedBox(width: 4),
                                                          Text(
                                                            'Comprovante',
                                                            style: TextStyle(
                                                              color:
                                                                  Colors.blue,
                                                              fontSize: 10,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w600,
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  ],
                                                  const SizedBox(height: 4),
                                                  _buildStatusBadge(
                                                    record.status,
                                                    isOverdue: isOverdue,
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
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
  }

  List<FinancialRecord> _getFilteredRecords() {
    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);

    return _records.where((record) {
      if (_selectedAthleteId != 'all' &&
          record.athleteId != _selectedAthleteId) {
        return false;
      }

      if (_onlyWithReceipt &&
          (record.receiptUrl == null || record.receiptUrl!.trim().isEmpty)) {
        return false;
      }

      if (!_recordMatchesCustomPeriod(record)) {
        return false;
      }

      if (_selectedStatus == 'all') return true;

      if (_selectedStatus == 'approved' || _selectedStatus == 'rejected') {
        return record.status == _selectedStatus;
      }

      if (_selectedStatus == 'pending') {
        if (record.status != 'pending') return false;
        final dueDate = DateTime(record.year, record.month, record.day);
        return !dueDate.isBefore(todayDate);
      }

      if (_selectedStatus == 'overdue') {
        if (record.status != 'pending') return false;
        final dueDate = DateTime(record.year, record.month, record.day);
        return dueDate.isBefore(todayDate);
      }

      return true;
    }).toList();
  }

  Widget _buildCompactCard(
    String label,
    int value,
    IconData icon,
    Color baseColor,
    double amount,
    bool isSelected, {
    bool large = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isSelected
              ? [baseColor, baseColor.withOpacity(0.7)]
              : [baseColor.withOpacity(0.08), baseColor.withOpacity(0.15)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isSelected ? baseColor : baseColor.withOpacity(0.2),
          width: isSelected ? 2 : 1,
        ),
        boxShadow: isSelected
            ? [
                BoxShadow(
                  color: baseColor.withOpacity(0.3),
                  spreadRadius: 1,
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ]
            : [],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: isSelected ? Colors.white : baseColor, size: 16),
          const SizedBox(height: 4),
          Text(
            value.toString(),
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: isSelected ? Colors.white : baseColor,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w600,
              color: isSelected ? Colors.white : baseColor.withOpacity(0.8),
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 3),
          Text(
            'R\$ ${amount.toStringAsFixed(0)}',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: isSelected ? Colors.white : baseColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTypeValueCard(
    String label,
    IconData icon,
    Color baseColor,
    double amount,
    bool isSelected,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
        decoration: BoxDecoration(
          gradient: isSelected
              ? LinearGradient(
                  colors: [baseColor, baseColor.withOpacity(0.7)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : LinearGradient(
                  colors: [
                    baseColor.withOpacity(0.05),
                    baseColor.withOpacity(0.1),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? baseColor : baseColor.withOpacity(0.2),
            width: isSelected ? 1.5 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: baseColor.withOpacity(0.3),
                    spreadRadius: 1,
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ]
              : [],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: isSelected ? Colors.white : baseColor, size: 18),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 9,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                color: isSelected ? Colors.white : baseColor,
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Text(
              'R\$ ${amount.toStringAsFixed(0)}',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: isSelected ? Colors.white : baseColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTypeButton(String type, String label, IconData icon) {
    final isSelected = _selectedType == type;
    final baseColor = _getTypeColor(type);
    final lightColor = baseColor.withOpacity(0.15);
    final mediumColor = baseColor.withOpacity(0.6);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () {
          setState(() {
            _selectedType = type;
            _saveFinancialFilters();
            _loadRecords();
          });
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
          decoration: BoxDecoration(
            gradient: isSelected
                ? LinearGradient(
                    colors: [baseColor, mediumColor],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  )
                : null,
            color: isSelected ? null : lightColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? baseColor : Colors.transparent,
              width: 1.5,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: baseColor.withOpacity(0.4),
                      spreadRadius: 2,
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ]
                : [],
          ),
          child: Column(
            children: [
              Icon(
                icon,
                color: isSelected ? Colors.white : baseColor,
                size: 22,
              ),
              const SizedBox(height: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                  color: isSelected ? Colors.white : baseColor,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showRecordDetails(FinancialRecord record) {
    final typeColor = _getTypeColor(record.type);
    final dueDate =
        '${record.day.toString().padLeft(2, '0')}/${record.month.toString().padLeft(2, '0')}/${record.year}';
    final isOverdue = _isOverdue(record);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => SafeArea(
        top: false,
        child: Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.88,
          ),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.white, Color(0xFFF8F9FA)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: SingleChildScrollView(
            padding: EdgeInsets.only(
              left: 24,
              right: 24,
              top: 12,
              bottom: MediaQuery.of(context).viewPadding.bottom + 24,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE0E0E0),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: typeColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Icon(
                        _getTypeIcon(record.type),
                        color: typeColor,
                        size: 30,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Tipo: ${record.typeLabel}',
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF2C3E5A),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Mês ${record.month}/${record.year}',
                            style: const TextStyle(
                              fontSize: 14,
                              color: Color(0xFF757575),
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.edit_outlined,
                        color: Color(0xFF2C3E5A),
                      ),
                      tooltip: 'Editar débito',
                      onPressed: () {
                        Navigator.pop(context);
                        _editRecord(record);
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, color: Colors.red),
                      tooltip: 'Excluir débito',
                      onPressed: () {
                        Navigator.pop(context);
                        _deleteRecord(record.id);
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.grey.withOpacity(0.1),
                        spreadRadius: 2,
                        blurRadius: 8,
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      _buildDetailRow(
                        icon: Icons.person,
                        label: 'Atleta',
                        value: _getAthleteName(record.athleteId),
                        valueColor: olympusBlue,
                        valueWeight: FontWeight.w600,
                      ),
                      const Divider(height: 32),
                      _buildDetailRow(
                        icon: Icons.attach_money,
                        label: 'Valor',
                        value: 'R\$ ${record.value.toStringAsFixed(2)}',
                        valueColor: olympusBlue,
                        valueWeight: FontWeight.bold,
                      ),
                      const Divider(height: 32),
                      _buildDetailRow(
                        icon: isOverdue
                            ? Icons.warning
                            : record.status == 'approved'
                                ? Icons.check_circle
                                : record.status == 'pending'
                                    ? Icons.schedule
                                    : Icons.cancel,
                        label: 'Status',
                        value: isOverdue ? 'Atrasado' : record.statusLabel,
                        valueColor: isOverdue
                            ? Colors.red
                            : record.status == 'approved'
                                ? Colors.green
                                : record.status == 'pending'
                                    ? Colors.orange
                                    : Colors.red,
                        valueWeight: FontWeight.w600,
                        iconColor: isOverdue
                            ? Colors.red
                            : record.status == 'approved'
                                ? Colors.green
                                : record.status == 'pending'
                                    ? Colors.orange
                                    : Colors.red,
                      ),
                      const Divider(height: 32),
                      _buildDetailRow(
                        icon: Icons.calendar_today,
                        label: 'Data vencimento',
                        value: dueDate,
                        valueColor:
                            isOverdue ? Colors.red : const Color(0xFF616161),
                        valueWeight:
                            isOverdue ? FontWeight.w600 : FontWeight.normal,
                      ),
                      const Divider(height: 32),
                      _buildDetailRow(
                        icon: Icons.calendar_today,
                        label: 'Mês/Ano',
                        value: '${record.month}/${record.year}',
                        valueColor: const Color(0xFF616161),
                      ),
                      if (record.description != null) ...[
                        const Divider(height: 32),
                        _buildDetailRow(
                          icon: Icons.description,
                          label: 'Descrição',
                          value: record.description!,
                          valueColor: const Color(0xFF616161),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () => _confirmAdminView(record.id),
                    icon: const Icon(Icons.visibility),
                    label: const Text('Confirmar visualização do Admin'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: olympusBlue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () =>
                        _showAthleteFinancialHistory(record.athleteId),
                    icon: const Icon(Icons.account_balance_wallet_rounded),
                    label: const Text('Histórico financeiro do atleta'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: olympusBlue,
                      side: BorderSide(color: olympusBlue),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                if (record.receiptUrl != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFE3F2FD), Color(0xFFBBDEFB)],
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                      ),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFF90CAF9)),
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.blue,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(
                                Icons.attach_file,
                                color: Colors.white,
                                size: 22,
                              ),
                            ),
                            const SizedBox(width: 12),
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Comprovante anexado pelo atleta',
                                    style: TextStyle(
                                      color: Color(0xFF1565C0),
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  Text(
                                    'Toque abaixo para visualizar o arquivo',
                                    style: TextStyle(
                                      color: Color(0xFF42A5F5),
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: () => _viewReceipt(record.receiptUrl!),
                            icon: const Icon(Icons.visibility),
                            label: const Text('Ver comprovante'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                if (record.status == 'pending') ...[
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        _editRecord(record);
                      },
                      icon: const Icon(Icons.edit_outlined),
                      label: const Text('Editar débito'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: olympusBlue,
                        side: BorderSide(color: olympusBlue),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () => _sendRecordChargeWhatsApp(record),
                      icon: const Icon(Icons.chat_rounded),
                      label: const Text('Cobrar no WhatsApp'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF25D366),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [Colors.green[600]!, Colors.green[400]!],
                              begin: Alignment.centerLeft,
                              end: Alignment.centerRight,
                            ),
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.green.withOpacity(0.3),
                                spreadRadius: 1,
                                blurRadius: 6,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: () async {
                                await _approvePayment(record.id);
                                if (mounted) {
                                  Navigator.pop(context);
                                }
                              },
                              borderRadius: BorderRadius.circular(12),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(
                                    Icons.check,
                                    color: Colors.white,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 8),
                                  const Text(
                                    'Aprovar',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [Colors.red[600]!, Colors.red[400]!],
                              begin: Alignment.centerLeft,
                              end: Alignment.centerRight,
                            ),
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.red.withOpacity(0.3),
                                spreadRadius: 1,
                                blurRadius: 6,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: () async {
                                await _rejectPayment(record.id);
                                if (mounted) {
                                  Navigator.pop(context);
                                }
                              },
                              borderRadius: BorderRadius.circular(12),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(
                                    Icons.close,
                                    color: Colors.white,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 8),
                                  const Text(
                                    'Rejeitar',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ] else if (record.status != 'pending') ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.grey[300]!),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          record.status == 'approved'
                              ? Icons.check_circle
                              : Icons.cancel,
                          color: record.status == 'approved'
                              ? Colors.green
                              : Colors.red,
                          size: 24,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                record.status == 'approved'
                                    ? 'Pagamento Aprovado'
                                    : 'Pagamento Rejeitado',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 15,
                                  color: Colors.grey[800],
                                ),
                              ),
                              Text(
                                'Registro finalizado',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                        ),
                        ElevatedButton.icon(
                          onPressed: () {
                            Navigator.pop(context);
                            _editRecord(record);
                          },
                          icon: const Icon(Icons.edit, size: 18),
                          label: const Text('Editar'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: olympusBlue,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF25D366), Color(0xFF128C7E)],
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                          ),
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF25D366).withOpacity(0.3),
                              spreadRadius: 1,
                              blurRadius: 6,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () {
                              Navigator.pop(context);
                              _navigateToAthleteProfile(record);
                            },
                            borderRadius: BorderRadius.circular(12),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(
                                  Icons.person,
                                  color: Colors.white,
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                const Text(
                                  'Enviar Mensagem',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Color.lerp(olympusBlue, Colors.black, 0.18)!,
                              Color.lerp(olympusBlue, Colors.white, 0.22)!,
                            ],
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                          ),
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: olympusBlue.withOpacity(0.3),
                              spreadRadius: 1,
                              blurRadius: 6,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () => Navigator.pop(context),
                            borderRadius: BorderRadius.circular(12),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(
                                  Icons.close,
                                  color: Colors.white,
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                const Text(
                                  'Fechar',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow({
    required IconData icon,
    required String label,
    required String value,
    required Color valueColor,
    FontWeight valueWeight = FontWeight.normal,
    Color? iconColor,
  }) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: (iconColor ?? const Color(0xFF667eea)).withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            icon,
            size: 20,
            color: iconColor ?? const Color(0xFF667eea),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF757575),
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: TextStyle(
                  fontSize: 16,
                  color: valueColor,
                  fontWeight: valueWeight,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}

class CurrencyInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.isEmpty) {
      return newValue;
    }

    String text = newValue.text.replaceAll(RegExp(r'[^\d]'), '');

    int value = int.tryParse(text) ?? 0;

    String formatted = (value / 100).toStringAsFixed(2);
    formatted = formatted.replaceAll('.', ',');

    final parts = formatted.split(',');
    String integerPart = parts[0];
    String decimalPart = parts.length > 1 ? parts[1] : '00';

    integerPart = integerPart.replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (Match m) => '${m[1]}.',
    );

    final result = 'R\$ $integerPart,$decimalPart';

    return TextEditingValue(
      text: result,
      selection: TextSelection.collapsed(offset: result.length),
    );
  }
}

class _OverdueAthleteBlockSheet extends StatefulWidget {
  const _OverdueAthleteBlockSheet({
    required this.service,
    required this.enforcementEnabled,
  });

  final FinancialAccessService service;
  final bool enforcementEnabled;

  @override
  State<_OverdueAthleteBlockSheet> createState() =>
      _OverdueAthleteBlockSheetState();
}

class _OverdueAthleteBlockSheetState extends State<_OverdueAthleteBlockSheet> {
  final TextEditingController _searchController = TextEditingController();
  List<OverdueAthleteBlockCandidate> _athletes = const [];
  final Set<String> _savingAthleteIds = <String>{};
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
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final athletes = await widget.service.getOverdueAthleteBlockCandidates();
      if (!mounted) return;
      setState(() {
        _athletes = athletes;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Não foi possível carregar os inadimplentes.';
      });
    }
  }

  Future<void> _toggle(
    OverdueAthleteBlockCandidate athlete,
    bool blocked,
  ) async {
    if (athlete.isAdmin || _savingAthleteIds.contains(athlete.athleteId)) {
      return;
    }
    setState(() => _savingAthleteIds.add(athlete.athleteId));
    try {
      await widget.service.setAthleteTrainingBlocked(
        athleteId: athlete.athleteId,
        blocked: blocked,
      );
      if (!mounted) return;
      final index = _athletes.indexWhere(
        (item) => item.athleteId == athlete.athleteId,
      );
      if (index >= 0) {
        final updated = List<OverdueAthleteBlockCandidate>.from(_athletes);
        updated[index] = updated[index].copyWith(isBlocked: blocked);
        setState(() => _athletes = updated);
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            blocked
                ? '${athlete.fullName} foi bloqueado para treinos.'
                : 'Acesso de ${athlete.fullName} liberado.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Não foi possível alterar ${athlete.fullName}.'),
          backgroundColor: Colors.red.shade700,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _savingAthleteIds.remove(athlete.athleteId));
      }
    }
  }

  Widget _avatar(OverdueAthleteBlockCandidate athlete) {
    final initial = athlete.fullName.isEmpty
        ? 'A'
        : athlete.fullName.characters.first.toUpperCase();
    final fallback = Container(
      width: 46,
      height: 46,
      alignment: Alignment.center,
      color: const Color(0xFFE8EDF4),
      child: Text(
        initial,
        style: const TextStyle(
          color: Color(0xFF123463),
          fontWeight: FontWeight.w800,
        ),
      ),
    );
    final url = athlete.avatarUrl;
    if (url == null) return ClipOval(child: fallback);
    return ClipOval(
      child: CachedNetworkImage(
        imageUrl: url,
        width: 46,
        height: 46,
        fit: BoxFit.cover,
        memCacheWidth: 160,
        maxWidthDiskCache: 320,
        placeholder: (_, __) => fallback,
        errorWidget: (_, __, ___) => fallback,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final query = _searchController.text.trim().toLowerCase();
    final visible = query.isEmpty
        ? _athletes
        : _athletes
            .where(
              (athlete) => athlete.fullName.toLowerCase().contains(query),
            )
            .toList(growable: false);
    final blockedCount = _athletes.where((athlete) => athlete.isBlocked).length;
    final currency = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

    return FractionallySizedBox(
      heightFactor: 0.9,
      child: Material(
        color: const Color(0xFFF4F7FB),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 12, 10),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(9),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE2BB5B).withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.lock_person_rounded,
                      color: Color(0xFF123463),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Bloqueio de treinos',
                          style: TextStyle(
                            color: Color(0xFF123463),
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          '$blockedCount bloqueado(s) de ${_athletes.length} inadimplente(s)',
                          style: const TextStyle(
                            color: Color(0xFF62748A),
                            fontSize: 12,
                          ),
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
            ),
            if (!widget.enforcementEnabled)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                padding: const EdgeInsets.all(11),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF3CD),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE2BB5B)),
                ),
                child: const Text(
                  'A regra geral está desativada. As escolhas serão salvas, mas o bloqueio só terá efeito quando ela for ativada.',
                  style: TextStyle(
                    color: Color(0xFF6D5513),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: TextField(
                controller: _searchController,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: 'Buscar atleta...',
                  prefixIcon: const Icon(Icons.search_rounded),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.cloud_off_rounded, size: 42),
                                const SizedBox(height: 10),
                                Text(_error!, textAlign: TextAlign.center),
                                const SizedBox(height: 12),
                                FilledButton.icon(
                                  onPressed: _load,
                                  icon: const Icon(Icons.refresh_rounded),
                                  label: const Text('Tentar novamente'),
                                ),
                              ],
                            ),
                          ),
                        )
                      : visible.isEmpty
                          ? const Center(
                              child: Padding(
                                padding: EdgeInsets.all(24),
                                child: Text(
                                  'Nenhum atleta inadimplente encontrado.',
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            )
                          : RefreshIndicator(
                              onRefresh: _load,
                              child: ListView.separated(
                                padding:
                                    const EdgeInsets.fromLTRB(16, 0, 16, 24),
                                itemCount: visible.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(height: 8),
                                itemBuilder: (context, index) {
                                  final athlete = visible[index];
                                  final saving = _savingAthleteIds.contains(
                                    athlete.athleteId,
                                  );
                                  return Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: athlete.isBlocked
                                          ? const Color(0xFFFFECEC)
                                          : Colors.white,
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(
                                        color: athlete.isBlocked
                                            ? const Color(0xFFE99A9A)
                                            : const Color(0xFFE1E7EF),
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        _avatar(athlete),
                                        const SizedBox(width: 11),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                athlete.fullName,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  color: Color(0xFF123463),
                                                  fontWeight: FontWeight.w800,
                                                ),
                                              ),
                                              const SizedBox(height: 3),
                                              Text(
                                                athlete.isAdmin
                                                    ? 'Administrador — acesso protegido'
                                                    : '${athlete.overdueCount} vencida(s) • ${currency.format(athlete.overdueAmount)}',
                                                style: TextStyle(
                                                  color: athlete.isAdmin
                                                      ? const Color(0xFF8B6A10)
                                                      : const Color(0xFF6A7687),
                                                  fontSize: 12,
                                                  fontWeight: athlete.isAdmin
                                                      ? FontWeight.w700
                                                      : FontWeight.w500,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        if (saving)
                                          const SizedBox(
                                            width: 42,
                                            height: 42,
                                            child: Padding(
                                              padding: EdgeInsets.all(10),
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                              ),
                                            ),
                                          )
                                        else
                                          Switch.adaptive(
                                            value: athlete.isBlocked,
                                            onChanged: athlete.isAdmin
                                                ? null
                                                : (value) =>
                                                    _toggle(athlete, value),
                                            activeThumbColor:
                                                const Color(0xFFD32F2F),
                                          ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                            ),
            ),
          ],
        ),
      ),
    );
  }
}
