import 'package:flutter/material.dart';
import '../theme/olympus_theme.dart';
import 'package:flutter/services.dart';
import 'dart:ui';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;
import '../models/financial_record_model.dart';
import '../services/permission_service.dart';
import '../services/olympus_memory_cache.dart';
import '../services/organization_storage_service.dart';

class AthleteFinancialPage extends StatefulWidget {
  const AthleteFinancialPage({
    super.key,
    this.financialRestrictionActive = false,
    this.overdueRestrictionCount = 0,
  });

  final bool financialRestrictionActive;
  final int overdueRestrictionCount;

  @override
  State<AthleteFinancialPage> createState() => _AthleteFinancialPageState();
}

class _AthleteFinancialPageState extends State<AthleteFinancialPage> {
  final _supabase = Supabase.instance.client;
  final _picker = ImagePicker();
  final PermissionService _permissionService = PermissionService();
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  bool _notificationsReady = false;
  final ScrollController _parallaxScrollController = ScrollController();
  double _parallaxOffset = 0;
  List<FinancialRecord> _records = [];
  List<FinancialRecord> _allRecords = [];
  bool _isLoading = true;
  bool _loadingRecords = false;
  int _selectedMonth = DateTime.now().month;
  int _selectedYear = DateTime.now().year;
  String _selectedType = 'all';
  String _quickFilter = 'all';
  bool _showAdvancedFilters = false;
  List<String> _allowedTypes = ['monthly', 'games', 'maintenance', 'other'];
  // ✅ Contadores
  int _overdueCount = 0;
  int _newBillsCount = 0;

  // Cores do logo Olympus Voleibol
  static const Color olympusBlue = Color(0xFF1E3A5F);
  static const Color olympusGold = Color(0xFFD4AF37);
  static const Color olympusLightBlue = Color(0xFF2C5F8D);

  @override
  void initState() {
    super.initState();
    _parallaxScrollController.addListener(_handleParallaxScroll);
    _initFinancialNotifications();
    _markFinancialAsViewed();
    _restoreAthleteFinancialCache();
    _loadFinancialFilters();
  }

  String get _financialCacheKey =>
      'athlete_financial:${_supabase.auth.currentUser?.id ?? 'guest'}';

  void _restoreAthleteFinancialCache() {
    final cached = OlympusMemoryCache.read<Map<String, dynamic>>(
      _financialCacheKey,
    );
    if (cached == null) return;
    final all =
        (cached['all'] as List?)?.whereType<FinancialRecord>().toList() ??
            <FinancialRecord>[];
    final visible =
        (cached['visible'] as List?)?.whereType<FinancialRecord>().toList() ??
            <FinancialRecord>[];
    if (all.isEmpty) return;
    setState(() {
      _allRecords = all;
      _records = visible;
      _isLoading = false;
    });
    _calculateCounters();
  }

  void _saveAthleteFinancialCache() {
    OlympusMemoryCache.write<Map<String, dynamic>>(_financialCacheKey, {
      'all': List<FinancialRecord>.from(_allRecords),
      'visible': List<FinancialRecord>.from(_records),
    });
  }

  void _handleParallaxScroll() {
    if (!_parallaxScrollController.hasClients) return;
    final nextOffset = _parallaxScrollController.offset;

    if ((nextOffset - _parallaxOffset).abs() < 2) return;

    if (mounted) {
      setState(() {
        _parallaxOffset = nextOffset;
      });
    }
  }

  @override
  void dispose() {
    _parallaxScrollController.removeListener(_handleParallaxScroll);
    _parallaxScrollController.dispose();
    super.dispose();
  }

