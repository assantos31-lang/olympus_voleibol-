import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

class AddEventPage extends StatefulWidget {
  final List<Map<String, String>>? registeredAthletes;
  final List<Map<String, String>>? registeredTechnicians;

  const AddEventPage({
    super.key,
    this.registeredAthletes,
    this.registeredTechnicians,
  });

  @override
  State<AddEventPage> createState() => _AddEventPageState();
}

class _AddEventPageState extends State<AddEventPage> {
  final _formKey = GlobalKey<FormState>();
  final goldenColor = const Color(0xFFE4C050);

  EventType _selectedType = EventType.treino;

  final _dateController = TextEditingController();
  final _timeController = TextEditingController();
  final _opponentController = TextEditingController();
  final _cepController = TextEditingController();
  final _ruaController = TextEditingController();
  final _numeroController = TextEditingController();
  final _bairroController = TextEditingController();
  final _cidadeController = TextEditingController();
  final _estadoController = TextEditingController();

  String _filtroGenero = 'Todos';
  String _filtroPessoa = 'Atleta';
  String _setsFormat = '1 Set';

  final List<String> _selectedAthletes = [];
  final List<String> _selectedTechnicians = [];

  bool _isSearchingCep = false;

  // ✅ Estados para dados do Supabase
  List<Map<String, String>> _athletesFromSupabase = [];
  List<Map<String, String>> _techniciansFromSupabase = [];
  bool _isLoadingProfiles = true;

  @override
  void initState() {
    super.initState();
    _fetchProfilesFromSupabase();
  }

  // ✅ Busca perfis do Supabase - CORREÇÃO: removido specialty
  Future<void> _fetchProfilesFromSupabase() async {
    try {
      final supabase = Supabase.instance.client;

      // Busca atletas: profiles com user_type = 'athlete'
      final athletesResponse = await supabase
          .from('profiles')
          .select('id, full_name, user_type')
          .eq('user_type', 'athlete');

      // Busca técnicos: profiles com user_type = 'coach'
      // ✅ CORREÇÃO: removido specialty (coluna não existe)
      final coachesResponse = await supabase
          .from('profiles')
          .select('id, full_name, user_type')
          .eq('user_type', 'coach');

      // Mapeia atletas
      final athletesList = athletesResponse.map<Map<String, String>>((p) {
        return {
          'uid': p['id']?.toString() ?? '',
          'nome': p['full_name'] ?? 'Usuário',
          'genero': 'Masculino', // Default
        };
      }).toList();

      // Mapeia técnicos
      final techniciansList = coachesResponse.map<Map<String, String>>((p) {
        return {
          'uid': p['id']?.toString() ?? '',
          'nome': p['full_name'] ?? 'Técnico',
          'especialidade': 'Técnico', // ✅ Valor fixo
        };
      }).toList();

      setState(() {
        _athletesFromSupabase = athletesList;
        _techniciansFromSupabase = techniciansList;
        _isLoadingProfiles = false;
      });
    } catch (e) {
      setState(() => _isLoadingProfiles = false);
      _showError('Erro ao carregar perfis: ${e.toString()}');
    }
  }

  // ✅ Prioridade: parâmetros > Supabase > mock data
  List<Map<String, String>> get _athletesList =>
      widget.registeredAthletes?.isNotEmpty == true
          ? widget.registeredAthletes!
          : _athletesFromSupabase.isNotEmpty
              ? _athletesFromSupabase
              : _mockAthletes;

  List<Map<String, String>> get _techniciansList =>
      widget.registeredTechnicians?.isNotEmpty == true
          ? widget.registeredTechnicians!
          : _techniciansFromSupabase.isNotEmpty
              ? _techniciansFromSupabase
              : _mockTechnicians;

  static const List<Map<String, String>> _mockAthletes = [
    {'nome': 'Ana Silva', 'genero': 'Feminino'},
    {'nome': 'Beatriz Costa', 'genero': 'Feminino'},
    {'nome': 'Carla Souza', 'genero': 'Feminino'},
    {'nome': 'João Santos', 'genero': 'Masculino'},
    {'nome': 'Pedro Lima', 'genero': 'Masculino'},
    {'nome': 'Lucas Oliveira', 'genero': 'Masculino'},
  ];

