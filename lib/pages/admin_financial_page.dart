import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
          .select('id, full_name, phone')
          .eq('user_type', 'athlete')
          .order('full_name');

      if (mounted) {
        setState(() {
          _athletes = List<Map<String, dynamic>>.from(response)
            ..sort((a, b) => (a['full_name'] ?? '')
                .toString()
                .toLowerCase()
                .compareTo((b['full_name'] ?? '').toString().toLowerCase()));
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
          '🔍 BUSCANDO: mês=$_selectedMonth, ano=$_selectedYear, tipo=$_selectedType');

      var query = _supabase
          .from('financial_records')
          .select()
          .eq('month', _selectedMonth)
          .eq('year', _selectedYear);

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
            .select('id, full_name, phone')
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
    final valueController =
        TextEditingController(text: record.value.toString());
    final descriptionController =
        TextEditingController(text: record.description ?? '');
    int selectedMonth = record.month;
    int selectedYear = record.year;
    String selectedType = record.type;
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Editar Registro'),
          content: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
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
                      if (value == null || value.isEmpty) {
                        return 'Campo obrigatório';
                      }
                      if (double.tryParse(value) == null) {
                        return 'Valor inválido';
                      }
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
                    await _supabase.from('financial_records').update({
                      'type': selectedType,
                      'value': double.parse(valueController.text),
                      'description': selectedType == 'other'
                          ? descriptionController.text
                          : null,
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
              child: const Text('Salvar'),
            ),
          ],
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
        return const Color(0xFF2C3E5A);
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

  List<TextInputFormatter> _getPixInputFormatters(String type) {
    switch (type) {
      case 'phone':
        return [
          FilteringTextInputFormatter.allow(RegExp(r'[0-9()\-\s+]')),
        ];
      case 'cpf':
      case 'cnpj':
        return [
          FilteringTextInputFormatter.allow(RegExp(r'[0-9./\-]')),
        ];
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
    String selectedType = 'monthly';
    final valueController = TextEditingController();
    final descriptionController = TextEditingController();
    final pixKeyController = TextEditingController();
    String selectedPixKeyType = 'cpf';
    int selectedMonth = _selectedMonth;
    int selectedYear = _selectedYear;
    int selectedDay = DateTime.now().day;
    bool showOtherDescription = false;
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text(
            'Cadastrar Registro Financeiro',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
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
                        labelStyle:
                            TextStyle(fontSize: 11, color: Color(0xFF1565C0)),
                        border: InputBorder.none,
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                      ),
                      hint: const Text('Selecione um atleta',
                          style: TextStyle(fontSize: 12)),
                      isExpanded: true,
                      icon: const Icon(Icons.keyboard_arrow_down,
                          color: Color(0xFF1976D2), size: 18),
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
                            child: Text(
                              athlete['full_name'] ?? 'Sem nome',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFF424242),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          );
                        }),
                      ],
                      onChanged: (value) {
                        selectedAthleteId = value;
                      },
                      validator: (value) =>
                          value == null ? 'Campo obrigatório' : null,
                    ),
                  ),
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
                        labelStyle:
                            TextStyle(fontSize: 11, color: Color(0xFF7B1FA2)),
                        border: InputBorder.none,
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                      ),
                      isExpanded: true,
                      icon: const Icon(Icons.keyboard_arrow_down,
                          color: Color(0xFF8E24AA), size: 18),
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
                        labelStyle:
                            TextStyle(fontSize: 11, color: Color(0xFF388E3C)),
                        border: InputBorder.none,
                        prefixText: 'R\$ ',
                        hintText: '0,00',
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 8, vertical: 8),
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
                        labelStyle:
                            TextStyle(fontSize: 11, color: Color(0xFF3949AB)),
                        border: InputBorder.none,
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                      ),
                      isExpanded: true,
                      icon: const Icon(Icons.keyboard_arrow_down,
                          color: Color(0xFF5C6BC0), size: 18),
                      style: const TextStyle(
                          fontSize: 12, color: Color(0xFF424242)),
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
                            horizontal: 8, vertical: 8),
                      ),
                      style: const TextStyle(fontSize: 12),
                      keyboardType: selectedPixKeyType == 'phone'
                          ? TextInputType.phone
                          : TextInputType.number,
                      inputFormatters:
                          _getPixInputFormatters(selectedPixKeyType),
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
                          labelStyle:
                              TextStyle(fontSize: 11, color: Color(0xFFF57C00)),
                          border: InputBorder.none,
                          hintText: 'Informe do que se trata',
                          contentPadding:
                              EdgeInsets.symmetric(horizontal: 8, vertical: 8),
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
                                  fontSize: 11, color: Color(0xFF616161)),
                              border: InputBorder.none,
                              contentPadding: EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 8),
                            ),
                            isExpanded: true,
                            icon: const Icon(Icons.keyboard_arrow_down,
                                color: Color(0xFF757575), size: 18),
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
                                  fontSize: 11, color: Color(0xFF616161)),
                              border: InputBorder.none,
                              contentPadding: EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 8),
                            ),
                            isExpanded: true,
                            icon: const Icon(Icons.keyboard_arrow_down,
                                color: Color(0xFF757575), size: 18),
                            style: const TextStyle(fontSize: 12),
                            items: List.generate(12, (i) => i + 1).map((m) {
                              return DropdownMenuItem(
                                value: m,
                                child: Text(
                                  DateFormat.MMMM('pt_BR')
                                      .format(DateTime(2024, m)),
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
                                  fontSize: 11, color: Color(0xFF616161)),
                              border: InputBorder.none,
                              contentPadding: EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 8),
                            ),
                            isExpanded: true,
                            icon: const Icon(Icons.keyboard_arrow_down,
                                color: Color(0xFF757575), size: 18),
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

                    if (selectedAthleteId == 'all') {
                      final records = _athletes
                          .map((athlete) => {
                                'athlete_id': athlete['id'],
                                'type': selectedType,
                                'value': double.parse(numericValue),
                                'description': finalDescription,
                                'day': selectedDay,
                                'month': selectedMonth,
                                'year': selectedYear,
                                'status': 'pending',
                                'created_at': DateTime.now().toIso8601String(),
                              })
                          .toList();

                      await _supabase
                          .from('financial_records')
                          .insert(records)
                          .select();
                    } else {
                      await _supabase.from('financial_records').insert({
                        'athlete_id': selectedAthleteId,
                        'type': selectedType,
                        'value': double.parse(numericValue),
                        'description': finalDescription,
                        'day': selectedDay,
                        'month': selectedMonth,
                        'year': selectedYear,
                        'status': 'pending',
                        'created_at': DateTime.now().toIso8601String(),
                      }).select();
                    }

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
              child: const Text('Cadastrar', style: TextStyle(fontSize: 12)),
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
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Aprovado!'), backgroundColor: Colors.green));
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
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Rejeitado!'), backgroundColor: Colors.red));
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
                const Icon(
                  Icons.error_outline,
                  size: 48,
                  color: Colors.red,
                ),
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

  String _getAthleteName(String athleteId) {
    if (athleteId == 'all') return 'Todos';
    final athlete = _athleteData[athleteId];
    return athlete?['full_name'] ?? 'Atleta não encontrado';
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
      return !dueDate.isBefore(DateTime(today.year, today.month, today.day));
    }).fold<double>(0, (sum, r) => sum + r.value);
    final overdueValue = _records.where((r) {
      if (r.status != 'pending') return false;
      final dueDate = DateTime(r.year, r.month, r.day);
      final today = DateTime.now();
      return dueDate.isBefore(DateTime(today.year, today.month, today.day));
    }).fold<double>(0, (sum, r) => sum + r.value);

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
                          const Color(0xFF2C3E5A),
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
                              crossAxisAlignment: CrossAxisAlignment.start,
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
                                  padding:
                                      const EdgeInsets.symmetric(horizontal: 8),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF6F8FB),
                                    borderRadius: BorderRadius.circular(10),
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
                                    items: List.generate(12, (i) => i + 1)
                                        .map((m) => DropdownMenuItem(
                                              value: m,
                                              child: Text(
                                                DateFormat.MMMM('pt_BR')
                                                    .format(DateTime(2024, m)),
                                                style: const TextStyle(
                                                  fontSize: 12,
                                                  color: Color(0xFF424242),
                                                  fontWeight: FontWeight.w500,
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
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
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
                                  padding:
                                      const EdgeInsets.symmetric(horizontal: 8),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF6F8FB),
                                    borderRadius: BorderRadius.circular(10),
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
                                    items: [2026, 2027, 2028, 2029, 2030]
                                        .map((y) => DropdownMenuItem(
                                              value: y,
                                              child: Text(
                                                y.toString(),
                                                style: const TextStyle(
                                                  fontSize: 12,
                                                  color: Color(0xFF424242),
                                                  fontWeight: FontWeight.w500,
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
                            padding: const EdgeInsets.symmetric(horizontal: 8),
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
                                _loadRecords();
                              }),
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
                        itemCount: _getFilteredRecords().length,
                        itemBuilder: (context, index) {
                          final record = _getFilteredRecords()[index];
                          final typeColor = _getTypeColor(record.type);
                          final dueDate =
                              '${record.day.toString().padLeft(2, '0')}/${record.month.toString().padLeft(2, '0')}/${record.year}';
                          final isOverdue = _isOverdue(record);

                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [Colors.white, const Color(0xFFFAFAFA)],
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
                                          color: typeColor.withOpacity(0.1),
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
                                                fontWeight: FontWeight.w600,
                                                fontSize: 14,
                                                color: Color(0xFF2C3E5A),
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              'Atleta: ${_getAthleteName(record.athleteId)}',
                                              style: const TextStyle(
                                                color: Color(0xFF757575),
                                                fontSize: 11,
                                              ),
                                            ),
                                            Text(
                                              'Vencimento: $dueDate',
                                              style: TextStyle(
                                                color: isOverdue
                                                    ? Colors.red
                                                    : const Color(0xFF757575),
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
                                              fontWeight: FontWeight.bold,
                                              fontSize: 14,
                                              color: Color(0xFF2C3E5A),
                                            ),
                                          ),
                                          if (record.receiptUrl != null) ...[
                                            const SizedBox(height: 4),
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                horizontal: 8,
                                                vertical: 3,
                                              ),
                                              decoration: BoxDecoration(
                                                color: Colors.blue
                                                    .withOpacity(0.1),
                                                borderRadius:
                                                    BorderRadius.circular(20),
                                                border: Border.all(
                                                  color: Colors.blue
                                                      .withOpacity(0.25),
                                                ),
                                              ),
                                              child: const Row(
                                                mainAxisSize: MainAxisSize.min,
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
                                                      color: Colors.blue,
                                                      fontSize: 10,
                                                      fontWeight:
                                                          FontWeight.w600,
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
    );
  }

  List<FinancialRecord> _getFilteredRecords() {
    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);

    return _records.where((record) {
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

  Widget _buildCompactCard(String label, int value, IconData icon,
      Color baseColor, double amount, bool isSelected,
      {bool large = false}) {
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
                    baseColor.withOpacity(0.1)
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
            Icon(
              icon,
              color: isSelected ? Colors.white : baseColor,
              size: 18,
            ),
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
                      icon: const Icon(Icons.delete_outline, color: Colors.red),
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
                                  const Icon(Icons.check,
                                      color: Colors.white, size: 20),
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
                                  const Icon(Icons.close,
                                      color: Colors.white, size: 20),
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
                            backgroundColor: const Color(0xFF2C3E5A),
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
                                const Icon(Icons.person,
                                    color: Colors.white, size: 20),
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
                          gradient: const LinearGradient(
                            colors: [Color(0xFF2C3E5A), Color(0xFF4A6FA5)],
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                          ),
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF2C3E5A).withOpacity(0.3),
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
                                const Icon(Icons.close,
                                    color: Colors.white, size: 20),
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
            child: Text('$label:',
                style: const TextStyle(fontWeight: FontWeight.bold)),
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
