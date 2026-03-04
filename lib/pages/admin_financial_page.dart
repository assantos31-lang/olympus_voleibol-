import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import '../models/financial_record_model.dart';

class AdminFinancialPage extends StatefulWidget {
  const AdminFinancialPage({super.key});

  @override
  State<AdminFinancialPage> createState() => _AdminFinancialPageState();
}

class _AdminFinancialPageState extends State<AdminFinancialPage> {
  final _supabase = Supabase.instance.client;
  List<FinancialRecord> _records = [];
  Map<String, Map<String, dynamic>> _athleteData = {};
  List<Map<String, dynamic>> _athletes = [];
  bool _isLoading = true;

  int _selectedMonth = DateTime.now().month;
  int _selectedYear = 2026;
  String _selectedStatus = 'all';
  String _selectedType = 'all';

  @override
  void initState() {
    super.initState();
    _loadAthletes();
    _loadRecords();
  }

  Future<void> _loadAthletes() async {
    try {
      final response = await _supabase
          .from('profiles')
          .select('id, full_name')
          .eq('user_type', 'athlete')
          .order('full_name');

      if (mounted) {
        setState(() {
          _athletes = List<Map<String, dynamic>>.from(response);
        });
      }
    } catch (e) {
      debugPrint('Erro atletas: $e');
    }
  }

  Future<void> _loadRecords() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      debugPrint(
          '🔍 BUSCANDO: mês=$_selectedMonth, ano=$_selectedYear, status=$_selectedStatus, tipo=$_selectedType');

      var query = _supabase
          .from('financial_records')
          .select()
          .eq('month', _selectedMonth)
          .eq('year', _selectedYear);

      if (_selectedStatus != 'all') {
        query = query.eq('status', _selectedStatus);
      }

      if (_selectedType != 'all') {
        query = query.eq('type', _selectedType);
      }

      debugPrint('📊 Executando query...');
      final response = await query.order('created_at', ascending: false);

      debugPrint('✅ RETORNO DO BANCO: ${(response as List).length} registros');

      final records =
          (response as List).map((r) => FinancialRecord.fromMap(r)).toList();

      debugPrint('📋 Após mapeamento: ${records.length} registros');

      final athleteIds = records.map((r) => r.athleteId).toSet().toList();
      if (athleteIds.isNotEmpty) {
        final athletesResponse = await _supabase
            .from('profiles')
            .select('id, full_name')
            .filter('id', 'in', "(${athleteIds.join(',')})");

        _athleteData = {
          for (var athlete in athletesResponse as List) athlete['id']: athlete
        };
      }