  static const List<Map<String, String>> _mockTechnicians = [
    {'nome': 'Carlos Mendes', 'especialidade': 'Técnico Principal'},
    {'nome': 'Mariana Alves', 'especialidade': 'Preparadora Física'},
    {'nome': 'Roberto Dias', 'especialidade': 'Assistente'},
  ];

  @override
  void dispose() {
    _dateController.dispose();
    _timeController.dispose();
    _opponentController.dispose();
    _cepController.dispose();
    _ruaController.dispose();
    _numeroController.dispose();
    _bairroController.dispose();
    _cidadeController.dispose();
    _estadoController.dispose();
    super.dispose();
  }

  Future<void> _buscarCep(String cep) async {
    if (cep.length != 8) {
      _showError('CEP deve conter 8 dígitos');
      return;
    }

    setState(() => _isSearchingCep = true);

    try {
      final response = await http
          .get(Uri.parse('https://viacep.com.br/ws/$cep/json/'))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['erro'] == null) {
          setState(() {
            _ruaController.text = data['logradouro'] ?? '';
            _bairroController.text = data['bairro'] ?? '';
            _cidadeController.text = data['localidade'] ?? '';
            _estadoController.text = data['uf'] ?? '';
            _isSearchingCep = false;
          });
          _showSuccess('CEP encontrado com sucesso!');
        } else {
          setState(() => _isSearchingCep = false);
          _showError('CEP não encontrado. Verifique o número digitado.');
        }
      } else {
        setState(() => _isSearchingCep = false);
        _showError('Erro na conexão. Tente novamente.');
      }
    } on TimeoutException {
      setState(() => _isSearchingCep = false);
      _showError('Tempo de resposta excedido. Verifique sua conexão.');
    } catch (e) {
      setState(() => _isSearchingCep = false);
      _showError('Erro ao buscar CEP. Verifique sua conexão com a internet.');
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.red.shade700,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  void _showSuccess(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle_outline, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.green.shade700,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2024),
      lastDate: DateTime(2030),
      locale: const Locale('pt', 'BR'),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: goldenColor,
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: Colors.black,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        _dateController.text =
            '${picked.day.toString().padLeft(2, '0')}/${picked.month.toString().padLeft(2, '0')}/${picked.year}';
      });
    }
  }

  Future<void> _selectTime(BuildContext context) async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: goldenColor,
              onPrimary: Colors.white,
            ),
            timePickerTheme: const TimePickerThemeData(
              backgroundColor: Color(0xFF1E3A5F),
              dialBackgroundColor: Color(0xFF2E5C8A),
              dialTextColor: Colors.white,
              hourMinuteTextColor: Colors.white,
              entryModeIconColor: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        _timeController.text = picked.format(context);
      });
    }
  }

  List<Map<String, String>> _getFilteredAthletes() {
    if (_filtroGenero == 'Todos') return _athletesList;
    return _athletesList.where((a) => a['genero'] == _filtroGenero).toList();
  }

  void _toggleAthleteSelection(String nome) {
    setState(() {
      if (_selectedAthletes.contains(nome)) {
        _selectedAthletes.remove(nome);
      } else {
        _selectedAthletes.add(nome);
      }
    });
  }

  void _toggleTechnicianSelection(String nome) {
    setState(() {
      if (_selectedTechnicians.contains(nome)) {
        _selectedTechnicians.remove(nome);
      } else {
        _selectedTechnicians.add(nome);
      }
    });
  }

  void _salvarEvento() {
    if (!_formKey.currentState!.validate()) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Evento salvo com sucesso!'),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
      ),
    );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1E3A5F),
      appBar: AppBar(
        title: const Text(
          'Novo Evento',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        backgroundColor: const Color(0xFF2E5C8A),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          TextButton(
            onPressed: _salvarEvento,
            child: const Text(
              'Salvar',
              style: TextStyle(
                color: Color(0xFFE4C050),
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildEventTypeSelector(),
            const SizedBox(height: 24),
            if (_selectedType == EventType.amistoso ||
                _selectedType == EventType.campeonato) ...[
              _buildOpponentField(),
              const SizedBox(height: 16),
              _buildSetsFormatSelector(),
              const SizedBox(height: 24),
            ],
            _buildDateTimeFields(),
            const SizedBox(height: 24),
            _buildConvocationSection(),
            const SizedBox(height: 24),
            _buildAddressSection(),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildEventTypeSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Tipo de Evento',
          style: TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            _buildEventTypeChip('Treino', EventType.treino),
            const SizedBox(width: 8),
            _buildEventTypeChip('Amistoso', EventType.amistoso),
            const SizedBox(width: 8),
            _buildEventTypeChip('Campeonato', EventType.campeonato),
          ],
        ),
      ],
    );
  }

  Widget _buildEventTypeChip(String label, EventType type) {
    final isSelected = _selectedType == type;
    return FilterChip(
      label: Text(
        label,
        style: TextStyle(
          color: isSelected ? Colors.white : Colors.white70,
          fontSize: 13,
        ),
      ),
      selected: isSelected,
      onSelected: (selected) {
        setState(() => _selectedType = type);
      },
      backgroundColor: Colors.white.withOpacity(0.1),
      selectedColor: goldenColor,
      checkmarkColor: Colors.white,
      labelStyle: const TextStyle(color: Colors.white),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color:
              isSelected ? Colors.transparent : Colors.white.withOpacity(0.3),
        ),
      ),
    );
  }

  Widget _buildOpponentField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Adversário',
          style: TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withOpacity(0.3)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextFormField(
            controller: _opponentController,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              hintText: 'Digite o nome do adversário',
              hintStyle: TextStyle(color: Colors.white54),
              border: InputBorder.none,
              prefixText: 'Olympus VS ',
              prefixStyle: TextStyle(color: Color(0xFFE4C050)),
            ),
            validator: (value) {
              if (value?.isEmpty ?? true) return 'Informe o adversário';
              return null;
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSetsFormatSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Formato de Sets',
          style: TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _buildSetChip('1 Set', 'Vencedor único'),
            _buildSetChip('3 Sets', 'Melhor de 3'),
            _buildSetChip('5 Sets', 'Melhor de 5'),
          ],
        ),
      ],
    );
  }

  Widget _buildSetChip(String label, String description) {
    final isSelected = _setsFormat == label;
    return GestureDetector(
      onTap: () => setState(() => _setsFormat = label),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? goldenColor : Colors.white.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color:
                isSelected ? Colors.transparent : Colors.white.withOpacity(0.3),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
            Text(
              description,
              style: TextStyle(
                color: isSelected ? Colors.white70 : Colors.white54,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDateTimeFields() {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Data',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: () => _selectDate(context),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.calendar_today, color: goldenColor, size: 18),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _dateController.text.isEmpty
                              ? 'Selecione a data'
                              : _dateController.text,
                          style: TextStyle(
                            color: _dateController.text.isEmpty
                                ? Colors.white54
                                : Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Hora',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: () => _selectTime(context),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.access_time, color: goldenColor, size: 18),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _timeController.text.isEmpty
                              ? 'Selecione a hora'
                              : _timeController.text,
                          style: TextStyle(
                            color: _timeController.text.isEmpty
                                ? Colors.white54
                                : Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildConvocationSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Convocar',
          style: TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            _buildConvocationTab('Atleta', 'Atleta'),
            _buildConvocationTab('Técnico', 'Tecnico'),
          ],
        ),
        const SizedBox(height: 16),
        if (_filtroPessoa == 'Atleta') ...[
          Row(
            children: [
              const Text(
                'Gênero: ',
                style: TextStyle(color: Colors.white70, fontSize: 14),
              ),
              const SizedBox(width: 8),
              _buildGenderFilterChip('Todos'),
              const SizedBox(width: 8),
              _buildGenderFilterChip('Masculino'),
              const SizedBox(width: 8),
              _buildGenderFilterChip('Feminino'),
            ],
          ),
          const SizedBox(height: 16),
        ],
        // ✅ Loading indicator
        if (_isLoadingProfiles)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(32.0),
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFE4C050)),
              ),
            ),
          )
        else
          Container(
            constraints: const BoxConstraints(maxHeight: 200),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withOpacity(0.2)),
            ),
            child: ListView(
              padding: const EdgeInsets.all(8),
              children: _filtroPessoa == 'Atleta'
                  ? _getFilteredAthletes().map((athlete) {
                      return _buildPersonTile(
                        name: athlete['nome']!,
                        subtitle: athlete['genero'],
                        isSelected: _selectedAthletes.contains(athlete['nome']),
                        onToggle: () =>
                            _toggleAthleteSelection(athlete['nome']!),
                      );
                    }).toList()
                  : _techniciansList.map((tech) {
                      return _buildPersonTile(
                        name: tech['nome']!,
                        subtitle: tech['especialidade'],
                        isSelected: _selectedTechnicians.contains(tech['nome']),
                        onToggle: () =>
                            _toggleTechnicianSelection(tech['nome']!),
                      );
                    }).toList(),
            ),
          ),
        if (_filtroPessoa == 'Atleta' && _selectedAthletes.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _selectedAthletes.map((name) {
              return Chip(
                label: Text(
                  name,
                  style: const TextStyle(fontSize: 12, color: Colors.white),
                ),
                backgroundColor: goldenColor.withOpacity(0.3),
                deleteIcon:
                    const Icon(Icons.close, size: 16, color: Colors.white),
                onDeleted: () => _toggleAthleteSelection(name),
              );
            }).toList(),
          ),
        ],
        if (_filtroPessoa == 'Tecnico' && _selectedTechnicians.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _selectedTechnicians.map((name) {
              return Chip(
                label: Text(
                  name,
                  style: const TextStyle(fontSize: 12, color: Colors.white),
                ),
                backgroundColor: goldenColor.withOpacity(0.3),
                deleteIcon:
                    const Icon(Icons.close, size: 16, color: Colors.white),
                onDeleted: () => _toggleTechnicianSelection(name),
              );
            }).toList(),
          ),
        ],
      ],
    );
  }

  Widget _buildConvocationTab(String label, String value) {
    final isSelected = _filtroPessoa == value;
    return GestureDetector(
      onTap: () => setState(() => _filtroPessoa = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? goldenColor : Colors.white.withOpacity(0.1),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(12),
            topRight: Radius.circular(12),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.white70,
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
      ),
    );
  }

  Widget _buildGenderFilterChip(String label) {
    final isSelected = _filtroGenero == label;
    return FilterChip(
      label: Text(
        label,
        style: TextStyle(
          color: isSelected ? Colors.white : Colors.white70,
          fontSize: 12,
        ),
      ),
      selected: isSelected,
      onSelected: (selected) {
        setState(() => _filtroGenero = label);
      },
      backgroundColor: Colors.white.withOpacity(0.1),
      selectedColor: goldenColor,
      labelStyle: const TextStyle(color: Colors.white),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color:
              isSelected ? Colors.transparent : Colors.white.withOpacity(0.3),
        ),
      ),
    );
  }

  Widget _buildPersonTile({
    required String name,
    required String? subtitle,
    required bool isSelected,
    required VoidCallback onToggle,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      leading: Checkbox(
        value: isSelected,
        onChanged: (_) => onToggle(),
        activeColor: goldenColor,
        checkColor: Colors.white,
        side: BorderSide(color: Colors.white.withOpacity(0.5)),
      ),
      title: Text(
        name,
        style: const TextStyle(color: Colors.white, fontSize: 14),
      ),
      subtitle: subtitle != null
          ? Text(
              subtitle,
              style: TextStyle(color: Colors.white54, fontSize: 12),
            )
          : null,
    );
  }

  Widget _buildAddressSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Local do Evento',
          style: TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _cepController,
          style: const TextStyle(color: Colors.white),
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(8),
          ],
          decoration: InputDecoration(
            labelText: 'CEP',
            labelStyle: TextStyle(color: Colors.white.withOpacity(0.7)),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.white.withOpacity(0.3)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.white.withOpacity(0.3)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFE4C050)),
            ),
            prefixIcon: Icon(Icons.location_on, color: goldenColor),
            suffixIcon: _isSearchingCep
                ? const Padding(
                    padding: EdgeInsets.all(12.0),
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          Color(0xFFE4C050),
                        ),
                      ),
                    ),
                  )
                : IconButton(
                    icon: const Icon(Icons.search, color: Color(0xFFE4C050)),
                    onPressed: () => _buscarCep(_cepController.text),
                  ),
            filled: true,
            fillColor: Colors.white.withOpacity(0.05),
          ),
          validator: (value) {
            if (value?.isEmpty ?? true) return 'Informe o CEP';
            if (value!.length != 8) return 'CEP deve ter 8 dígitos';
            return null;
          },
          onChanged: (valor) {
            if (valor.length == 8) _buscarCep(valor);
          },
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _ruaController,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            labelText: 'Rua',
            labelStyle: TextStyle(color: Colors.white.withOpacity(0.7)),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.white.withOpacity(0.3)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.white.withOpacity(0.3)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFE4C050)),
            ),
            prefixIcon: Icon(Icons.streetview, color: goldenColor),
            filled: true,
            fillColor: Colors.white.withOpacity(0.05),
          ),
          validator: (value) {
            if (value?.isEmpty ?? true) return 'Informe a rua';
            return null;
          },
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              flex: 1,
              child: TextFormField(
                controller: _numeroController,
                style: const TextStyle(color: Colors.white),
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Número',
                  labelStyle: TextStyle(color: Colors.white.withOpacity(0.7)),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide:
                        BorderSide(color: Colors.white.withOpacity(0.3)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide:
                        BorderSide(color: Colors.white.withOpacity(0.3)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFFE4C050)),
                  ),
                  filled: true,
                  fillColor: Colors.white.withOpacity(0.05),
                ),
                validator: (value) {
                  if (value?.isEmpty ?? true) return 'Informe o número';
                  return null;
                },
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              flex: 2,
              child: TextFormField(
                controller: _bairroController,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Bairro',
                  labelStyle: TextStyle(color: Colors.white.withOpacity(0.7)),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide:
                        BorderSide(color: Colors.white.withOpacity(0.3)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide:
                        BorderSide(color: Colors.white.withOpacity(0.3)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFFE4C050)),
                  ),
                  filled: true,
                  fillColor: Colors.white.withOpacity(0.05),
                ),
                validator: (value) {
                  if (value?.isEmpty ?? true) return 'Informe o bairro';
                  return null;
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              flex: 3,
              child: TextFormField(
                controller: _cidadeController,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Cidade',
                  labelStyle: TextStyle(color: Colors.white.withOpacity(0.7)),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide:
                        BorderSide(color: Colors.white.withOpacity(0.3)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide:
                        BorderSide(color: Colors.white.withOpacity(0.3)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFFE4C050)),
                  ),
                  filled: true,
                  fillColor: Colors.white.withOpacity(0.05),
                ),
                validator: (value) {
                  if (value?.isEmpty ?? true) return 'Informe a cidade';
                  return null;
                },
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              flex: 1,
              child: TextFormField(
                controller: _estadoController,
                style: const TextStyle(color: Colors.white),
                maxLength: 2,
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(
                  labelText: 'UF',
                  labelStyle: TextStyle(color: Colors.white.withOpacity(0.7)),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide:
                        BorderSide(color: Colors.white.withOpacity(0.3)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide:
                        BorderSide(color: Colors.white.withOpacity(0.3)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFFE4C050)),
                  ),
                  counterText: '',
                  filled: true,
                  fillColor: Colors.white.withOpacity(0.05),
                ),
                validator: (value) {
                  if (value?.isEmpty ?? true) return 'Informe o estado';
                  return null;
                },
              ),
            ),
          ],
        ),
      ],
    );
  }
}

enum EventType { treino, amistoso, campeonato }
