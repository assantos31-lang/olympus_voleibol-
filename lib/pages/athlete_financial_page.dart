import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import '../models/financial_record_model.dart';

class AthleteFinancialPage extends StatefulWidget {
  const AthleteFinancialPage({super.key});

  @override
  State<AthleteFinancialPage> createState() => _AthleteFinancialPageState();
}

class _AthleteFinancialPageState extends State<AthleteFinancialPage> {
  final _supabase = Supabase.instance.client;
  final _picker = ImagePicker();
  List<FinancialRecord> _records = [];
  bool _isLoading = true;
  int _selectedMonth = DateTime.now().month;
  int _selectedYear = DateTime.now().year;
  String _selectedType = 'all';

  // Cores do logo Olympus Voleibol
  static const Color olympusBlue = Color(0xFF1E3A5F);
  static const Color olympusGold = Color(0xFFD4AF37);
  static const Color olympusLightBlue = Color(0xFF2C5F8D);

  @override
  void initState() {
    super.initState();
    _loadRecords();
  }

  Future<void> _loadRecords() async {
    setState(() => _isLoading = true);
    final currentUserId = _supabase.auth.currentUser!.id;

    var query = _supabase
        .from('financial_records')
        .select()
        .eq('athlete_id', currentUserId)
        .eq('month', _selectedMonth)
        .eq('year', _selectedYear);

    if (_selectedType != 'all') {
      query = query.eq('type', _selectedType);
    }

    final response = await query.order('created_at', ascending: false);

    setState(() {
      _records =
          (response as List).map((r) => FinancialRecord.fromMap(r)).toList();
      _isLoading = false;
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
      body: Column(
        children: [
          // Modern Filter Section with Olympus Colors
          Container(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
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
                bottomLeft: Radius.circular(24),
                bottomRight: Radius.circular(24),
              ),
            ),
            child: Column(
              children: [
                // Month and Year Row
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
                                      fontSize: 14,
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
                    const SizedBox(width: 12),
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
                                      fontSize: 14,
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
                const SizedBox(height: 12),
                // Type Filter
                _buildModernDropdown(
                  icon: Icons.category_outlined,
                  value: _selectedType,
                  items: const [
                    DropdownMenuItem(
                        value: 'all',
                        child: Text(
                          'Todos os Tipos',
                          style: TextStyle(fontWeight: FontWeight.w500),
                        )),
                    DropdownMenuItem(
                        value: 'monthly',
                        child: Text(
                          'Mensalidade',
                          style: TextStyle(fontWeight: FontWeight.w500),
                        )),
                    DropdownMenuItem(
                        value: 'games',
                        child: Text(
                          'Jogos',
                          style: TextStyle(fontWeight: FontWeight.w500),
                        )),
                    DropdownMenuItem(
                        value: 'maintenance',
                        child: Text(
                          'Manutenção',
                          style: TextStyle(fontWeight: FontWeight.w500),
                        )),
                    DropdownMenuItem(
                        value: 'other',
                        child: Text(
                          'Outros',
                          style: TextStyle(fontWeight: FontWeight.w500),
                        )),
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
                    : LayoutBuilder(
                        builder: (context, constraints) {
                          return GridView.builder(
                            padding: const EdgeInsets.all(16),
                            gridDelegate:
                                SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount:
                                  _getCrossAxisCount(constraints.maxWidth),
                              childAspectRatio: 0.95,
                              crossAxisSpacing: 12,
                              mainAxisSpacing: 12,
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
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: typeColor.withOpacity(0.3),
                                    width: 1.5,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: typeColor.withOpacity(0.1),
                                      spreadRadius: 1,
                                      blurRadius: 8,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    onTap: () => _showRecordDetails(record),
                                    borderRadius: BorderRadius.circular(16),
                                    child: Padding(
                                      padding: const EdgeInsets.all(14),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Container(
                                                padding:
                                                    const EdgeInsets.all(10),
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
                                                      BorderRadius.circular(10),
                                                ),
                                                child: Icon(
                                                  _getTypeIcon(record.type),
                                                  color: typeColor,
                                                  size: 22,
                                                ),
                                              ),
                                              const Spacer(),
                                              // 2 - Status visible in card
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                  horizontal: 10,
                                                  vertical: 5,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: statusColor
                                                      .withOpacity(0.15),
                                                  borderRadius:
                                                      BorderRadius.circular(8),
                                                  border: Border.all(
                                                    color: statusColor,
                                                    width: 1.2,
                                                  ),
                                                ),
                                                child: Text(
                                                  statusText,
                                                  style: TextStyle(
                                                    color: statusColor,
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 14),
                                          Text(
                                            'R\$ ${record.value.toStringAsFixed(2)}',
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 24,
                                              color: typeColor,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            record.typeLabel,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w600,
                                              fontSize: 15,
                                              color: Color(0xFF2C3E5A),
                                            ),
                                          ),
                                          const Spacer(),
                                          // 4 - Show due date from database - MAIS VISÍVEL
                                          Container(
                                            width: double.infinity,
                                            padding: const EdgeInsets.all(10),
                                            decoration: BoxDecoration(
                                              color: isOverdue
                                                  ? Colors.red.withOpacity(0.1)
                                                  : typeColor.withOpacity(0.08),
                                              borderRadius:
                                                  BorderRadius.circular(10),
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
                                                  size: 18,
                                                  color: isOverdue
                                                      ? Colors.red
                                                      : typeColor,
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
                                                          fontSize: 10,
                                                          color:
                                                              Colors.grey[600],
                                                          fontWeight:
                                                              FontWeight.w500,
                                                        ),
                                                      ),
                                                      Text(
                                                        formattedDueDate,
                                                        style: TextStyle(
                                                          fontSize: 15,
                                                          color: isOverdue
                                                              ? Colors.red[700]
                                                              : typeColor,
                                                          fontWeight:
                                                              FontWeight.bold,
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
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            spreadRadius: 1,
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 16,
                  color: iconColor,
                ),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    color: iconColor.withOpacity(0.8),
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<dynamic>(
                value: value,
                isExpanded: true,
                items: items,
                onChanged: onChanged,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF2C3E5A),
                ),
                icon: Icon(
                  Icons.keyboard_arrow_down_rounded,
                  color: iconColor,
                  size: 20,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
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
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Color(0xFFE0E0E0),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                children: [
                  Row(
                    children: [
                      // 1 - Close button
                      IconButton(
                        icon: const Icon(Icons.close, size: 24),
                        onPressed: () => Navigator.pop(context),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        color: Colors.grey[700],
                      ),
                      const Spacer(),
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              typeColor.withOpacity(0.2),
                              typeColor.withOpacity(0.1),
                            ],
                          ),
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
                            // 4 - Show due date instead of month/year
                            Text(
                              'Vencimento: $formattedDueDate',
                              style: const TextStyle(
                                fontSize: 14,
                                color: Color(0xFF757575),
                              ),
                            ),
                          ],
                        ),
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
                          icon: Icons.attach_money,
                          label: 'Valor',
                          value: 'R\$ ${record.value.toStringAsFixed(2)}',
                          valueColor: const Color(0xFF2C3E5A),
                          valueWeight: FontWeight.bold,
                        ),
                        const Divider(height: 32),
                        _buildDetailRow(
                          // 3 - Show updated status in detail view
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
                        const Divider(height: 32),
                        // 4 - Changed from Mês/Ano to Data de Vencimento
                        _buildDetailRow(
                          icon: Icons.event,
                          label: 'Data de Vencimento',
                          value: formattedDueDate,
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
                  const SizedBox(height: 20),
                  if (record.status == 'pending' && record.receiptUrl == null)
                    // 3 - Reduced button size
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            olympusBlue,
                            olympusLightBlue,
                          ],
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                        ),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: olympusBlue.withOpacity(0.3),
                            spreadRadius: 1,
                            blurRadius: 8,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () => _uploadReceipt(record),
                          borderRadius: BorderRadius.circular(12),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: const Icon(
                                    Icons.camera_alt,
                                    color: Colors.white,
                                    size: 18,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                const Text(
                                  'Anexar Comprovante',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 15,
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
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            const Color(0xFFE8F5E9),
                            const Color(0xFFC8E6C9)
                          ],
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                        ),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFA5D6A7)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: Colors.green,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Icon(
                              Icons.check_circle,
                              color: Colors.white,
                              size: 18,
                            ),
                          ),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Comprovante Enviado',
                                  style: TextStyle(
                                    color: Color(0xFF2E7D32),
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  'Aguarde a aprovação do admin',
                                  style: TextStyle(
                                    color: Color(0xFF43A047),
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(Icons.chevron_right,
                              color: const Color(0xFF388E3C), size: 18),
                        ],
                      ),
                    )
                  else if (record.status == 'approved')
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            const Color(0xFFE8F5E9),
                            const Color(0xFFC8E6C9)
                          ],
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                        ),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFA5D6A7)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: Colors.green,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Icon(
                              Icons.verified,
                              color: Colors.white,
                              size: 18,
                            ),
                          ),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Pagamento Aprovado',
                                  style: TextStyle(
                                    color: Color(0xFF2E7D32),
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  'Confirmado pela administração',
                                  style: TextStyle(
                                    color: Color(0xFF43A047),
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(Icons.chevron_right,
                              color: const Color(0xFF388E3C), size: 18),
                        ],
                      ),
                    ),
                  const SizedBox(height: 24),
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
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: (iconColor ?? olympusBlue).withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            icon,
            size: 20,
            color: iconColor ?? olympusBlue,
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