      if (mounted) {
        setState(() {
          _records = records;
          _isLoading = false;
        });
        debugPrint('🎯 FINAL: ${_records.length} registros na tela');
      }
    } catch (e) {
      debugPrint('❌ ERRO: $e');
      if (mounted) {
        setState(() => _isLoading = false);
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
    switch (type) {
      case 'monthly':
        return const Color(0xFF667eea);
      case 'games':
        return const Color(0xFFf093fb);
      case 'maintenance':
        return const Color(0xFF4facfe);
      case 'other':
        return const Color(0xFF43e97b);
      default:
        return const Color(0xFF667eea);
    }
  }

  void _showCreateRecordDialog() {
    String? selectedAthleteId;
    String selectedType = 'monthly';
    final valueController = TextEditingController();
    final descriptionController = TextEditingController();

    int selectedMonth = _selectedMonth;
    int selectedYear = _selectedYear;

    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Cadastrar Registro Financeiro'),
          content: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    value: selectedAthleteId,
                    decoration: const InputDecoration(
                      labelText: 'Atleta *',
                      border: OutlineInputBorder(),
                    ),
                    hint: const Text('Selecione um atleta'),
                    items: _athletes.map((athlete) {
                      return DropdownMenuItem<String>(
                        value: athlete['id'] as String,
                        child: Text(athlete['full_name'] ?? 'Sem nome'),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setDialogState(() {
                        selectedAthleteId = value;
                      });
                    },
                    validator: (value) =>
                        value == null ? 'Campo obrigatório' : null,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: selectedType,
                    decoration: const InputDecoration(
                      labelText: 'Tipo *',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(
                          value: 'monthly', child: Text('Mensalidade')),
                      DropdownMenuItem(value: 'games', child: Text('Jogos')),
                      DropdownMenuItem(
                          value: 'maintenance', child: Text('Manutenção')),
                      DropdownMenuItem(value: 'other', child: Text('Outros')),
                    ],
                    onChanged: (value) {
                      setDialogState(() {
                        selectedType = value!;
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: valueController,
                    decoration: const InputDecoration(
                      labelText: 'Valor (R\$) *',
                      border: OutlineInputBorder(),
                      prefixText: 'R\$ ',
                    ),
                    keyboardType: TextInputType.number,
                    validator: (value) {
                      if (value == null || value.isEmpty)
                        return 'Campo obrigatório';
                      if (double.tryParse(value) == null)
                        return 'Valor inválido';
                      return null;
                    },
                  ),
                  if (selectedType == 'other') ...[
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: descriptionController,
                      decoration: const InputDecoration(
                        labelText: 'Descrição *',
                        border: OutlineInputBorder(),
                        hintText: 'Informe do que se trata',
                      ),
                      maxLines: 2,
                      validator: (value) {
                        if (selectedType == 'other' &&
                            (value == null || value.isEmpty)) {
                          return 'Campo obrigatório para "Outros"';
                        }
                        return null;
                      },
                    ),
                  ],
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          value: selectedMonth,
                          decoration: const InputDecoration(
                            labelText: 'Mês *',
                            border: OutlineInputBorder(),
                          ),
                          items: List.generate(12, (i) => i + 1).map((m) {
                            return DropdownMenuItem(
                              value: m,
                              child: Text(DateFormat.MMMM('pt_BR')
                                  .format(DateTime(2024, m))),
                            );
                          }).toList(),
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
                          decoration: const InputDecoration(
                            labelText: 'Ano *',
                            border: OutlineInputBorder(),
                          ),
                          items: [2026, 2027, 2028, 2029, 2030].map((y) {
                            return DropdownMenuItem(
                              value: y,
                              child: Text(y.toString()),
                            );
                          }).toList(),
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
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (formKey.currentState!.validate()) {
                  try {
                    await _supabase.from('financial_records').insert({
                      'athlete_id': selectedAthleteId,
                      'type': selectedType,
                      'value': double.parse(valueController.text),
                      'description': selectedType == 'other'
                          ? descriptionController.text
                          : null,
                      'month': selectedMonth,
                      'year': selectedYear,
                      'status': 'pending',
                      'created_at': DateTime.now().toIso8601String(),
                    }).select();

                    if (mounted) {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('✅ Registro cadastrado!'),
                          backgroundColor: Colors.green,
                        ),
                      );
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
              child: const Text('Cadastrar'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _approvePayment(String recordId) async {
    try {
      await _supabase.from('financial_records').update({
        'status': 'approved',
        'approved_by': _supabase.auth.currentUser!.id,
        'approved_at': DateTime.now().toIso8601String(),
      }).eq('id', recordId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Aprovado!'), backgroundColor: Colors.green),
        );
        _loadRecords();
      }
    } catch (e) {
      debugPrint('Erro aprovar: $e');
    }
  }

  Future<void> _rejectPayment(String recordId) async {
    try {
      await _supabase.from('financial_records').update({
        'status': 'rejected',
        'approved_by': _supabase.auth.currentUser!.id,
        'approved_at': DateTime.now().toIso8601String(),
      }).eq('id', recordId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Rejeitado!'), backgroundColor: Colors.red),
        );
        _loadRecords();
      }
    } catch (e) {
      debugPrint('Erro rejeitar: $e');
    }
  }

  Future<void> _viewReceipt(String receiptUrl) async {
    final publicUrl =
        _supabase.storage.from('receipts').getPublicUrl(receiptUrl);
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
                actions: [
                  IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context)),
                ],
              ),
              Padding(
                  padding: const EdgeInsets.all(16),
                  child: Image.network(publicUrl)),
            ],
          ),
        ),
      );
    }
  }

  String _getAthleteName(String athleteId) {
    final athlete = _athleteData[athleteId];
    return athlete?['full_name'] ?? 'Atleta não encontrado';
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Financeiro - Admin',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 20,
          ),
        ),
        backgroundColor: const Color(0xFF2C3E5A),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadRecords),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showCreateRecordDialog,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text(
          'Cadastrar',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
        backgroundColor: const Color(0xFF2C3E5A),
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            color: const Color(0xFFF5F5F5),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.grey.withOpacity(0.08),
                              spreadRadius: 1,
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: DropdownButton<int>(
                          value: _selectedMonth,
                          isExpanded: true,
                          underline: const SizedBox(),
                          icon: const Icon(Icons.keyboard_arrow_down,
                              color: Color(0xFF757575)),
                          items: List.generate(12, (i) => i + 1)
                              .map((m) => DropdownMenuItem(
                                    value: m,
                                    child: Text(
                                      DateFormat.MMMM('pt_BR')
                                          .format(DateTime(2024, m)),
                                      style: const TextStyle(
                                        fontSize: 14,
                                        color: Color(0xFF424242),
                                      ),
                                    ),
                                  ))
                              .toList(),
                          onChanged: (v) => setState(() {
                            _selectedMonth = v!;
                            _loadRecords();
                          }),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.grey.withOpacity(0.08),
                              spreadRadius: 1,
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: DropdownButton<int>(
                          value: _selectedYear,
                          isExpanded: true,
                          underline: const SizedBox(),
                          icon: const Icon(Icons.keyboard_arrow_down,
                              color: Color(0xFF757575)),
                          items: [2026, 2027, 2028, 2029, 2030]
                              .map((y) => DropdownMenuItem(
                                    value: y,
                                    child: Text(
                                      y.toString(),
                                      style: const TextStyle(
                                        fontSize: 14,
                                        color: Color(0xFF424242),
                                      ),
                                    ),
                                  ))
                              .toList(),
                          onChanged: (v) => setState(() {
                            _selectedYear = v!;
                            _loadRecords();
                          }),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.grey.withOpacity(0.08),
                              spreadRadius: 1,
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: DropdownButton<String>(
                          value: _selectedStatus,
                          isExpanded: true,
                          underline: const SizedBox(),
                          icon: const Icon(Icons.keyboard_arrow_down,
                              color: Color(0xFF757575)),
                          items: const [
                            DropdownMenuItem(
                                value: 'all', child: Text('Todos')),
                            DropdownMenuItem(
                                value: 'pending', child: Text('Pendentes')),
                            DropdownMenuItem(
                                value: 'approved', child: Text('Aprovados')),
                          ],
                          onChanged: (v) => setState(() {
                            _selectedStatus = v!;
                            _loadRecords();
                          }),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.grey.withOpacity(0.08),
                              spreadRadius: 1,
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: DropdownButton<String>(
                          value: _selectedType,
                          isExpanded: true,
                          underline: const SizedBox(),
                          icon: const Icon(Icons.keyboard_arrow_down,
                              color: Color(0xFF757575)),
                          items: const [
                            DropdownMenuItem(
                                value: 'all', child: Text('Todos Tipos')),
                            DropdownMenuItem(
                                value: 'monthly', child: Text('Mensalidade')),
                            DropdownMenuItem(
                                value: 'games', child: Text('Jogos')),
                            DropdownMenuItem(
                                value: 'maintenance',
                                child: Text('Manutenção')),
                            DropdownMenuItem(
                                value: 'other', child: Text('Outros')),
                          ],
                          onChanged: (v) => setState(() {
                            _selectedType = v!;
                            _loadRecords();
                          }),
                        ),
                      ),
                    ),
                  ],
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
                        padding: const EdgeInsets.all(16),
                        itemCount: _records.length,
                        itemBuilder: (context, index) {
                          final record = _records[index];
                          final typeColor = _getTypeColor(record.type);

                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [Colors.white, const Color(0xFFFAFAFA)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.grey.withOpacity(0.1),
                                  spreadRadius: 2,
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: () => _showRecordDetails(record),
                                borderRadius: BorderRadius.circular(16),
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 50,
                                        height: 50,
                                        decoration: BoxDecoration(
                                          color: typeColor.withOpacity(0.1),
                                          borderRadius:
                                              BorderRadius.circular(12),
                                        ),
                                        child: Icon(
                                          _getTypeIcon(record.type),
                                          color: typeColor,
                                          size: 26,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              record.typeLabel,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w600,
                                                fontSize: 16,
                                                color: Color(0xFF2C3E5A),
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              'Atleta: ${_getAthleteName(record.athleteId)}',
                                              style: const TextStyle(
                                                color: Color(0xFF757575),
                                                fontSize: 13,
                                              ),
                                            ),
                                            if (record.description != null)
                                              Text(
                                                record.description!,
                                                style: const TextStyle(
                                                  color: Color(0xFF757575),
                                                  fontSize: 12,
                                                  fontStyle: FontStyle.italic,
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            Text(
                                              'Mês: ${record.month}/${record.year}',
                                              style: const TextStyle(
                                                color: Color(0xFF757575),
                                                fontSize: 13,
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
                                              fontWeight: FontWeight.bold,
                                              fontSize: 18,
                                              color: Color(0xFF2C3E5A),
                                            ),
                                          ),
                                          const SizedBox(height: 6),
                                          _buildStatusBadge(record.status),
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
    );
  }

  void _showRecordDetails(FinancialRecord record) {
    final typeColor = _getTypeColor(record.type);

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
                          valueColor: const Color(0xFF2C3E5A),
                          valueWeight: FontWeight.w600,
                        ),
                        const Divider(height: 32),
                        _buildDetailRow(
                          icon: Icons.attach_money,
                          label: 'Valor',
                          value: 'R\$ ${record.value.toStringAsFixed(2)}',
                          valueColor: const Color(0xFF2C3E5A),
                          valueWeight: FontWeight.bold,
                        ),
                        const Divider(height: 32),
                        _buildDetailRow(
                          icon: record.status == 'approved'
                              ? Icons.check_circle
                              : record.status == 'pending'
                                  ? Icons.schedule
                                  : Icons.cancel,
                          label: 'Status',
                          value: record.statusLabel,
                          valueColor: record.status == 'approved'
                              ? Colors.green
                              : record.status == 'pending'
                                  ? Colors.orange
                                  : Colors.red,
                          valueWeight: FontWeight.w600,
                          iconColor: record.status == 'approved'
                              ? Colors.green
                              : record.status == 'pending'
                                  ? Colors.orange
                                  : Colors.red,
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
                  const SizedBox(height: 20),
                  if (record.receiptUrl != null)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            const Color(0xFFE3F2FD),
                            const Color(0xFFBBDEFB)
                          ],
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                        ),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFF90CAF9)),
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () => _viewReceipt(record.receiptUrl!),
                          borderRadius: BorderRadius.circular(16),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: Colors.blue,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Icon(
                                    Icons.visibility,
                                    color: Colors.white,
                                    size: 24,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                const Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Ver Comprovante',
                                        style: TextStyle(
                                          color: Color(0xFF1565C0),
                                          fontSize: 15,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      Text(
                                        'Clique para visualizar',
                                        style: TextStyle(
                                          color: Color(0xFF42A5F5),
                                          fontSize: 13,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Icon(Icons.chevron_right,
                                    color: const Color(0xFF1976D2)),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  if (record.status == 'pending') ...[
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Colors.green[600]!,
                                  Colors.green[400]!
                                ],
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
                                onTap: () => _approvePayment(record.id),
                                borderRadius: BorderRadius.circular(12),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(Icons.check,
                                        color: Colors.white, size: 20),
                                    const SizedBox(width: 8),
                                    const Text(
                                      'Aprovar',
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
                                onTap: () => _rejectPayment(record.id),
                                borderRadius: BorderRadius.circular(12),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(Icons.close,
                                        color: Colors.white, size: 20),
                                    const SizedBox(width: 8),
                                    const Text(
                                      'Rejeitar',
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
                        ),
                      ],
                    ),
                  ],
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
              child: Text('$label:',
                  style: const TextStyle(fontWeight: FontWeight.bold))),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}