  Future<void> _markFinancialAsViewed() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    try {
      final viewedAt = DateTime.now().toIso8601String();
      await _supabase.auth.updateUser(
        UserAttributes(
          data: {...?user.userMetadata, 'last_financial_viewed_at': viewedAt},
        ),
      );
    } catch (e) {
      debugPrint('Erro ao marcar financeiro como visualizado: $e');
    }
  }

  Future<void> _loadFinancialFilters() async {
    final user = _supabase.auth.currentUser;

    if (user == null) {
      await _loadRecords();
      return;
    }

    List<String> allowedTypes = ['monthly', 'games', 'maintenance', 'other'];

    try {
      final dynamic service = _permissionService;
      final filters = await service.getFinancialFilters(user.id);

      if (filters != null && filters['allowed_financial_types'] != null) {
        allowedTypes = List<String>.from(filters['allowed_financial_types']);
      }
    } catch (_) {
      try {
        final dynamic service = _permissionService;
        final filters = await service.getAgendaFilters(user.id);

        if (filters != null && filters['allowed_financial_types'] != null) {
          allowedTypes = List<String>.from(filters['allowed_financial_types']);
        }
      } catch (_) {
        // Mantém o fallback padrão
      }
    }

    if (!mounted) return;

    setState(() {
      _allowedTypes = allowedTypes;

      if (_selectedType != 'all' && !_allowedTypes.contains(_selectedType)) {
        _selectedType = _allowedTypes.isNotEmpty ? _allowedTypes.first : 'all';
      }
    });

    await _loadRecords();
  }

  Future<void> _loadRecords() async {
    if (_loadingRecords) return;
    _loadingRecords = true;
    setState(() => _isLoading = _records.isEmpty);
    try {
      final currentUserId = _supabase.auth.currentUser!.id;

      var query = _supabase
          .from('financial_records')
          .select()
          .eq('athlete_id', currentUserId);

      if (_selectedType == 'all') {
        query = query.inFilter('type', _allowedTypes);
      } else {
        query = query.eq('type', _selectedType);
      }

      final response = await query.order('created_at', ascending: false);

      final allAllowedRecords =
          (response as List).map((r) => FinancialRecord.fromMap(r)).toList();

      final filteredRecords = allAllowedRecords.where((record) {
        final isSelectedMonthYear =
            record.month == _selectedMonth && record.year == _selectedYear;

        final dueDate = _getDueDate(record);
        final now = DateTime.now();
        final todayOnly = DateTime(now.year, now.month, now.day);
        final dueDateOnly = DateTime(dueDate.year, dueDate.month, dueDate.day);
        final isApproved = record.status == 'approved';
        final isOverdue = !isApproved && todayOnly.isAfter(dueDateOnly);
        final isPending = record.status == 'pending' && !isOverdue;

        final matchesBase = isSelectedMonthYear || isOverdue;
        if (!matchesBase) return false;

        if (_quickFilter == 'overdue') return isOverdue;
        if (_quickFilter == 'pending') return isPending;
        if (_quickFilter == 'paid') return isApproved;
        return true;
      }).toList();

      if (!mounted) return;
      setState(() {
        _allRecords = allAllowedRecords;
        _records = filteredRecords;
        _isLoading = false;
      });
      _calculateCounters();
      _saveAthleteFinancialCache();
      await _scheduleFinancialNotifications();
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _records.isEmpty
                ? 'Erro ao carregar financeiro: $e'
                : 'Não foi possível atualizar. Dados anteriores mantidos.',
          ),
        ),
      );
    } finally {
      _loadingRecords = false;
    }
  }

  // ✅ NOVO: Calcular contadores de atrasos e novos boletos
  void _calculateCounters() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    int overdue = 0;
    int newBills = 0;

    for (var record in _allRecords) {
      if (record.status == 'approved') {
        // Não conta pagos
        continue;
      }

      final day = (record as dynamic).day ?? 10;
      final dueDate = DateTime(record.year, record.month, day);
      final dueDateOnly = DateTime(dueDate.year, dueDate.month, dueDate.day);

      if (today.isAfter(dueDateOnly)) {
        overdue++;
      } else {
        newBills++;
      }
    }

    setState(() {
      _overdueCount = overdue;
      _newBillsCount = newBills;
    });
  }

  Future<void> _initFinancialNotifications() async {
    try {
      tz_data.initializeTimeZones();

      const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
      const iosInit = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );

      const initSettings = InitializationSettings(
        android: androidInit,
        iOS: iosInit,
      );

      await _localNotifications.initialize(initSettings);

      final androidPlugin =
          _localNotifications.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      await androidPlugin?.requestNotificationsPermission();

      final iosPlugin =
          _localNotifications.resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>();
      await iosPlugin?.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );

      _notificationsReady = true;
      await _scheduleFinancialNotifications();
    } catch (e) {
      debugPrint('Erro ao inicializar notificações financeiras: $e');
    }
  }

  NotificationDetails _financialNotificationDetails({required bool isOverdue}) {
    final androidDetails = AndroidNotificationDetails(
      'financial_due_notifications',
      'Financeiro',
      channelDescription:
          'Lembretes de vencimento, pendências e atrasos financeiros.',
      importance: Importance.high,
      priority: Priority.high,
      color: isOverdue ? Colors.red : olympusGold,
      icon: '@mipmap/ic_launcher',
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    return NotificationDetails(android: androidDetails, iOS: iosDetails);
  }

  bool _hasReceipt(FinancialRecord record) {
    final receiptUrl = record.receiptUrl;
    return receiptUrl != null && receiptUrl.trim().isNotEmpty;
  }

  bool _shouldNotifyRecord(FinancialRecord record) {
    if (record.status == 'approved') return false;

    // Se o atleta já anexou comprovante, não cobrar novamente.
    if (record.status == 'pending' && _hasReceipt(record)) return false;

    return true;
  }

  int _notificationIdFor(FinancialRecord record, String kind) {
    final raw = '${record.id}-$kind'.hashCode;
    return raw.abs() % 2147483647;
  }

  tz.TZDateTime _nextValidSchedule(DateTime dateTime) {
    final scheduled = tz.TZDateTime.from(dateTime, tz.local);
    final now = tz.TZDateTime.now(tz.local);

    if (scheduled.isAfter(now)) {
      return scheduled;
    }

    return now.add(const Duration(seconds: 8));
  }

  Future<void> _scheduleFinancialNotifications() async {
    if (!_notificationsReady || _allRecords.isEmpty) return;

    try {
      for (final record in _allRecords) {
        await _cancelFinancialNotificationsForRecord(record);

        if (!_shouldNotifyRecord(record)) continue;

        final dueDate = _getDueDate(record);
        final now = DateTime.now();
        final todayOnly = DateTime(now.year, now.month, now.day);
        final dueOnly = DateTime(dueDate.year, dueDate.month, dueDate.day);

        final typeLabel = record.typeLabel;
        final value = _formatMoney(record.value);
        final formattedDueDate = DateFormat('dd/MM/yyyy').format(dueDate);

        final beforeDue = DateTime(
          dueDate.year,
          dueDate.month,
          dueDate.day,
          9,
          0,
        ).subtract(const Duration(days: 2));

        final dueDay = DateTime(dueDate.year, dueDate.month, dueDate.day, 9, 0);

        final overdueDay = DateTime(
          dueDate.year,
          dueDate.month,
          dueDate.day,
          9,
          0,
        ).add(const Duration(days: 1));

        if (todayOnly.isBefore(dueOnly.subtract(const Duration(days: 1))) ||
            todayOnly.isAtSameMomentAs(
              dueOnly.subtract(const Duration(days: 2)),
            )) {
          await _localNotifications.zonedSchedule(
            _notificationIdFor(record, 'before'),
            'Pagamento próximo do vencimento',
            '$typeLabel de $value vence em $formattedDueDate.',
            _nextValidSchedule(beforeDue),
            _financialNotificationDetails(isOverdue: false),
            androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
            uiLocalNotificationDateInterpretation:
                UILocalNotificationDateInterpretation.absoluteTime,
            payload: record.id,
          );
        }

        if (todayOnly.isBefore(dueOnly) ||
            todayOnly.isAtSameMomentAs(dueOnly)) {
          await _localNotifications.zonedSchedule(
            _notificationIdFor(record, 'due'),
            'Pagamento vence hoje',
            '$typeLabel de $value vence hoje. Anexe o comprovante após pagar.',
            _nextValidSchedule(dueDay),
            _financialNotificationDetails(isOverdue: false),
            androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
            uiLocalNotificationDateInterpretation:
                UILocalNotificationDateInterpretation.absoluteTime,
            payload: record.id,
          );
        }

        if (todayOnly.isAfter(dueOnly) ||
            todayOnly.isAtSameMomentAs(dueOnly.add(const Duration(days: 1)))) {
          await _localNotifications.zonedSchedule(
            _notificationIdFor(record, 'overdue'),
            'Pagamento em atraso',
            '$typeLabel de $value venceu em $formattedDueDate.',
            _nextValidSchedule(overdueDay),
            _financialNotificationDetails(isOverdue: true),
            androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
            uiLocalNotificationDateInterpretation:
                UILocalNotificationDateInterpretation.absoluteTime,
            matchDateTimeComponents: DateTimeComponents.time,
            payload: record.id,
          );
        }
      }
    } catch (e) {
      debugPrint('Erro ao agendar notificações financeiras: $e');
    }
  }

  Future<void> _cancelFinancialNotificationsForRecord(
    FinancialRecord record,
  ) async {
    await _localNotifications.cancel(_notificationIdFor(record, 'before'));
    await _localNotifications.cancel(_notificationIdFor(record, 'due'));
    await _localNotifications.cancel(_notificationIdFor(record, 'overdue'));
  }

  Future<void> _notifyAdminsAboutReceipt({
    required FinancialRecord record,
  }) async {
    try {
      final rows = await _supabase
          .from('profiles')
          .select('id')
          .eq('user_type', 'admin');

      final adminIds = List<Map<String, dynamic>>.from(rows)
          .map((row) => row['id']?.toString())
          .whereType<String>()
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList();

      if (adminIds.isEmpty) {
        debugPrint('Nenhum administrador encontrado para receber comprovante.');
        return;
      }

      await _supabase.functions.invoke(
        'send-push-notification',
        body: {
          'userIds': adminIds,
          'title': 'Novo comprovante anexado',
          'body':
              'Um atleta anexou um comprovante de pagamento. Revise no Financeiro.',
          'type': 'admin_receipt_attached',
          'recordId': record.id,
        },
      );
    } catch (e) {
      // O comprovante ja foi salvo; uma falha no push nao pode desfazer o envio.
      debugPrint('Erro ao notificar administradores sobre comprovante: $e');
    }
  }

  Future<void> _uploadReceipt(FinancialRecord record) async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 85,
      );

      if (image == null) return;

      final fileExt = image.name.split('.').last;
      final fileName =
          '${record.id}_${DateTime.now().millisecondsSinceEpoch}.$fileExt';
      final filePath = OrganizationStorageService.scopedPath(
        '${record.athleteId}/$fileName',
      );
      final bytes = await image.readAsBytes();

      await _supabase.storage.from('receipts').uploadBinary(
            filePath,
            bytes,
            fileOptions: const FileOptions(upsert: true),
          );

      await _supabase.from('financial_records').update(
          {'receipt_url': filePath, 'status': 'pending'}).eq('id', record.id);

      await _notifyAdminsAboutReceipt(record: record);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Comprovante enviado! Aguarde aprovação.'),
            backgroundColor: Colors.green,
          ),
        );
        _loadRecords();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao enviar: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
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
    // Cores baseadas no logo Olympus (azul e dourado)
    switch (type) {
      case 'monthly':
        return olympusBlue;
      case 'games':
        return olympusGold;
      case 'maintenance':
        return olympusLightBlue;
      case 'other':
        return const Color(0xFF4A90A4);
      default:
        return olympusBlue;
    }
  }

  // 1 - Get due date from database (day, month, year)
  DateTime _getDueDate(FinancialRecord record) {
    // Access day field directly from the record
    int day = 10; // default fallback

    // Try to access day dynamically from the map
    try {
      // Access the day field if it exists
      day = (record as dynamic).day ?? 10;
    } catch (e) {
      // Use default day if field doesn't exist
    }

    return DateTime(record.year, record.month, day);
  }

  // 2 - Get status text based on approval and due date
  String _getStatusText(String status, DateTime dueDate) {
    if (status == 'approved') {
      return 'Pago';
    } else if (status == 'pending') {
      final now = DateTime.now();
      // Compare only date parts (ignore time)
      final dueDateOnly = DateTime(dueDate.year, dueDate.month, dueDate.day);
      final todayOnly = DateTime(now.year, now.month, now.day);

      if (todayOnly.isAfter(dueDateOnly)) {
        return 'Atrasado';
      } else {
        return 'Pendente';
      }
    } else if (status == 'rejected') {
      return 'Rejeitado';
    }

    return status;
  }

  // Get status color based on status and due date
  Color _getStatusColor(String status, DateTime dueDate) {
    if (status == 'approved') {
      return Colors.green;
    } else if (status == 'pending') {
      final now = DateTime.now();
      final dueDateOnly = DateTime(dueDate.year, dueDate.month, dueDate.day);
      final todayOnly = DateTime(now.year, now.month, now.day);

      if (todayOnly.isAfter(dueDateOnly)) {
        return Colors.red;
      } else {
        return Colors.orange;
      }
    } else if (status == 'rejected') {
      return Colors.red;
    }

    return Colors.grey;
  }

  int _getCrossAxisCount(double width) {
    if (width >= 1100) return 4;
    if (width >= 760) return 3;
    return 2;
  }

  double _getChildAspectRatio(double width) {
    if (width >= 1100) return 1.08;
    if (width >= 760) return 0.98;
    if (width >= 390) return 0.73;
    return 0.66;
  }

  Widget _buildPremiumFinancialBackground() {
    final parallaxY = -(_parallaxOffset * 0.10).clamp(0.0, 90.0);

    return Stack(
      fit: StackFit.expand,
      children: [
        Transform.translate(
          offset: Offset(0, parallaxY),
          child: Transform.scale(
            scale: 1.10,
            child: OlympusBrandBackgroundImage(
              fit: BoxFit.cover,
              alignment: Alignment.center,
              errorBuilder: (context, error, stackTrace) {
                return Container(color: const Color(0xFFF4F7FB));
              },
            ),
          ),
        ),
        BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 0.55, sigmaY: 0.55),
          child: Container(color: Colors.transparent),
        ),
        Container(color: const Color(0xFF07182B).withOpacity(0.50)),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                olympusBlue.withOpacity(0.16),
                Colors.transparent,
                Colors.black.withOpacity(0.22),
              ],
            ),
          ),
        ),
        IgnorePointer(
          child: Align(
            alignment: Alignment.topCenter,
            child: Container(
              height: 180,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [olympusBlue.withOpacity(0.34), Colors.transparent],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildGlassPanel({
    required Widget child,
    EdgeInsetsGeometry padding = const EdgeInsets.all(12),
    double radius = 18,
    Color? borderColor,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.88),
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(
              color: borderColor ?? Colors.white.withOpacity(0.48),
              width: 1.1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.14),
                blurRadius: 20,
                offset: const Offset(0, 9),
              ),
              BoxShadow(
                color: olympusGold.withOpacity(0.06),
                blurRadius: 18,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }

  double _getPaidTotalForSelectedMonth() {
    return _allRecords
        .where(
          (record) =>
              record.year == _selectedYear &&
              record.month == _selectedMonth &&
              record.status == 'approved',
        )
        .fold<double>(0, (sum, record) => sum + record.value);
  }

  double _getOpenTotal() {
    return _allRecords
        .where((record) => record.status != 'approved')
        .fold<double>(0, (sum, record) => sum + record.value);
  }

  double _getOverdueTotal() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return _allRecords.where((record) {
      if (record.status == 'approved') return false;
      final dueDate = _getDueDate(record);
      final dueOnly = DateTime(dueDate.year, dueDate.month, dueDate.day);
      return today.isAfter(dueOnly);
    }).fold<double>(0, (sum, record) => sum + record.value);
  }

  int _getPendingReceiptCount() {
    return _allRecords.where((record) {
      return record.status == 'pending' &&
          record.receiptUrl != null &&
          record.receiptUrl!.trim().isNotEmpty;
    }).length;
  }

  String _formatMoney(double value) => 'R\$ ${value.toStringAsFixed(2)}';

  String _getFinancialScoreLabel() {
    if (_overdueCount > 0) return 'Inadimplente';
    if (_newBillsCount > 0) return 'Atenção';
    return 'Em dia';
  }

  Color _getFinancialScoreColor() {
    if (_overdueCount > 0) return Colors.red;
    if (_newBillsCount > 0) return Colors.orange;
    return Colors.green;
  }

  IconData _getFinancialScoreIcon() {
    if (_overdueCount > 0) return Icons.warning_rounded;
    if (_newBillsCount > 0) return Icons.schedule_rounded;
    return Icons.verified_rounded;
  }

  String _getSmartInsight() {
    if (_overdueCount > 0) {
      return "Você tem $_overdueCount ${_overdueCount == 1 ? 'cobrança vencida' : 'cobranças vencidas'}. Regularize para voltar ao status em dia.";
    }
    if (_newBillsCount > 0) {
      return "Você tem $_newBillsCount ${_newBillsCount == 1 ? 'cobrança em aberto' : 'cobranças em aberto'} neste momento.";
    }
    final paidMonths = _allRecords
        .where((record) => record.status == 'approved')
        .map((record) => '${record.month}/${record.year}')
        .toSet()
        .length;
    if (paidMonths >= 3) {
      return 'Boa! Você já possui pagamentos aprovados em $paidMonths meses.';
    }
    return 'Tudo certo por aqui. Quando houver novas cobranças, elas aparecerão nesta tela.';
  }

  Widget _buildAthleteUpgradeHeader() {
    final paid = _getPaidTotalForSelectedMonth();
    final open = _getOpenTotal();
    final overdue = _getOverdueTotal();

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      child: Column(
        children: [
          _buildCompactFinancialSummary(paid, open, overdue),
          const SizedBox(height: 10),
          _buildSmartFilterToggle(),
          if (_showAdvancedFilters) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _buildModernDropdown(
                    icon: Icons.calendar_month,
                    value: _selectedMonth,
                    items: List.generate(12, (i) => i + 1)
                        .map(
                          (m) => DropdownMenuItem(
                            value: m,
                            child: Text(
                              DateFormat.MMMM(
                                'pt_BR',
                              ).format(DateTime(2024, m)),
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => setState(() {
                      _selectedMonth = v!;
                      _loadRecords();
                    }),
                    label: 'Mês',
                    iconColor: olympusGold,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildModernDropdown(
                    icon: Icons.date_range,
                    value: _selectedYear,
                    items: List.generate(5, (i) => 2026 + i)
                        .map(
                          (y) => DropdownMenuItem(
                            value: y,
                            child: Text(
                              y.toString(),
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => setState(() {
                      _selectedYear = v!;
                      _loadRecords();
                    }),
                    label: 'Ano',
                    iconColor: olympusGold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _buildModernDropdown(
              icon: Icons.category_outlined,
              value: _selectedType,
              items: [
                const DropdownMenuItem(
                  value: 'all',
                  child: Text(
                    'Todos os Tipos',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                if (_allowedTypes.contains('monthly'))
                  const DropdownMenuItem(
                    value: 'monthly',
                    child: Text(
                      'Mensalidade',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                if (_allowedTypes.contains('games'))
                  const DropdownMenuItem(
                    value: 'games',
                    child: Text(
                      'Jogos',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                if (_allowedTypes.contains('maintenance'))
                  const DropdownMenuItem(
                    value: 'maintenance',
                    child: Text(
                      'Manutenção',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                if (_allowedTypes.contains('other'))
                  const DropdownMenuItem(
                    value: 'other',
                    child: Text(
                      'Outros',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
              ],
              onChanged: (v) => setState(() {
                _selectedType = v!;
                _loadRecords();
              }),
              label: 'Tipo',
              iconColor: olympusGold,
            ),
          ],
          const SizedBox(height: 10),
          _buildQuickFilters(),
          const SizedBox(height: 10),
          _buildMiniFinancialChart(),
        ],
      ),
    );
  }

  Widget _buildSmartAlertCard(
    double open,
    double overdue,
    int pendingReceipts,
  ) {
    if (_overdueCount == 0 && _newBillsCount == 0 && pendingReceipts == 0) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Row(
          children: [
            const Icon(
              Icons.check_circle_rounded,
              color: Colors.greenAccent,
              size: 18,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Tudo certo por aqui.',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.86),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.10),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                _overdueCount > 0 ? Icons.warning_rounded : Icons.info_rounded,
                color: _overdueCount > 0 ? Colors.red : olympusGold,
                size: 20,
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Atenção no financeiro',
                  style: TextStyle(
                    color: olympusBlue,
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              TextButton(
                onPressed: () => setState(() {
                  _quickFilter = _overdueCount > 0 ? 'overdue' : 'pending';
                  _loadRecords();
                }),
                child: const Text('Ver agora'),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (_overdueCount > 0)
                _buildAlertPill(
                  Icons.warning_rounded,
                  '$_overdueCount em atraso',
                  Colors.red,
                ),
              if (open > 0)
                _buildAlertPill(
                  Icons.attach_money_rounded,
                  _formatMoney(open),
                  olympusBlue,
                ),
              if (pendingReceipts > 0)
                _buildAlertPill(
                  Icons.attach_file_rounded,
                  '$pendingReceipts comprovante(s)',
                  Colors.blue,
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAlertPill(IconData icon, String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 14),
          const SizedBox(width: 5),
          Text(
            text,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactFinancialSummary(
    double paid,
    double open,
    double overdue,
  ) {
    return _buildGlassPanel(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      radius: 18,
      child: Row(
        children: [
          _buildSummaryInlineItem(
            'Pago',
            _formatMoney(paid),
            Icons.check_circle_rounded,
            Colors.green,
          ),
          _buildSummaryDivider(),
          _buildSummaryInlineItem(
            'Aberto',
            _formatMoney(open),
            Icons.schedule_rounded,
            Colors.orange,
          ),
          _buildSummaryDivider(),
          _buildSummaryInlineItem(
            'Atrasado',
            _formatMoney(overdue),
            Icons.warning_rounded,
            Colors.red,
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryInlineItem(
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    return Expanded(
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 16),
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: color,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF5C6670),
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryDivider() {
    return Container(
      width: 1,
      height: 34,
      margin: const EdgeInsets.symmetric(horizontal: 7),
      color: const Color(0xFFE1E6ED),
    );
  }

  Widget _buildSmartFilterToggle() {
    final monthLabel = DateFormat.MMMM(
      'pt_BR',
    ).format(DateTime(2024, _selectedMonth));
    final typeLabel =
        _selectedType == 'all' ? 'Todos os tipos' : _typeLabel(_selectedType);

    return InkWell(
      onTap: () => setState(() => _showAdvancedFilters = !_showAdvancedFilters),
      borderRadius: BorderRadius.circular(20),
      child: _buildGlassPanel(
        radius: 18,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    olympusGold.withOpacity(0.28),
                    olympusGold.withOpacity(0.12),
                  ],
                ),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: olympusGold.withOpacity(0.28)),
              ),
              child: const Icon(
                Icons.tune_rounded,
                color: olympusBlue,
                size: 18,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Filtro inteligente',
                    style: TextStyle(
                      color: olympusBlue,
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$monthLabel $_selectedYear • $typeLabel',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF64748B),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              _showAdvancedFilters
                  ? Icons.keyboard_arrow_up_rounded
                  : Icons.keyboard_arrow_down_rounded,
              color: olympusBlue,
              size: 22,
            ),
          ],
        ),
      ),
    );
  }

  String _typeLabel(String type) {
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
        return 'Todos os tipos';
    }
  }

  Widget _buildCompactScoreAndInsightCard() {
    final scoreColor = _getFinancialScoreColor();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFDDE6F0)),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: scoreColor.withOpacity(0.18),
              border: Border.all(color: scoreColor.withOpacity(0.55)),
            ),
            child: Icon(_getFinancialScoreIcon(), color: scoreColor, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _getFinancialScoreLabel(),
                  style: TextStyle(
                    color: scoreColor,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _getSmartInsight(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.82),
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    height: 1.15,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScoreAndInsightCard() {
    final scoreColor = _getFinancialScoreColor();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE1E8F0)),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: scoreColor.withOpacity(0.18),
              border: Border.all(color: scoreColor.withOpacity(0.55)),
            ),
            child: Icon(_getFinancialScoreIcon(), color: scoreColor, size: 22),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _getFinancialScoreLabel(),
                  style: TextStyle(
                    color: scoreColor,
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  _getSmartInsight(),
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.82),
                    fontSize: 12,
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

  Widget _buildQuickFilters() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final itemWidth = (constraints.maxWidth - 24) / 4;
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            SizedBox(
              width: itemWidth,
              child: _buildQuickFilterChip(
                'all',
                'Todos',
                Icons.grid_view_rounded,
              ),
            ),
            SizedBox(
              width: itemWidth,
              child: _buildQuickFilterChip(
                'overdue',
                'Atrasados',
                Icons.warning_rounded,
              ),
            ),
            SizedBox(
              width: itemWidth,
              child: _buildQuickFilterChip(
                'pending',
                'Pendentes',
                Icons.schedule_rounded,
              ),
            ),
            SizedBox(
              width: itemWidth,
              child: _buildQuickFilterChip(
                'paid',
                'Pagos',
                Icons.check_circle_rounded,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildQuickFilterChip(String value, String label, IconData icon) {
    final selected = _quickFilter == value;
    return AnimatedScale(
      scale: selected ? 1.02 : 1,
      duration: const Duration(milliseconds: 160),
      child: InkWell(
        onTap: () => setState(() {
          _quickFilter = value;
          _loadRecords();
        }),
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 4),
          decoration: BoxDecoration(
            gradient: selected
                ? LinearGradient(
                    colors: [Color(0xFFD4AF37), Color(0xFFE7C75D)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  )
                : null,
            color: selected ? null : Colors.white.withOpacity(0.78),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected
                  ? olympusGold.withOpacity(0.70)
                  : Colors.white.withOpacity(0.58),
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: olympusGold.withOpacity(0.24),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ]
                : [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
          ),
          child: Column(
            children: [
              Icon(
                icon,
                color: selected ? olympusBlue : const Color(0xFF64748B),
                size: 15,
              ),
              const SizedBox(height: 3),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: selected ? olympusBlue : const Color(0xFF475569),
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMonthlyTimeline() {
    final recordsInYear =
        _allRecords.where((record) => record.year == _selectedYear).toList();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.10),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.timeline_rounded, color: olympusBlue, size: 18),
              SizedBox(width: 6),
              Text(
                'Linha do tempo do ano',
                style: TextStyle(
                  color: olympusBlue,
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: List.generate(12, (index) {
                final month = index + 1;
                final monthRecords = recordsInYear
                    .where((record) => record.month == month)
                    .toList();
                final status = _getMonthTimelineStatus(monthRecords);
                final color = status['color'] as Color;
                final icon = status['icon'] as IconData;
                final text = status['text'] as String;
                final label = DateFormat.MMM(
                  'pt_BR',
                ).format(DateTime(_selectedYear, month)).replaceAll('.', '');
                return Container(
                  width: 78,
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(
                    vertical: 10,
                    horizontal: 8,
                  ),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: color.withOpacity(0.25)),
                  ),
                  child: Column(
                    children: [
                      Icon(icon, color: color, size: 18),
                      const SizedBox(height: 5),
                      Text(
                        label,
                        style: const TextStyle(
                          color: olympusBlue,
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        text,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: color,
                          fontSize: 9.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }

  Map<String, dynamic> _getMonthTimelineStatus(List<FinancialRecord> records) {
    if (records.isEmpty) {
      return {
        'text': 'Sem débito',
        'color': Colors.grey,
        'icon': Icons.remove_circle_outline_rounded,
      };
    }
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final hasOverdue = records.any((record) {
      if (record.status == 'approved') return false;
      final dueDate = _getDueDate(record);
      return today.isAfter(DateTime(dueDate.year, dueDate.month, dueDate.day));
    });
    if (hasOverdue)
      return {
        'text': 'Atrasado',
        'color': Colors.red,
        'icon': Icons.cancel_rounded,
      };
    if (records.any((record) => record.status == 'pending'))
      return {
        'text': 'Pendente',
        'color': Colors.orange,
        'icon': Icons.schedule_rounded,
      };
    if (records.every((record) => record.status == 'approved'))
      return {
        'text': 'Pago',
        'color': Colors.green,
        'icon': Icons.check_circle_rounded,
      };
    if (records.any((record) => record.status == 'rejected'))
      return {
        'text': 'Rejeitado',
        'color': Colors.red,
        'icon': Icons.report_gmailerrorred_rounded,
      };
    return {
      'text': 'Aberto',
      'color': olympusBlue,
      'icon': Icons.receipt_long_rounded,
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Financeiro',
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 20),
        ),
        backgroundColor: olympusBlue.withOpacity(0.92),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadingRecords ? null : _loadRecords,
          ),
        ],
      ),
      body: Stack(
        children: [
          Positioned.fill(child: _buildPremiumFinancialBackground()),
          NestedScrollView(
            controller: _parallaxScrollController,
            physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics(),
            ),
            headerSliverBuilder: (context, innerBoxIsScrolled) => [
              SliverToBoxAdapter(
                child: Column(
                  children: [
                    if (widget.financialRestrictionActive)
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF3E0),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: const Color(0xFFE4B45B)),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(
                              Icons.lock_clock_rounded,
                              color: Color(0xFF9A5B00),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Participação em treinos temporariamente bloqueada',
                                    style: TextStyle(
                                      color: Color(0xFF5D3700),
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    widget.overdueRestrictionCount == 1
                                        ? 'Existe uma mensalidade vencida. Regularize o valor e aguarde a aprovação do administrador. Até lá, somente o Financeiro ficará disponível.'
                                        : 'Existem ${widget.overdueRestrictionCount} mensalidades vencidas. Regularize os valores e aguarde a aprovação do administrador. Até lá, somente o Financeiro ficará disponível.',
                                    style: const TextStyle(
                                      color: Color(0xFF6B4A1C),
                                      height: 1.35,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    _buildAthleteUpgradeHeader(),
                    if (_loadingRecords && _records.isNotEmpty)
                      const LinearProgressIndicator(
                        minHeight: 3,
                        color: olympusGold,
                      ),
                  ],
                ),
              ),
            ],
            body: _isLoading
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(
                          valueColor: AlwaysStoppedAnimation<Color>(
                            olympusGold,
                          ),
                        ),
                        SizedBox(height: 16),
                        Text(
                          'Carregando financeiro...',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  )
                : _records.isEmpty
                    ? Center(
                        child: Container(
                          margin: const EdgeInsets.all(20),
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.14),
                            ),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.receipt_long_outlined,
                                size: 64,
                                color: olympusBlue,
                              ),
                              const SizedBox(height: 16),
                              const Text(
                                'Nenhum registro encontrado',
                                style:
                                    TextStyle(color: olympusBlue, fontSize: 16),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      )
                    : LayoutBuilder(
                        builder: (context, constraints) {
                          return GridView.builder(
                            primary: true,
                            keyboardDismissBehavior:
                                ScrollViewKeyboardDismissBehavior.onDrag,
                            physics: const BouncingScrollPhysics(
                              parent: AlwaysScrollableScrollPhysics(),
                            ),
                            padding: EdgeInsets.fromLTRB(
                              10,
                              10,
                              10,
                              MediaQuery.of(context).viewPadding.bottom + 24,
                            ),
                            gridDelegate:
                                SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: _getCrossAxisCount(
                                constraints.maxWidth,
                              ),
                              childAspectRatio: _getChildAspectRatio(
                                constraints.maxWidth,
                              ),
                              crossAxisSpacing: 8,
                              mainAxisSpacing: 8,
                            ),
                            itemCount: _records.length,
                            itemBuilder: (context, index) {
                              final record = _records[index];
                              final typeColor = _getTypeColor(record.type);
                              final dueDate = _getDueDate(record);
                              final statusText = _getStatusText(
                                record.status,
                                dueDate,
                              );
                              final statusColor = _getStatusColor(
                                record.status,
                                dueDate,
                              );
                              final formattedDueDate = DateFormat(
                                'dd/MM/yyyy',
                              ).format(dueDate);
                              final isOverdue = statusText == 'Atrasado';

                              return ClipRRect(
                                borderRadius: BorderRadius.circular(20),
                                child: Container(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [
                                        Colors.white.withOpacity(0.94),
                                        Colors.white.withOpacity(0.86),
                                      ],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    ),
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                      color: Colors.white.withOpacity(0.38),
                                      width: 1.4,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.14),
                                        blurRadius: 18,
                                        offset: const Offset(0, 8),
                                      ),
                                      BoxShadow(
                                        color: typeColor.withOpacity(0.12),
                                        blurRadius: 10,
                                        spreadRadius: 0.4,
                                      ),
                                    ],
                                  ),
                                  child: Material(
                                    color: Colors.transparent,
                                    child: InkWell(
                                      onTap: () => _showRecordDetails(record),
                                      borderRadius: BorderRadius.circular(20),
                                      child: Padding(
                                        padding: const EdgeInsets.fromLTRB(
                                          10,
                                          10,
                                          10,
                                          14,
                                        ),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Container(
                                                  padding:
                                                      const EdgeInsets.all(8),
                                                  decoration: BoxDecoration(
                                                    color:
                                                        typeColor.withOpacity(
                                                      0.12,
                                                    ),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            10),
                                                    border: Border.all(
                                                      color:
                                                          typeColor.withOpacity(
                                                        0.18,
                                                      ),
                                                    ),
                                                  ),
                                                  child: Icon(
                                                    _getTypeIcon(record.type),
                                                    color: typeColor,
                                                    size: 16,
                                                  ),
                                                ),
                                                const Spacer(),
                                                Container(
                                                  padding: const EdgeInsets
                                                      .symmetric(
                                                    horizontal: 10,
                                                    vertical: 5,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    color: statusColor,
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            999),
                                                    boxShadow: [
                                                      BoxShadow(
                                                        color: statusColor
                                                            .withOpacity(0.22),
                                                        blurRadius: 6,
                                                        offset:
                                                            const Offset(0, 2),
                                                      ),
                                                    ],
                                                  ),
                                                  child: Text(
                                                    statusText,
                                                    style: const TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 10,
                                                      fontWeight:
                                                          FontWeight.w800,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 10),
                                            Text(
                                              'R\$ ${record.value.toStringAsFixed(2)}',
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w800,
                                                fontSize: 22,
                                                color: Color(0xFF1E3A5F),
                                                height: 1,
                                              ),
                                            ),
                                            const SizedBox(height: 6),
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                horizontal: 8,
                                                vertical: 5,
                                              ),
                                              decoration: BoxDecoration(
                                                color:
                                                    typeColor.withOpacity(0.10),
                                                borderRadius:
                                                    BorderRadius.circular(
                                                  10,
                                                ),
                                              ),
                                              child: Text(
                                                record.typeLabel,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  fontWeight: FontWeight.w700,
                                                  fontSize: 11,
                                                  color: typeColor,
                                                ),
                                              ),
                                            ),
                                            const Spacer(),
                                            Container(
                                              width: double.infinity,
                                              padding: const EdgeInsets.all(8),
                                              decoration: BoxDecoration(
                                                color: isOverdue
                                                    ? Colors.red
                                                        .withOpacity(0.10)
                                                    : const Color(0xFFF5F7FA),
                                                borderRadius:
                                                    BorderRadius.circular(
                                                  12,
                                                ),
                                                border: Border.all(
                                                  color: isOverdue
                                                      ? Colors.red
                                                          .withOpacity(0.28)
                                                      : const Color(0xFFD8E0EA),
                                                  width: 1.2,
                                                ),
                                              ),
                                              child: Row(
                                                children: [
                                                  Container(
                                                    width: 26,
                                                    height: 26,
                                                    decoration: BoxDecoration(
                                                      color: isOverdue
                                                          ? Colors.red
                                                              .withOpacity(
                                                              0.12,
                                                            )
                                                          : typeColor
                                                              .withOpacity(
                                                              0.12,
                                                            ),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              8),
                                                    ),
                                                    child: Icon(
                                                      Icons.calendar_today,
                                                      size: 13,
                                                      color: isOverdue
                                                          ? Colors.red
                                                          : typeColor,
                                                    ),
                                                  ),
                                                  const SizedBox(width: 8),
                                                  Expanded(
                                                    child: Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      children: [
                                                        Text(
                                                          'Vencimento',
                                                          style: TextStyle(
                                                            fontSize: 9,
                                                            color: Colors
                                                                .grey[600],
                                                            fontWeight:
                                                                FontWeight.w600,
                                                          ),
                                                        ),
                                                        const SizedBox(
                                                            height: 2),
                                                        Text(
                                                          formattedDueDate,
                                                          style: TextStyle(
                                                            fontSize: 12,
                                                            color: isOverdue
                                                                ? Colors
                                                                    .red[700]
                                                                : const Color(
                                                                    0xFF1E3A5F,
                                                                  ),
                                                            fontWeight:
                                                                FontWeight.w800,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            const SizedBox(height: 10),
                                            _buildRecordActionButtons(record),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildMiniFinancialChart() {
    final yearRecords =
        _allRecords.where((record) => record.year == _selectedYear).toList();

    final maxValue = List.generate(12, (index) {
      final month = index + 1;
      return yearRecords
          .where((record) => record.month == month)
          .fold<double>(0, (sum, record) => sum + record.value);
    }).fold<double>(0, (max, value) => value > max ? value : max);

    return _buildGlassPanel(
      radius: 20,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.bar_chart_rounded, color: olympusBlue, size: 18),
              SizedBox(width: 6),
              Text(
                'Evolução financeira',
                style: TextStyle(
                  color: olympusBlue,
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 118,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: List.generate(12, (index) {
                final month = index + 1;
                final monthRecords = yearRecords
                    .where((record) => record.month == month)
                    .toList();

                final paid = monthRecords
                    .where((record) => record.status == 'approved')
                    .fold<double>(0, (sum, record) => sum + record.value);

                final overdue = monthRecords.where((record) {
                  if (record.status == 'approved') return false;
                  final dueDate = _getDueDate(record);
                  final now = DateTime.now();
                  final today = DateTime(now.year, now.month, now.day);
                  return today.isAfter(
                    DateTime(dueDate.year, dueDate.month, dueDate.day),
                  );
                }).fold<double>(0, (sum, record) => sum + record.value);

                final pending = monthRecords.where((record) {
                  if (record.status == 'approved') return false;
                  final dueDate = _getDueDate(record);
                  final now = DateTime.now();
                  final today = DateTime(now.year, now.month, now.day);
                  return !today.isAfter(
                    DateTime(dueDate.year, dueDate.month, dueDate.day),
                  );
                }).fold<double>(0, (sum, record) => sum + record.value);

                final total = paid + pending + overdue;
                final totalHeight = maxValue == 0
                    ? 8.0
                    : (72 * (total / maxValue)).clamp(8.0, 72.0);

                double segmentHeight(double value) {
                  if (total <= 0) return 0;
                  return (totalHeight * (value / total)).clamp(
                    3.0,
                    totalHeight,
                  );
                }

                final label = DateFormat.MMM(
                  'pt_BR',
                ).format(DateTime(_selectedYear, month)).replaceAll('.', '');

                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        if (total > 0)
                          Text(
                            total.toStringAsFixed(0),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: olympusBlue,
                              fontSize: 8,
                              fontWeight: FontWeight.w900,
                            ),
                          )
                        else
                          const SizedBox(height: 10),
                        const SizedBox(height: 3),
                        Container(
                          width: 16,
                          height: total > 0 ? totalHeight : 8,
                          decoration: BoxDecoration(
                            color: total > 0
                                ? Colors.transparent
                                : Colors.grey.shade300,
                            borderRadius: BorderRadius.circular(999),
                            boxShadow: total > 0
                                ? [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.10),
                                      blurRadius: 8,
                                      offset: const Offset(0, 4),
                                    ),
                                  ]
                                : null,
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: total > 0
                              ? Column(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    if (overdue > 0)
                                      Container(
                                        height: segmentHeight(overdue),
                                        color: Colors.red,
                                      ),
                                    if (pending > 0)
                                      Container(
                                        height: segmentHeight(pending),
                                        color: Colors.orange,
                                      ),
                                    if (paid > 0)
                                      Container(
                                        height: segmentHeight(paid),
                                        color: Colors.green,
                                      ),
                                  ],
                                )
                              : const SizedBox.shrink(),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFF6B7280),
                            fontSize: 8,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _buildChartLegend('Pago', Colors.green),
              _buildChartLegend('Pendente', Colors.orange),
              _buildChartLegend('Atrasado', Colors.red),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildChartLegend(String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF5C6670),
            fontSize: 10,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  Widget _buildRecordActionButtons(FinancialRecord record) {
    final pixKey = _extractPixKey(record);
    final canUploadReceipt = record.status == 'pending' &&
        (record.receiptUrl == null || record.receiptUrl!.trim().isEmpty);

    if (record.status == 'approved') {
      return SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: pixKey == null
              ? null
              : () async {
                  HapticFeedback.selectionClick();
                  await Clipboard.setData(ClipboardData(text: pixKey));
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Chave Pix copiada!'),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                },
          icon: const Icon(Icons.pix, size: 15),
          label: Text(pixKey == null ? 'Sem Pix' : 'Copiar Pix'),
          style: OutlinedButton.styleFrom(
            foregroundColor: olympusBlue,
            side: BorderSide(color: olympusBlue.withOpacity(0.24)),
            backgroundColor: Colors.white.withOpacity(0.55),
            padding: const EdgeInsets.symmetric(vertical: 8),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            textStyle: const TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 11,
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: pixKey == null
                ? null
                : () async {
                    HapticFeedback.selectionClick();
                    await Clipboard.setData(ClipboardData(text: pixKey));
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Chave Pix copiada!'),
                          backgroundColor: Colors.green,
                        ),
                      );
                    }
                  },
            icon: const Icon(Icons.pix, size: 14),
            label: Text(pixKey == null ? 'Sem Pix' : 'Pix'),
            style: OutlinedButton.styleFrom(
              foregroundColor: olympusBlue,
              side: BorderSide(color: olympusBlue.withOpacity(0.24)),
              backgroundColor: Colors.white.withOpacity(0.55),
              padding: const EdgeInsets.symmetric(vertical: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              textStyle: const TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 11,
              ),
            ),
          ),
        ),
        if (canUploadReceipt) ...[
          const SizedBox(width: 8),
          Expanded(
            child: ElevatedButton.icon(
              onPressed: () {
                HapticFeedback.mediumImpact();
                _uploadReceipt(record);
              },
              icon: const Icon(Icons.upload_file_rounded, size: 14),
              label: const Text('Já paguei'),
              style: ElevatedButton.styleFrom(
                backgroundColor: olympusGold,
                foregroundColor: olympusBlue,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                textStyle: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 11,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildModernDropdown({
    required IconData icon,
    required dynamic value,
    required List<DropdownMenuItem<dynamic>> items,
    required ValueChanged<dynamic> onChanged,
    required String label,
    required Color iconColor,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            spreadRadius: 1,
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 3),
            child: Row(
              children: [
                Icon(icon, size: 13, color: iconColor),
                const SizedBox(width: 4),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 9,
                    color: iconColor.withOpacity(0.8),
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<dynamic>(
                value: value,
                isExpanded: true,
                items: items,
                onChanged: onChanged,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF2C3E5A),
                ),
                icon: Icon(
                  Icons.keyboard_arrow_down_rounded,
                  color: iconColor,
                  size: 16,
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
        ],
      ),
    );
  }

  Widget _buildStatusBadgeSmall(String status) {
    Color bgColor;
    IconData icon;

    switch (status) {
      case 'approved':
        bgColor = Colors.green;
        icon = Icons.check_circle;
        break;
      case 'pending':
        bgColor = Colors.orange;
        icon = Icons.schedule;
        break;
      case 'rejected':
        bgColor = Colors.red;
        icon = Icons.cancel;
        break;
      default:
        bgColor = Colors.grey;
        icon = Icons.help_outline;
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: bgColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: bgColor, width: 1),
      ),
      child: Icon(icon, size: 14, color: bgColor),
    );
  }

  Widget _buildStatusBadge(String status) {
    Color bgColor;
    Color textColor;
    IconData icon;

    switch (status) {
      case 'approved':
        bgColor = Colors.green;
        textColor = Colors.white;
        icon = Icons.check_circle;
        break;
      case 'pending':
        bgColor = Colors.orange;
        textColor = Colors.white;
        icon = Icons.schedule;
        break;
      case 'rejected':
        bgColor = Colors.red;
        textColor = Colors.white;
        icon = Icons.cancel;
        break;
      default:
        bgColor = Colors.grey;
        textColor = Colors.white;
        icon = Icons.help_outline;
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
            status == 'approved'
                ? 'Aprovado'
                : status == 'pending'
                    ? 'Pendente'
                    : 'Rejeitado',
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

  String? _extractPixKey(FinancialRecord record) {
    try {
      final dynamic value = (record as dynamic).pixKey;
      if (value != null && value.toString().trim().isNotEmpty) {
        return value.toString().trim();
      }
    } catch (_) {}

    try {
      final dynamic value = (record as dynamic).pix_key;
      if (value != null && value.toString().trim().isNotEmpty) {
        return value.toString().trim();
      }
    } catch (_) {}

    final description = record.description?.trim();
    if (description == null || description.isEmpty) return null;

    final match = RegExp(
      r'Chave Pix(?: \(([^)]+)\))?:\s*(.+)',
      caseSensitive: false,
    ).firstMatch(description);

    if (match == null) return null;

    final pixType = (match.group(1) ?? '').toLowerCase().trim();
    final rawKey = (match.group(2) ?? '').trim();

    if (pixType == 'cnpj' || pixType == 'cpf') {
      return rawKey.replaceAll(RegExp(r'\D'), '');
    }

    return rawKey;
  }

  bool _descriptionIsOnlyPix(FinancialRecord record) {
    final description = record.description?.trim();
    if (description == null || description.isEmpty) return false;
    return RegExp(
      r'^Chave Pix(?: \(([^)]+)\))?:\s*.+$',
      caseSensitive: false,
    ).hasMatch(description);
  }

  void _showRecordDetails(FinancialRecord record) {
    final typeColor = _getTypeColor(record.type);
    final dueDate = _getDueDate(record);
    final statusText = _getStatusText(record.status, dueDate);
    final statusColor = _getStatusColor(record.status, dueDate);
    final formattedDueDate = DateFormat('dd/MM/yyyy').format(dueDate);
    final pixKey = _extractPixKey(record);
    final showDescription = record.description != null &&
        record.description!.trim().isNotEmpty &&
        !_descriptionIsOnlyPix(record);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => SafeArea(
        top: false,
        child: Container(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewPadding.bottom + 12,
          ),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.white, Color(0xFFF8F9FA)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 10),
              Container(
                width: 35,
                height: 3,
                decoration: BoxDecoration(
                  color: Color(0xFFE0E0E0),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: Column(
                  children: [
                    // Header melhorado - INVERTIDO: Descrição à esquerda, X à direita
                    Row(
                      children: [
                        // Ícone do tipo e descrição à ESQUERDA
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                typeColor.withOpacity(0.2),
                                typeColor.withOpacity(0.1),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            _getTypeIcon(record.type),
                            color: typeColor,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                record.typeLabel,
                                style: const TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF2C3E5A),
                                ),
                              ),
                              const SizedBox(height: 2),
                              Row(
                                children: [
                                  Icon(
                                    Icons.calendar_today,
                                    size: 12,
                                    color: Colors.grey[600],
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    formattedDueDate,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        // Botão X à DIREITA
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.grey[100],
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: IconButton(
                            icon: const Icon(Icons.close, size: 20),
                            onPressed: () => Navigator.pop(context),
                            padding: const EdgeInsets.all(6),
                            constraints: const BoxConstraints(),
                            color: Colors.grey[700],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    // Card de detalhes
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.grey.withOpacity(0.1),
                            spreadRadius: 1,
                            blurRadius: 6,
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          _buildDetailRow(
                            icon: Icons.attach_money,
                            label: 'Valor',
                            value: 'R\$ ${record.value.toStringAsFixed(2)}',
                            valueColor: const Color(0xFF2C3E5A),
                            valueWeight: FontWeight.bold,
                          ),
                          const Divider(height: 24),
                          _buildDetailRow(
                            icon: record.status == 'approved'
                                ? Icons.check_circle
                                : record.status == 'pending'
                                    ? (DateTime.now().isAfter(dueDate)
                                        ? Icons.warning
                                        : Icons.schedule)
                                    : Icons.cancel,
                            label: 'Status',
                            value: statusText,
                            valueColor: statusColor,
                            valueWeight: FontWeight.w600,
                            iconColor: statusColor,
                          ),
                          const Divider(height: 24),
                          _buildDetailRow(
                            icon: Icons.event,
                            label: 'Data de Vencimento',
                            value: formattedDueDate,
                            valueColor: const Color(0xFF616161),
                          ),
                          if (showDescription) ...[
                            const Divider(height: 24),
                            _buildDetailRow(
                              icon: Icons.description,
                              label: 'Descrição',
                              value: record.description!.trim(),
                              valueColor: const Color(0xFF616161),
                            ),
                          ],
                          if (pixKey != null) ...[
                            const Divider(height: 24),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: olympusBlue.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: const Icon(
                                    Icons.pix,
                                    size: 18,
                                    color: olympusBlue,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Chave Pix',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Color(0xFF757575),
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        pixKey!,
                                        style: const TextStyle(
                                          fontSize: 15,
                                          color: Color(0xFF616161),
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Container(
                                  decoration: BoxDecoration(
                                    color: olympusBlue.withOpacity(0.08),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: IconButton(
                                    onPressed: () async {
                                      await Clipboard.setData(
                                        ClipboardData(text: pixKey!),
                                      );
                                      if (mounted) {
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          const SnackBar(
                                            content: Text('Chave Pix copiada!'),
                                            backgroundColor: Colors.green,
                                          ),
                                        );
                                      }
                                    },
                                    icon: const Icon(
                                      Icons.copy_rounded,
                                      color: olympusBlue,
                                      size: 20,
                                    ),
                                    tooltip: 'Copiar chave Pix',
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (record.receiptUrl != null)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              const Color(0xFFE8F5E9),
                              const Color(0xFFC8E6C9),
                            ],
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                          ),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFA5D6A7)),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(5),
                              decoration: BoxDecoration(
                                color: Colors.green,
                                borderRadius: BorderRadius.circular(5),
                              ),
                              child: const Icon(
                                Icons.check_circle,
                                color: Colors.white,
                                size: 16,
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Comprovante Enviado',
                                    style: TextStyle(
                                      color: Color(0xFF2E7D32),
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  Text(
                                    'Aguarde a aprovação',
                                    style: TextStyle(
                                      color: Color(0xFF43A047),
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Icon(
                              Icons.chevron_right,
                              color: const Color(0xFF388E3C),
                              size: 16,
                            ),
                          ],
                        ),
                      )
                    else if (record.status == 'pending' &&
                        record.receiptUrl == null)
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(top: 4),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [olympusBlue, olympusLightBlue],
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                          ),
                          borderRadius: BorderRadius.circular(10),
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
                            onTap: () => _uploadReceipt(record),
                            borderRadius: BorderRadius.circular(10),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(5),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.2),
                                      borderRadius: BorderRadius.circular(5),
                                    ),
                                    child: const Icon(
                                      Icons.camera_alt,
                                      color: Colors.white,
                                      size: 16,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  const Text(
                                    'Anexar Comprovante',
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
                      )
                    else if (record.status == 'approved')
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              const Color(0xFFE8F5E9),
                              const Color(0xFFC8E6C9),
                            ],
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                          ),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFA5D6A7)),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(5),
                              decoration: BoxDecoration(
                                color: Colors.green,
                                borderRadius: BorderRadius.circular(5),
                              ),
                              child: const Icon(
                                Icons.verified,
                                color: Colors.white,
                                size: 16,
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Pagamento Aprovado',
                                    style: TextStyle(
                                      color: Color(0xFF2E7D32),
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  Text(
                                    'Confirmado',
                                    style: TextStyle(
                                      color: Color(0xFF43A047),
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Icon(
                              Icons.chevron_right,
                              color: const Color(0xFF388E3C),
                              size: 16,
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 18),
                  ],
                ),
              ),
            ],
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
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: (iconColor ?? olympusBlue).withOpacity(0.1),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(icon, size: 18, color: iconColor ?? olympusBlue),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 11,
                  color: Color(0xFF757575),
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: TextStyle(
                  fontSize: 15,
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
