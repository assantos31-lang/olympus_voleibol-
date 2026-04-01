import 'package:flutter/material.dart';
import 'dart:ui';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import '../models/financial_record_model.dart';
import '../services/permission_service.dart';

class AthleteFinancialPage extends StatefulWidget {
  const AthleteFinancialPage({super.key});

  @override
  State<AthleteFinancialPage> createState() => _AthleteFinancialPageState();
}

class _AthleteFinancialPageState extends State<AthleteFinancialPage> {
  final _supabase = Supabase.instance.client;
  final _picker = ImagePicker();
  final PermissionService _permissionService = PermissionService();
  List<FinancialRecord> _records = [];
  bool _isLoading = true;
  int _selectedMonth = DateTime.now().month;
  int _selectedYear = DateTime.now().year;
  String _selectedType = 'all';
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
    _loadFinancialFilters();
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
    setState(() => _isLoading = true);
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
      final isPendingFinancialCard =
          record.status != 'approved' && record.receiptUrl == null;

      return isSelectedMonthYear || isPendingFinancialCard;
    }).toList();

    setState(() {
      _records = filteredRecords;
      _isLoading = false;
    });
    _calculateCounters();
  }

  // ✅ NOVO: Calcular contadores de atrasos e novos boletos
  void _calculateCounters() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    int overdue = 0;
    int newBills = 0;

    for (var record in _records) {
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
      final filePath = '${record.athleteId}/$fileName';
      final bytes = await image.readAsBytes();

      await _supabase.storage.from('receipts').uploadBinary(filePath, bytes,
          fileOptions: const FileOptions(upsert: true));

      await _supabase.from('financial_records').update({
        'receipt_url': filePath,
        'status': 'pending',
      }).eq('id', record.id);

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
    if (width > 900) return 4;
    if (width > 600) return 3;
    if (width > 350) return 2;
    return 1;
  }

  double _getChildAspectRatio(double width) {
    if (width > 900) return 1.08;
    if (width > 600) return 1.0;
    if (width > 350) return 0.98;
    return 1.12;
  }

  Widget _buildPremiumFinancialBackground() {
    return Stack(
      children: [
        Positioned.fill(
          child: Image.asset(
            'assets/images/monte_olimpo_v2.png',
            fit: BoxFit.cover,
            alignment: Alignment.center,
            errorBuilder: (context, error, stackTrace) {
              return Container(color: const Color(0xFF102845));
            },
          ),
        ),
        Positioned.fill(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 2, sigmaY: 2),
            child: Container(color: Colors.transparent),
          ),
        ),
        Positioned.fill(
          child: Container(
            color: Colors.black.withOpacity(0.08),
          ),
        ),
        Positioned.fill(
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  olympusBlue.withOpacity(0.40),
                  olympusLightBlue.withOpacity(0.18),
                  Colors.black.withOpacity(0.55),
                ],
              ),
            ),
          ),
        ),
        Positioned.fill(
          child: Container(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(0, -0.62),
                radius: 1.18,
                colors: [
                  olympusGold.withOpacity(0.10),
                  Colors.transparent,
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Financeiro',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 20,
          ),
        ),
        backgroundColor: olympusBlue,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadRecords,
          ),
        ],
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: _buildPremiumFinancialBackground(),
          ),
          Column(
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Color(0xFF1E3A5F),
                      Color(0xFF2C5F8D),
                    ],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                  borderRadius: BorderRadius.only(
                    bottomLeft: Radius.circular(16),
                    bottomRight: Radius.circular(16),
                  ),
                ),
                child: Column(
                  children: [
                    if (_overdueCount > 0 || _newBillsCount > 0)
                      Container(
                        padding: const EdgeInsets.all(10),
                        margin: const EdgeInsets.only(bottom: 10),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.95),
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.1),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            if (_overdueCount > 0)
                              Expanded(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: Colors.red.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                        color: Colors.red.withOpacity(0.3)),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(Icons.warning,
                                          color: Colors.red, size: 16),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            const Text(
                                              'Em Atraso',
                                              style: TextStyle(
                                                fontSize: 9,
                                                color: Colors.grey,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                            Text(
                                              '$_overdueCount ${_overdueCount == 1 ? "conta" : "contas"}',
                                              style: const TextStyle(
                                                fontSize: 13,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.red,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            if (_overdueCount > 0 && _newBillsCount > 0)
                              const SizedBox(width: 6),
                            if (_newBillsCount > 0)
                              Expanded(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: olympusGold.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                        color: olympusGold.withOpacity(0.3)),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(Icons.add_circle_outline,
                                          color: olympusGold, size: 16),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            const Text(
                                              'Novos Boletos',
                                              style: TextStyle(
                                                fontSize: 9,
                                                color: Colors.grey,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                            Text(
                                              '$_newBillsCount ${_newBillsCount == 1 ? "boleto" : "boletos"}',
                                              style: const TextStyle(
                                                fontSize: 13,
                                                fontWeight: FontWeight.bold,
                                                color: olympusBlue,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    Row(
                      children: [
                        Expanded(
                          child: _buildModernDropdown(
                            icon: Icons.calendar_month,
                            value: _selectedMonth,
                            items: List.generate(12, (i) => i + 1)
                                .map((m) => DropdownMenuItem(
                                      value: m,
                                      child: Text(
                                        DateFormat.MMMM('pt_BR')
                                            .format(DateTime(2024, m)),
                                        style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ))
                                .toList(),
                            onChanged: (v) => setState(() {
                              _selectedMonth = v!;
                              _loadRecords();
                            }),
                            label: 'Mês',
                            iconColor: olympusGold,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _buildModernDropdown(
                            icon: Icons.date_range,
                            value: _selectedYear,
                            items: List.generate(5, (i) => 2026 + i)
                                .map((y) => DropdownMenuItem(
                                      value: y,
                                      child: Text(
                                        y.toString(),
                                        style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ))
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
                    const SizedBox(height: 10),
                    _buildModernDropdown(
                      icon: Icons.category_outlined,
                      value: _selectedType,
                      items: [
                        const DropdownMenuItem(
                          value: 'all',
                          child: Text(
                            'Todos os Tipos',
                            style: TextStyle(fontWeight: FontWeight.w500),
                          ),
                        ),
                        if (_allowedTypes.contains('monthly'))
                          const DropdownMenuItem(
                            value: 'monthly',
                            child: Text(
                              'Mensalidade',
                              style: TextStyle(fontWeight: FontWeight.w500),
                            ),
                          ),
                        if (_allowedTypes.contains('games'))
                          const DropdownMenuItem(
                            value: 'games',
                            child: Text(
                              'Jogos',
                              style: TextStyle(fontWeight: FontWeight.w500),
                            ),
                          ),
                        if (_allowedTypes.contains('maintenance'))
                          const DropdownMenuItem(
                            value: 'maintenance',
                            child: Text(
                              'Manutenção',
                              style: TextStyle(fontWeight: FontWeight.w500),
                            ),
                          ),
                        if (_allowedTypes.contains('other'))
                          const DropdownMenuItem(
                            value: 'other',
                            child: Text(
                              'Outros',
                              style: TextStyle(fontWeight: FontWeight.w500),
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
                ),
              ),
              Expanded(
                child: _isLoading
                    ? const Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            CircularProgressIndicator(
                              valueColor:
                                  AlwaysStoppedAnimation<Color>(olympusGold),
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
                                color: Colors.white.withOpacity(0.10),
                                borderRadius: BorderRadius.circular(18),
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
                                    color: Colors.white70,
                                  ),
                                  const SizedBox(height: 16),
                                  const Text(
                                    'Nenhum registro encontrado',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ),
                            ),
                          )
                        : LayoutBuilder(
                            builder: (context, constraints) {
                              return GridView.builder(
                                padding: const EdgeInsets.all(14),
                                gridDelegate:
                                    SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount:
                                      _getCrossAxisCount(constraints.maxWidth),
                                  childAspectRatio: _getChildAspectRatio(
                                      constraints.maxWidth),
                                  crossAxisSpacing: 10,
                                  mainAxisSpacing: 10,
                                ),
                                itemCount: _records.length,
                                itemBuilder: (context, index) {
                                  final record = _records[index];
                                  final typeColor = _getTypeColor(record.type);
                                  final dueDate = _getDueDate(record);
                                  final statusText =
                                      _getStatusText(record.status, dueDate);
                                  final statusColor =
                                      _getStatusColor(record.status, dueDate);
                                  final formattedDueDate =
                                      DateFormat('dd/MM/yyyy').format(dueDate);
                                  final isOverdue = statusText == 'Atrasado';

                                  return Container(
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: [
                                          Colors.white,
                                          typeColor.withOpacity(0.05),
                                        ],
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                      ),
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(
                                        color: typeColor.withOpacity(0.3),
                                        width: 1.5,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: typeColor.withOpacity(0.1),
                                          spreadRadius: 1,
                                          blurRadius: 6,
                                          offset: const Offset(0, 3),
                                        ),
                                      ],
                                    ),
                                    child: Material(
                                      color: Colors.transparent,
                                      child: InkWell(
                                        onTap: () => _showRecordDetails(record),
                                        borderRadius: BorderRadius.circular(14),
                                        child: Padding(
                                          padding: const EdgeInsets.all(10),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                children: [
                                                  Container(
                                                    padding:
                                                        const EdgeInsets.all(7),
                                                    decoration: BoxDecoration(
                                                      gradient: LinearGradient(
                                                        colors: [
                                                          typeColor
                                                              .withOpacity(0.2),
                                                          typeColor
                                                              .withOpacity(0.1),
                                                        ],
                                                      ),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              7),
                                                    ),
                                                    child: Icon(
                                                      _getTypeIcon(record.type),
                                                      color: typeColor,
                                                      size: 18,
                                                    ),
                                                  ),
                                                  const Spacer(),
                                                  Container(
                                                    padding: const EdgeInsets
                                                        .symmetric(
                                                      horizontal: 7,
                                                      vertical: 3,
                                                    ),
                                                    decoration: BoxDecoration(
                                                      color: statusColor
                                                          .withOpacity(0.15),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              5),
                                                      border: Border.all(
                                                        color: statusColor,
                                                        width: 1.2,
                                                      ),
                                                    ),
                                                    child: Text(
                                                      statusText,
                                                      style: TextStyle(
                                                        color: statusColor,
                                                        fontSize: 9,
                                                        fontWeight:
                                                            FontWeight.w700,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 8),
                                              Text(
                                                'R\$ ${record.value.toStringAsFixed(2)}',
                                                style: TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 20,
                                                  color: typeColor,
                                                ),
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                record.typeLabel,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w600,
                                                  fontSize: 13,
                                                  color: Color(0xFF2C3E5A),
                                                ),
                                              ),
                                              const SizedBox(height: 8),
                                              Container(
                                                width: double.infinity,
                                                padding:
                                                    const EdgeInsets.all(7),
                                                decoration: BoxDecoration(
                                                  color: isOverdue
                                                      ? Colors.red
                                                          .withOpacity(0.1)
                                                      : typeColor
                                                          .withOpacity(0.08),
                                                  borderRadius:
                                                      BorderRadius.circular(7),
                                                  border: Border.all(
                                                    color: isOverdue
                                                        ? Colors.red
                                                            .withOpacity(0.3)
                                                        : typeColor
                                                            .withOpacity(0.2),
                                                    width: 1.2,
                                                  ),
                                                ),
                                                child: Row(
                                                  children: [
                                                    Icon(
                                                      Icons.calendar_today,
                                                      size: 14,
                                                      color: isOverdue
                                                          ? Colors.red
                                                          : typeColor,
                                                    ),
                                                    const SizedBox(width: 5),
                                                    Expanded(
                                                      child: Column(
                                                        crossAxisAlignment:
                                                            CrossAxisAlignment
                                                                .start,
                                                        children: [
                                                          Text(
                                                            'Vencimento',
                                                            style: TextStyle(
                                                              fontSize: 11,
                                                              color: Colors
                                                                  .grey[600],
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w600,
                                                            ),
                                                          ),
                                                          Text(
                                                            formattedDueDate,
                                                            style: TextStyle(
                                                              fontSize: 12,
                                                              color: isOverdue
                                                                  ? Colors
                                                                      .red[700]
                                                                  : typeColor,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .bold,
                                                            ),
                                                          ),
                                                        ],
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
                                  );
                                },
                              );
                            },
                          ),
              ),
            ],
          ),
        ],
      ),
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
                Icon(
                  icon,
                  size: 13,
                  color: iconColor,
                ),
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

  void _showRecordDetails(FinancialRecord record) {
    final typeColor = _getTypeColor(record.type);
    final dueDate = _getDueDate(record);
    final statusText = _getStatusText(record.status, dueDate);
    final statusColor = _getStatusColor(record.status, dueDate);
    final formattedDueDate = DateFormat('dd/MM/yyyy').format(dueDate);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
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
                        if (record.description != null) ...[
                          const Divider(height: 24),
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
                  if (record.status == 'pending' && record.receiptUrl == null)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            olympusBlue,
                            olympusLightBlue,
                          ],
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
                  else if (record.receiptUrl != null)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            const Color(0xFFE8F5E9),
                            const Color(0xFFC8E6C9)
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
                          Icon(Icons.chevron_right,
                              color: const Color(0xFF388E3C), size: 16),
                        ],
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
                            const Color(0xFFC8E6C9)
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
                          Icon(Icons.chevron_right,
                              color: const Color(0xFF388E3C), size: 16),
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
          child: Icon(
            icon,
            size: 18,
            color: iconColor ?? olympusBlue,
          ),
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
