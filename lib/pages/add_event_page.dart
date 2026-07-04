import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

class AddEventPage extends StatefulWidget {
  final List<Map<String, String>>? registeredAthletes;
  final List<Map<String, String>>? registeredTechnicians;
  final Map<String, dynamic>? evento;

  const AddEventPage({
    super.key,
    this.registeredAthletes,
    this.registeredTechnicians,
    this.evento,
  });

  @override
  State<AddEventPage> createState() => _AddEventPageState();
}

class _AddEventPageState extends State<AddEventPage> {
  final _formKey = GlobalKey<FormState>();
  final goldenColor = const Color(0xFFD4AF37);
  final techColor = const Color(0xFF1E3A8A);
  final backgroundColor = const Color(0xFFF8F9FA);
  final cardColor = const Color(0xFF0A2463);
  final surfaceColor = const Color(0xFF1E3A8A);

  EventType _selectedType = EventType.treino;
  final _dateController = TextEditingController();
  final _timeController = TextEditingController();
  final _endTimeController = TextEditingController();
  final _opponentController = TextEditingController();
  final _championshipNameController = TextEditingController();
  final _cepController = TextEditingController();
  final _ruaController = TextEditingController();
  final _numeroController = TextEditingController();
  final _bairroController = TextEditingController();
  final _cidadeController = TextEditingController();
  final _estadoController = TextEditingController();

  String _filtroGeneroAtleta = 'Todos';
  String _generoEvento = 'masculino';
  String _filtroPessoa = 'Atleta';
  String _setsFormat = '1 Set';
  String _championshipName = '';

  final Set<String> _selectedAthleteIds = {};
  final Set<String> _selectedTechnicianIds = {};
  bool _isSearchingCep = false;
  bool _enableCheckIn = false;
  bool _enableRideLogistics = false;
  bool _isSaving = false;
  bool _isEditing = false;
  int _automaticAthletesCount = 0;
  String? _eventId;

  List<Map<String, String>> _athletesFromSupabase = [];
  List<Map<String, String>> _techniciansFromSupabase = [];
  bool _isLoadingProfiles = true;

  @override
  void initState() {
    super.initState();
    _fetchProfilesFromSupabase();
    _loadEventData();
  }

  void _loadEventData() async {
    if (widget.evento != null) {
      setState(() {
        _isEditing = true;
        _eventId = widget.evento!['id'];
        final eventType = widget.evento!['event_type'] ?? 'treino';
        if (eventType == 'treino') {
          _selectedType = EventType.treino;
        } else if (eventType == 'amistoso') {
          _selectedType = EventType.amistoso;
        } else if (eventType == 'campeonato') {
          _selectedType = EventType.campeonato;
        }

        final eventName = widget.evento!['event_name'] ?? '';
        if (eventName.contains('Olympus VS ')) {
          _opponentController.text = eventName.replaceFirst('Olympus VS ', '');
        }

        _dateController.text = widget.evento!['event_date'] ?? '';
        _timeController.text = widget.evento!['event_time'] ?? '';
        _endTimeController.text = widget.evento!['event_end_time'] ?? '';
        _setsFormat = widget.evento!['set_format'] ?? '1 Set';
        _cepController.text = widget.evento!['cep'] ?? '';
        _ruaController.text = widget.evento!['street'] ?? '';
        _numeroController.text = widget.evento!['street_number'] ?? '';
        _bairroController.text = widget.evento!['neighborhood'] ?? '';
        _cidadeController.text = widget.evento!['city'] ?? '';
        _estadoController.text = widget.evento!['state'] ?? '';
        _enableCheckIn = widget.evento!['allow_checkin'] ?? false;
        _enableRideLogistics = widget.evento!['enable_ride_logistics'] ?? false;

        _generoEvento = widget.evento!['gender'] ?? 'masculino';
        _championshipName = widget.evento!['championship_name'] ?? '';
        _championshipNameController.text = _championshipName;
      });

      await Future.delayed(const Duration(milliseconds: 500));
      _loadConvocados();
    }
  }

  Future<void> _loadConvocados() async {
    if (_eventId == null) return;

    try {
      final supabase = Supabase.instance.client;
      final convocationsResponse = await supabase
          .from('convocations')
          .select('user_id, event_role')
          .eq('event_id', _eventId!);

      final athleteIds = <String>{};
      final technicianIds = <String>{};

      for (var convocation in convocationsResponse) {
        final userId = convocation['user_id']?.toString();
        if (userId == null || userId.isEmpty) continue;

        final eventRole =
            (convocation['event_role'] ?? 'athlete').toString().toLowerCase();
        if (eventRole == 'coach') {
          technicianIds.add(userId);
          continue;
        }
        athleteIds.add(userId);
      }

      if (mounted) {
        setState(() {
          _selectedAthleteIds
            ..clear()
            ..addAll(athleteIds);
          _selectedTechnicianIds
            ..clear()
            ..addAll(technicianIds);
        });
      }
    } catch (e) {
      print('Erro ao carregar convocados: $e');
    }
  }

  Future<void> _fetchProfilesFromSupabase() async {
    try {
      final supabase = Supabase.instance.client;

      final profilesResponse = await supabase
          .from('profiles')
          .select('id, full_name, user_type, gender, training_weekdays')
          .eq('is_active', true);
      final rolesResponse = await supabase
          .from('user_roles')
          .select('user_id, role')
          .eq('is_active', true);

      final rolesByUser = <String, Set<String>>{};
      for (final row in rolesResponse) {
        final userId = (row['user_id'] ?? '').toString();
        final role = (row['role'] ?? '').toString();
        if (userId.isNotEmpty && role.isNotEmpty) {
          rolesByUser.putIfAbsent(userId, () => <String>{}).add(role);
        }
      }

      bool hasRole(Map<String, dynamic> profile, String role) {
        final id = (profile['id'] ?? '').toString();
        final primary = (profile['user_type'] ?? '').toString();
        return primary == role || (rolesByUser[id]?.contains(role) ?? false);
      }

      final athletesResponse = profilesResponse
          .where((profile) => hasRole(profile, 'athlete'))
          .toList();
      final coachesResponse = profilesResponse
          .where((profile) => hasRole(profile, 'coach'))
          .toList();

      final athletesList = athletesResponse.map<Map<String, String>>((p) {
        return {
          'uid': p['id']?.toString() ?? '',
          'nome': p['full_name'] ?? 'Usuário',
          'genero': _normalizeGenero(p['gender']?.toString()),
          'training_weekdays': (p['training_weekdays'] is List)
              ? (p['training_weekdays'] as List).join(',')
              : '',
        };
      }).toList();

      final techniciansList = coachesResponse.map<Map<String, String>>((p) {
        return {
          'uid': p['id']?.toString() ?? '',
          'nome': p['full_name'] ?? 'Técnico',
          'especialidade': 'Técnico',
        };
      }).toList();

      if (mounted) {
        setState(() {
          _athletesFromSupabase = athletesList;
          _techniciansFromSupabase = techniciansList;
          _isLoadingProfiles = false;
        });
      }

      if (_isEditing && _eventId != null) {
        await _loadConvocados();
      } else {
        _applyAutomaticAthleteSelection();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingProfiles = false);
      }
      _showError('Erro ao carregar perfis: ${e.toString()}');
    }
  }

  List<Map<String, String>> get _athletesList {
    final list = widget.registeredAthletes?.isNotEmpty == true
        ? widget.registeredAthletes!
        : _athletesFromSupabase.isNotEmpty
            ? _athletesFromSupabase
            : _mockAthletes;

    return _sortByName(list);
  }

  List<Map<String, String>> get _techniciansList {
    final list = widget.registeredTechnicians?.isNotEmpty == true
        ? widget.registeredTechnicians!
        : _techniciansFromSupabase.isNotEmpty
            ? _techniciansFromSupabase
            : _mockTechnicians;

    return _sortByName(list);
  }

  static const List<Map<String, String>> _mockAthletes = [
    {'nome': 'Ana Silva', 'genero': 'Feminino'},
    {'nome': 'Beatriz Costa', 'genero': 'Feminino'},
    {'nome': 'Carla Souza', 'genero': 'Feminino'},
    {'nome': 'João Santos', 'genero': 'Masculino'},
    {'nome': 'Pedro Lima', 'genero': 'Masculino'},
    {'nome': 'Lucas Oliveira', 'genero': 'Masculino'},
  ];

  static const List<Map<String, String>> _mockTechnicians = [];

  String _normalizeGenero(String? genero) {
    final valor = (genero ?? '').trim().toLowerCase();

    if (valor == 'feminino' || valor == 'female' || valor == 'f') {
      return 'Feminino';
    }

    if (valor == 'masculino' || valor == 'male' || valor == 'm') {
      return 'Masculino';
    }

    return 'Masculino';
  }

  List<Map<String, String>> _sortByName(List<Map<String, String>> list) {
    final sortedList = List<Map<String, String>>.from(list);
    sortedList.sort((a, b) => (a['nome'] ?? '').toLowerCase().compareTo(
          (b['nome'] ?? '').toLowerCase(),
        ));
    return sortedList;
  }

  @override
  void dispose() {
    _dateController.dispose();
    _timeController.dispose();
    _endTimeController.dispose();
    _opponentController.dispose();
    _championshipNameController.dispose();
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
          if (mounted) {
            setState(() {
              _ruaController.text = data['logradouro'] ?? '';
              _bairroController.text = data['bairro'] ?? '';
              _cidadeController.text = data['localidade'] ?? '';
              _estadoController.text = data['uf'] ?? '';
              _isSearchingCep = false;
            });
          }
          _showSuccess('CEP encontrado com sucesso!');
        } else {
          if (mounted) {
            setState(() => _isSearchingCep = false);
          }
          _showError('CEP não encontrado. Verifique o número digitado.');
        }
      } else {
        if (mounted) {
          setState(() => _isSearchingCep = false);
        }
        _showError('Erro na conexão. Tente novamente.');
      }
    } on TimeoutException {
      if (mounted) {
        setState(() => _isSearchingCep = false);
      }
      _showError('Tempo de resposta excedido. Verifique sua conexão.');
    } catch (e) {
      if (mounted) {
        setState(() => _isSearchingCep = false);
      }
      _showError('Erro ao buscar CEP. Verifique sua conexão com a internet.');
    }
  }

  // ✅ CORREÇÃO: Geocodificação com tratamento de erro robusto
  Future<Map<String, double>?> _geocodeAddress() async {
    try {
      final address = [
        _ruaController.text,
        _numeroController.text,
        _bairroController.text,
        _cidadeController.text,
        _estadoController.text,
        _cepController.text,
      ].where((e) => e.isNotEmpty).join(' ');

      if (address.trim().isEmpty) {
        print('⚠️ Endereço vazio para geocodificação');
        return null;
      }

      print('📍 Geocodificando: $address');

      final url = Uri.parse(
          'https://us1.locationiq.com/v1/search?key=pk.5a7a05184e41c916429dceb50cf02718&q=${Uri.encodeComponent(address)}&format=json&limit=1');

      final response = await http.get(url).timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          print('❌ Timeout na geocodificação');
          throw Exception('Timeout na API de geocodificação');
        },
      );

      print('📡 Status code: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as List;

        if (data.isEmpty) {
          print('❌ Endereço não encontrado na API');
          return null;
        }

        final lat = double.tryParse(data[0]['lat']);
        final lng = double.tryParse(data[0]['lon']);

        if (lat == null || lng == null) {
          print(
              '❌ Coordenadas inválidas: lat=${data[0]['lat']}, lng=${data[0]['lon']}');
          return null;
        }

        print('✅ Coordenadas obtidas: lat=$lat, lng=$lng');
        return {
          'latitude': lat,
          'longitude': lng,
        };
      } else {
        print('❌ Erro HTTP ${response.statusCode}: ${response.body}');
        return null;
      }
    } catch (e) {
      print('❌ Erro na geocodificação: $e');
      return null;
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
      if (mounted) {
        setState(() {
          _dateController.text =
              '${picked.day.toString().padLeft(2, '0')}/${picked.month.toString().padLeft(2, '0')}/${picked.year}';
        });
        _applyAutomaticAthleteSelection();
      }
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
              backgroundColor: Color(0xFFF8F9FA),
              dialBackgroundColor: Color(0xFF0A2463),
              dialTextColor: Colors.white,
              hourMinuteTextColor: Color(0xFF0A2463),
              entryModeIconColor: Color(0xFF0A2463),
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      if (mounted) {
        setState(() {
          _timeController.text = picked.format(context);
        });
      }
    }
  }

  Future<void> _selectEndTime(BuildContext context) async {
    final startParts = _timeController.text.split(':');
    final initial = startParts.length == 2
        ? TimeOfDay(
            hour: int.tryParse(startParts[0]) ?? TimeOfDay.now().hour,
            minute: int.tryParse(startParts[1]) ?? TimeOfDay.now().minute,
          )
        : TimeOfDay.now();
    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: ColorScheme.light(
            primary: goldenColor,
            onPrimary: Colors.white,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null && mounted) {
      setState(() => _endTimeController.text = picked.format(context));
    }
  }

  DateTime? _buildEventStartAt() {
    final dateParts = _dateController.text.trim().split('/');
    final timeParts = _timeController.text.trim().split(':');

    if (dateParts.length != 3 || timeParts.length != 2) {
      return null;
    }

    final day = int.tryParse(dateParts[0]);
    final month = int.tryParse(dateParts[1]);
    final year = int.tryParse(dateParts[2]);
    final hour = int.tryParse(timeParts[0]);
    final minute = int.tryParse(timeParts[1]);

    if (day == null ||
        month == null ||
        year == null ||
        hour == null ||
        minute == null) {
      return null;
    }

    return DateTime(year, month, day, hour, minute);
  }

  List<Map<String, String>> _getFilteredAthletes() {
    if (_filtroGeneroAtleta == 'Todos') return _athletesList;

    return _athletesList
        .where(
          (a) => _normalizeGenero(a['genero']) == _filtroGeneroAtleta,
        )
        .toList();
  }

  DateTime? _selectedEventDate() {
    final parts = _dateController.text.trim().split('/');
    if (parts.length != 3) return null;
    final day = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    final year = int.tryParse(parts[2]);
    if (day == null || month == null || year == null) return null;
    return DateTime(year, month, day);
  }

  Set<int> _athleteTrainingDays(Map<String, String> athlete) {
    return (athlete['training_weekdays'] ?? '')
        .split(',')
        .map((value) => int.tryParse(value.trim()))
        .whereType<int>()
        .toSet();
  }

  void _applyAutomaticAthleteSelection() {
    if (_isEditing || _selectedType != EventType.treino) return;
    final eventDate = _selectedEventDate();
    if (eventDate == null || _isLoadingProfiles) return;

    final expectedGender = _normalizeGenero(_generoEvento);
    final automaticIds = _athletesList
        .where((athlete) {
          final sameGender =
              _normalizeGenero(athlete['genero']) == expectedGender;
          return sameGender &&
              _athleteTrainingDays(athlete).contains(eventDate.weekday);
        })
        .map((athlete) => athlete['uid'] ?? '')
        .where((id) => id.isNotEmpty)
        .toSet();

    if (!mounted) return;
    setState(() {
      _selectedAthleteIds
        ..clear()
        ..addAll(automaticIds);
      _automaticAthletesCount = automaticIds.length;
      _filtroGeneroAtleta = expectedGender;
    });
  }

  void _toggleAthleteSelection(String userId) {
    if (mounted) {
      setState(() {
        if (_selectedAthleteIds.contains(userId)) {
          _selectedAthleteIds.remove(userId);
        } else {
          _selectedTechnicianIds.remove(userId);
          _selectedAthleteIds.add(userId);
        }
      });
    }
  }

  void _toggleTechnicianSelection(String userId) {
    if (mounted) {
      setState(() {
        if (_selectedTechnicianIds.contains(userId)) {
          _selectedTechnicianIds.remove(userId);
        } else {
          final previousCoachIds = _selectedTechnicianIds.toList();
          _selectedTechnicianIds.clear();
          _selectedTechnicianIds.add(userId);
          _selectedAthleteIds.remove(userId);

          for (final previousCoachId in previousCoachIds) {
            final canPlay = _athletesList.any(
              (athlete) => athlete['uid'] == previousCoachId,
            );
            if (canPlay) _selectedAthleteIds.add(previousCoachId);
          }
        }
      });
    }
  }

  // ✅ CORREÇÃO: Validação e salvamento com geocodificação obrigatória
  Future<void> _salvarEvento() async {
    if (!_formKey.currentState!.validate()) return;

    if (_selectedType == EventType.campeonato &&
        _championshipNameController.text.trim().isEmpty) {
      _showError('Informe o nome do campeonato');
      return;
    }

    // ✅ VALIDAR SE ENDEREÇO ESTÁ PREENCHIDO
    if (_ruaController.text.isEmpty ||
        _numeroController.text.isEmpty ||
        _bairroController.text.isEmpty ||
        _cidadeController.text.isEmpty ||
        _estadoController.text.isEmpty) {
      _showError('Preencha todos os campos de endereço obrigatórios');
      return;
    }

    setState(() => _isSaving = true);

    try {
      // ✅ 1. Geocodificar endereço (OBRIGATÓRIO)
      _showSuccess('📡 Geocodificando endereço...');
      final coords = await _geocodeAddress();

      if (coords == null) {
        setState(() => _isSaving = false);
        _showError(
          '❌ Não foi possível obter as coordenadas do endereço.\n\n'
          'Verifique se:\n'
          '• O endereço está correto e completo\n'
          '• Você tem conexão com internet\n'
          '• O CEP é válido\n\n'
          'Tente buscar o CEP novamente ou corrija o endereço.',
        );
        return;
      }

      print(
          '✅ Geocodificação concluída: ${coords['latitude']}, ${coords['longitude']}');

      final supabase = Supabase.instance.client;
      final user = supabase.auth.currentUser;

      if (user == null) {
        if (mounted) {
          setState(() => _isSaving = false);
        }
        _showError('Usuário não autenticado');
        return;
      }

      final eventStartAt = _buildEventStartAt();

      if (eventStartAt == null) {
        if (mounted) {
          setState(() => _isSaving = false);
        }
        _showError('Data ou hora do evento inválida');
        return;
      }

      if (_endTimeController.text.trim().isEmpty) {
        if (mounted) setState(() => _isSaving = false);
        _showError('Informe o horário de término do evento');
        return;
      }

      final endParts = _endTimeController.text.trim().split(':');
      final endHour = endParts.length == 2 ? int.tryParse(endParts[0]) : null;
      final endMinute = endParts.length == 2 ? int.tryParse(endParts[1]) : null;
      if (endHour == null || endMinute == null) {
        if (mounted) setState(() => _isSaving = false);
        _showError('Horário de término inválido');
        return;
      }
      final eventEndAt = DateTime(
        eventStartAt.year,
        eventStartAt.month,
        eventStartAt.day,
        endHour,
        endMinute,
      );
      if (!eventEndAt.isAfter(eventStartAt)) {
        if (mounted) setState(() => _isSaving = false);
        _showError('O término deve ser posterior ao início do evento');
        return;
      }

      final eventData = {
        'user_id': user.id,
        'event_name': _opponentController.text.isNotEmpty
            ? 'Olympus VS ${_opponentController.text}'
            : 'Evento ${_selectedType.name}',
        'event_type': _selectedType.name,
        'event_date': _dateController.text,
        'event_time': _timeController.text,
        'event_end_time': _endTimeController.text,
        'event_start_at': eventStartAt.toUtc().toIso8601String(),
        'cep': _cepController.text,
        'street': _ruaController.text,
        'street_number': _numeroController.text,
        'neighborhood': _bairroController.text,
        'city': _cidadeController.text,
        'state': _estadoController.text,
        'set_format': _setsFormat,
        'allow_checkin': _enableCheckIn,
        'enable_ride_logistics': _selectedType == EventType.campeonato
            ? _enableRideLogistics
            : false,
        'gender': _generoEvento,
        'championship_name': _selectedType == EventType.campeonato
            ? _championshipNameController.text.trim()
            : null,
        // ✅ 2. Incluir coordenadas OBRIGATORIAMENTE
        'latitude': coords['latitude'],
        'longitude': coords['longitude'],
      };

      dynamic response;

      if (_isEditing && _eventId != null) {
        response = await supabase
            .from('events')
            .update(eventData)
            .eq('id', _eventId!)
            .select();
      } else {
        eventData['created_at'] = DateTime.now().toIso8601String();
        response = await supabase.from('events').insert(eventData).select();
      }

      if (response.isEmpty) {
        throw Exception(
            'Falha ao ${_isEditing ? 'atualizar' : 'criar'} evento');
      }

      final eventId = response[0]['id'];

      final selectedRoles = <String, String>{
        for (final userId in _selectedAthleteIds) userId: 'athlete',
        for (final userId in _selectedTechnicianIds) userId: 'coach',
      };
      final selectedUserIds = selectedRoles.keys.toSet();

      final existingConvocations = await supabase
          .from('convocations')
          .select('user_id')
          .eq('event_id', eventId);

      final existingUserIds = existingConvocations
          .map<String>((c) => c['user_id'].toString())
          .toSet();

      final userIdsToDelete = existingUserIds.difference(selectedUserIds);

      if (userIdsToDelete.isNotEmpty) {
        await supabase
            .from('convocations')
            .delete()
            .eq('event_id', eventId)
            .inFilter('user_id', userIdsToDelete.toList());
      }

      if (selectedRoles.isNotEmpty) {
        final convocations = selectedRoles.entries
            .map((entry) => {
                  'event_id': eventId,
                  'user_id': entry.key,
                  'event_role': entry.value,
                  'status':
                      existingUserIds.contains(entry.key) ? null : 'pending',
                })
            .toList();

        for (final convocation in convocations) {
          final status = convocation.remove('status');
          final data = {
            ...convocation,
            if (status != null) 'status': status,
          };
          await supabase.from('convocations').upsert(
                data,
                onConflict: 'event_id,user_id',
              );
        }
      }

// ==========================================================
// DISPARA A EDGE FUNCTION PARA ENVIAR AS NOTIFICAÇÕES
// ==========================================================

      try {
        final notificationResponse = await supabase.functions.invoke(
          'send-event-notification',
          body: {
            'eventId': eventId,
          },
        );

        debugPrint("==========================================");
        debugPrint("SEND EVENT NOTIFICATION");
        debugPrint(notificationResponse.data.toString());
        debugPrint("==========================================");
      } catch (e) {
        debugPrint("==========================================");
        debugPrint("ERRO AO CHAMAR send-event-notification");
        debugPrint(e.toString());
        debugPrint("==========================================");
      }

      if (mounted) {
        setState(() => _isSaving = false);
      }

      if (!mounted) return;

      final totalConvocados =
          _selectedAthleteIds.length + _selectedTechnicianIds.length;
      _showSuccess(
        '✅ Evento ${_isEditing ? 'atualizado' : 'salvo'} com sucesso!\n'
        '$totalConvocados convocados registrados'
        '${_enableCheckIn ? ' • Check-in habilitado' : ''}\n'
        '📍 Coordenadas: ${coords['latitude']!.toStringAsFixed(6)}, ${coords['longitude']!.toStringAsFixed(6)}',
      );

      await Future.delayed(const Duration(milliseconds: 500));

      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
      }
      _showError(
          'Erro ao ${_isEditing ? 'atualizar' : 'salvar'} evento: ${e.toString()}');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.event, color: Color(0xFFD4AF37)),
            SizedBox(width: 8),
            Text(
              'Novo Evento',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.white,
                fontFamily: 'Roboto',
                fontSize: 20,
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF1E3A5F),
        foregroundColor: Colors.white,
        elevation: 2,
      ),
      body: Form(
        key: _formKey,
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildFormCard(
                    icon: Icons.event_note_rounded,
                    title: 'Dados do evento',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildEventTypeSelector(),
                        const SizedBox(height: 18),
                        _buildGenderSelector(),
                        if (_selectedType == EventType.campeonato) ...[
                          const SizedBox(height: 18),
                          _buildChampionshipNameField(),
                          const SizedBox(height: 16),
                          _buildRideLogisticsOption(),
                        ],
                        if (_selectedType == EventType.amistoso ||
                            _selectedType == EventType.campeonato) ...[
                          const SizedBox(height: 18),
                          _buildOpponentField(),
                          const SizedBox(height: 16),
                          _buildSetsFormatSelector(),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildFormCard(
                    icon: Icons.schedule_rounded,
                    title: 'Data e horário',
                    child: _buildResponsiveDateTimeFields(),
                  ),
                  const SizedBox(height: 16),
                  _buildFormCard(
                    icon: Icons.groups_rounded,
                    title: 'Convocação',
                    child: _buildConvocationSection(),
                  ),
                  const SizedBox(height: 16),
                  _buildFormCard(
                    icon: Icons.location_on_outlined,
                    title: 'Local e acesso',
                    child: Column(
                      children: [
                        _buildAddressSection(),
                        const SizedBox(height: 16),
                        _buildCheckInOption(),
                      ],
                    ),
                  ),
                  const SizedBox(height: 80),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 8,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: SafeArea(
                child: SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _isSaving ? null : _salvarEvento,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: goldenColor,
                      foregroundColor: const Color(0xFF0A2463),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                    ),
                    child: _isSaving
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                  Color(0xFF0A2463)),
                            ),
                          )
                        : Text(
                            _isEditing ? 'Atualizar Evento' : 'Salvar Evento',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGenderSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Gênero do Evento',
          style: TextStyle(
            color: Color(0xFF0A2463),
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: _buildGenderChip('masculino', 'Masculino')),
            const SizedBox(width: 8),
            Expanded(child: _buildGenderChip('feminino', 'Feminino')),
          ],
        ),
      ],
    );
  }

  Widget _buildGenderChip(String value, String label) {
    final isSelected = _generoEvento == value;
    return GestureDetector(
      onTap: () {
        if (mounted) {
          setState(() => _generoEvento = value);
          _applyAutomaticAthleteSelection();
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? goldenColor : Colors.grey[200],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? Colors.transparent
                : const Color(0xFF0A2463).withOpacity(0.3),
          ),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color:
                isSelected ? const Color(0xFF0A2463) : const Color(0xFF0A2463),
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildChampionshipNameField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Nome do Campeonato/Liga',
          style: TextStyle(
            color: Color(0xFF0A2463),
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: Colors.grey[100],
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF0A2463).withOpacity(0.3)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextFormField(
            controller: _championshipNameController,
            style: const TextStyle(color: Color(0xFF0A2463)),
            decoration: const InputDecoration(
              hintText: 'Ex: Liga de Jundiaí, Campeonato Paulista...',
              hintStyle: TextStyle(color: Colors.grey),
              border: InputBorder.none,
              prefixIcon: Icon(Icons.emoji_events, color: Color(0xFFD4AF37)),
            ),
            onChanged: (value) {
              setState(() {
                _championshipName = value;
              });
            },
          ),
        ),
      ],
    );
  }

  Widget _buildRideLogisticsOption() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _enableRideLogistics
            ? goldenColor.withOpacity(0.1)
            : Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _enableRideLogistics
              ? goldenColor
              : const Color(0xFF0A2463).withOpacity(0.2),
          width: _enableRideLogistics ? 2 : 1,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.directions_car_filled_rounded,
                      color: _enableRideLogistics ? goldenColor : Colors.grey,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Habilitar logística de carona',
                      style: TextStyle(
                        color: _enableRideLogistics
                            ? const Color(0xFF0A2463)
                            : Colors.grey[600],
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Quando ativado, atletas verão a opção de responder ida e volta ao aceitar a convocação.',
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: _enableRideLogistics,
            onChanged: (value) {
              if (mounted) {
                setState(() {
                  _enableRideLogistics = value;
                });
              }
            },
            activeColor: goldenColor,
            activeTrackColor: goldenColor.withOpacity(0.5),
          ),
        ],
      ),
    );
  }

  Widget _buildCheckInOption() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _enableCheckIn ? goldenColor.withOpacity(0.1) : Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _enableCheckIn
              ? goldenColor
              : const Color(0xFF0A2463).withOpacity(0.2),
          width: _enableCheckIn ? 2 : 1,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.check_circle_outline,
                      color: _enableCheckIn ? goldenColor : Colors.grey,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Habilitar Check-in',
                      style: TextStyle(
                        color: _enableCheckIn
                            ? const Color(0xFF0A2463)
                            : Colors.grey[600],
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Convocados confirmarão presença via GPS no local',
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: _enableCheckIn,
            onChanged: (value) {
              if (mounted) {
                setState(() {
                  _enableCheckIn = value;
                });
              }
            },
            activeColor: goldenColor,
            activeTrackColor: goldenColor.withOpacity(0.5),
          ),
        ],
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
            color: Color(0xFF0A2463),
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _buildEventTypeChip('Treino', EventType.treino),
            _buildEventTypeChip('Amistoso', EventType.amistoso),
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
          color: isSelected ? const Color(0xFF0A2463) : const Color(0xFF0A2463),
          fontSize: 13,
        ),
      ),
      selected: isSelected,
      onSelected: (selected) {
        if (mounted) {
          setState(() => _selectedType = type);
          if (type == EventType.treino) {
            _applyAutomaticAthleteSelection();
          } else {
            setState(() => _automaticAthletesCount = 0);
          }
        }
      },
      backgroundColor: Colors.grey[200],
      selectedColor: goldenColor,
      checkmarkColor: const Color(0xFF0A2463),
      labelStyle: const TextStyle(color: Colors.white),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: isSelected
              ? Colors.transparent
              : const Color(0xFF0A2463).withOpacity(0.3),
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
            color: Color(0xFF0A2463),
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: Colors.grey[100],
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF0A2463).withOpacity(0.3)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextFormField(
            controller: _opponentController,
            style: const TextStyle(color: Color(0xFF0A2463)),
            decoration: const InputDecoration(
              hintText: 'Digite o nome do adversário',
              hintStyle: TextStyle(color: Colors.grey),
              border: InputBorder.none,
              prefixText: 'Olympus VS ',
              prefixStyle: TextStyle(color: Color(0xFFD4AF37)),
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
            color: Color(0xFF0A2463),
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 80,
          child: Row(
            children: [
              Expanded(child: _buildSetChip('1 Set', 'Vencedor único')),
              const SizedBox(width: 8),
              Expanded(child: _buildSetChip('3 Sets', 'Melhor de 3')),
              const SizedBox(width: 8),
              Expanded(child: _buildSetChip('5 Sets', 'Melhor de 5')),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSetChip(String label, String description) {
    final isSelected = _setsFormat == label;
    return GestureDetector(
      onTap: () {
        if (mounted) {
          setState(() => _setsFormat = label);
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? goldenColor : Colors.grey[100],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? Colors.transparent
                : const Color(0xFF0A2463).withOpacity(0.3),
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: isSelected
                    ? const Color(0xFF0A2463)
                    : const Color(0xFF0A2463),
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              description,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: isSelected
                    ? const Color(0xFF0A2463).withOpacity(0.8)
                    : Colors.grey[600],
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Mantido temporariamente para compatibilidade com personalizações antigas.
  // ignore: unused_element
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
                  color: Color(0xFF0A2463),
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
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: const Color(0xFF0A2463).withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.calendar_today,
                          color: Color(0xFFD4AF37), size: 18),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _dateController.text.isEmpty
                              ? 'Selecione a data'
                              : _dateController.text,
                          style: TextStyle(
                            color: _dateController.text.isEmpty
                                ? Colors.grey[500]
                                : const Color(0xFF0A2463),
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
                'Início',
                style: TextStyle(
                  color: Color(0xFF0A2463),
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
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: const Color(0xFF0A2463).withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.access_time,
                          color: Color(0xFFD4AF37), size: 18),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _timeController.text.isEmpty
                              ? 'Selecione a hora'
                              : _timeController.text,
                          style: TextStyle(
                            color: _timeController.text.isEmpty
                                ? Colors.grey[500]
                                : const Color(0xFF0A2463),
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
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Término',
                style: TextStyle(
                  color: Color(0xFF0A2463),
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: () => _selectEndTime(context),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: const Color(0xFF0A2463).withOpacity(0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.timer_outlined,
                        color: Color(0xFFD4AF37),
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _endTimeController.text.isEmpty
                              ? '--:--'
                              : _endTimeController.text,
                          style: TextStyle(
                            color: _endTimeController.text.isEmpty
                                ? Colors.grey[500]
                                : const Color(0xFF0A2463),
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

  Widget _buildAutomaticSelectionSummary() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: goldenColor.withOpacity(0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: goldenColor.withOpacity(0.45)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.auto_awesome_rounded,
            color: Color(0xFF0A2463),
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '$_automaticAthletesCount atleta(s) carregado(s) automaticamente para este dia.',
              style: const TextStyle(
                color: Color(0xFF0A2463),
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Recarregar escala',
            onPressed: _applyAutomaticAthleteSelection,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
    );
  }

  Widget _buildFormCard({
    required IconData icon,
    required String title,
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE1E8F0)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x120A2463),
            blurRadius: 16,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: goldenColor.withOpacity(0.16),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: cardColor, size: 21),
              ),
              const SizedBox(width: 10),
              Text(
                title,
                style: const TextStyle(
                  color: Color(0xFF0A2463),
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }

  Widget _buildResponsiveDateTimeFields() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 520;
        final dateWidth =
            compact ? constraints.maxWidth : (constraints.maxWidth - 24) / 3;
        final timeWidth = compact
            ? (constraints.maxWidth - 10) / 2
            : (constraints.maxWidth - 24) / 3;

        return Wrap(
          spacing: compact ? 10 : 12,
          runSpacing: 14,
          children: [
            SizedBox(
              width: dateWidth,
              child: _buildDateTimeBox(
                label: 'Data',
                value: _dateController.text,
                placeholder: 'Selecione a data',
                icon: Icons.calendar_today_rounded,
                onTap: () => _selectDate(context),
              ),
            ),
            SizedBox(
              width: timeWidth,
              child: _buildDateTimeBox(
                label: 'Início',
                value: _timeController.text,
                placeholder: '--:--',
                icon: Icons.access_time_rounded,
                onTap: () => _selectTime(context),
              ),
            ),
            SizedBox(
              width: timeWidth,
              child: _buildDateTimeBox(
                label: 'Término',
                value: _endTimeController.text,
                placeholder: '--:--',
                icon: Icons.timer_outlined,
                onTap: () => _selectEndTime(context),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildDateTimeBox({
    required String label,
    required String value,
    required String placeholder,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF0A2463),
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 7),
        Material(
          color: const Color(0xFFF5F8FC),
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFD8E2ED)),
              ),
              child: Row(
                children: [
                  Icon(icon, color: goldenColor, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      value.isEmpty ? placeholder : value,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: value.isEmpty
                            ? Colors.grey.shade500
                            : const Color(0xFF0A2463),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
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
            color: Color(0xFF0A2463),
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),
        if (_selectedType == EventType.treino &&
            _selectedEventDate() != null) ...[
          _buildAutomaticSelectionSummary(),
          const SizedBox(height: 12),
        ],
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
              Text('Gênero: ',
                  style: TextStyle(color: Colors.grey[600], fontSize: 14)),
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
        if (_isLoadingProfiles)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(32.0),
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFD4AF37)),
              ),
            ),
          )
        else
          Container(
            constraints: const BoxConstraints(maxHeight: 200),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: BorderRadius.circular(12),
              border:
                  Border.all(color: const Color(0xFF0A2463).withOpacity(0.2)),
            ),
            child: ListView(
              padding: const EdgeInsets.all(8),
              children: _filtroPessoa == 'Atleta'
                  ? _getFilteredAthletes().map((athlete) {
                      final athleteId = athlete['uid'] ?? '';
                      return _buildPersonTile(
                        name: athlete['nome']!,
                        subtitle: athlete['genero'],
                        avatarUrl: athlete['avatar_url'],
                        isSelected: _selectedAthleteIds.contains(athleteId),
                        onToggle: athleteId.isEmpty
                            ? null
                            : () => _toggleAthleteSelection(athleteId),
                      );
                    }).toList()
                  : _techniciansList.map((tech) {
                      final technicianId = tech['uid'] ?? '';
                      return _buildPersonTile(
                        name: tech['nome']!,
                        subtitle: tech['especialidade'],
                        avatarUrl: tech['avatar_url'],
                        isSelected:
                            _selectedTechnicianIds.contains(technicianId),
                        onToggle: technicianId.isEmpty
                            ? null
                            : () => _toggleTechnicianSelection(technicianId),
                      );
                    }).toList(),
            ),
          ),
        if (_selectedAthleteIds.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _athletesList
                .where(
                    (athlete) => _selectedAthleteIds.contains(athlete['uid']))
                .map((athlete) {
              final athleteId = athlete['uid'] ?? '';
              final athleteName = athlete['nome'] ?? '';
              return Chip(
                label: Text(athleteName,
                    style: const TextStyle(
                        fontSize: 12, color: Color(0xFF0A2463))),
                backgroundColor: goldenColor.withOpacity(0.3),
                side: const BorderSide(color: Color(0xFFD4AF37), width: 1),
                deleteIcon:
                    const Icon(Icons.close, size: 16, color: Color(0xFF0A2463)),
                onDeleted: athleteId.isEmpty
                    ? null
                    : () => _toggleAthleteSelection(athleteId),
              );
            }).toList(),
          ),
        ],
        if (_selectedTechnicianIds.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _techniciansList
                .where((tech) => _selectedTechnicianIds.contains(tech['uid']))
                .map((tech) {
              final technicianId = tech['uid'] ?? '';
              final technicianName = tech['nome'] ?? '';
              return Chip(
                label: Text(technicianName,
                    style: const TextStyle(fontSize: 12, color: Colors.white)),
                backgroundColor: techColor.withOpacity(0.3),
                side: const BorderSide(color: Color(0xFF1E3A8A), width: 1),
                deleteIcon:
                    const Icon(Icons.close, size: 16, color: Colors.white),
                onDeleted: technicianId.isEmpty
                    ? null
                    : () => _toggleTechnicianSelection(technicianId),
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
      onTap: () {
        if (mounted) {
          setState(() => _filtroPessoa = value);
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? goldenColor : Colors.grey[200],
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(12),
            topRight: Radius.circular(12),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color:
                isSelected ? const Color(0xFF0A2463) : const Color(0xFF0A2463),
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
      ),
    );
  }

  Widget _buildGenderFilterChip(String label) {
    final isSelected = _filtroGeneroAtleta == label;
    return FilterChip(
      label: Text(
        label,
        style: TextStyle(
          color: isSelected ? const Color(0xFF0A2463) : const Color(0xFF0A2463),
          fontSize: 12,
        ),
      ),
      selected: isSelected,
      onSelected: (selected) {
        if (mounted) {
          setState(() => _filtroGeneroAtleta = label);
        }
      },
      backgroundColor: Colors.grey[200],
      selectedColor: goldenColor,
      labelStyle: const TextStyle(color: Colors.white),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isSelected
              ? Colors.transparent
              : const Color(0xFF0A2463).withOpacity(0.3),
        ),
      ),
    );
  }

  Widget _buildPersonTile({
    required String name,
    required String? subtitle,
    required String? avatarUrl,
    required bool isSelected,
    required VoidCallback? onToggle,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      leading: CircleAvatar(
        radius: 20,
        backgroundColor: goldenColor.withOpacity(0.2),
        backgroundImage: avatarUrl != null && avatarUrl.isNotEmpty
            ? NetworkImage(avatarUrl)
            : null,
        child: avatarUrl == null || avatarUrl.isEmpty
            ? Icon(Icons.person, color: goldenColor, size: 20)
            : null,
      ),
      title: Text(name,
          style: const TextStyle(color: Color(0xFF0A2463), fontSize: 14)),
      subtitle: subtitle != null
          ? Text(subtitle,
              style: TextStyle(color: Colors.grey[600], fontSize: 12))
          : null,
      trailing: Checkbox(
        value: isSelected,
        onChanged: onToggle == null ? null : (_) => onToggle(),
        activeColor: goldenColor,
        checkColor: Colors.white,
        side: BorderSide(color: const Color(0xFF0A2463).withOpacity(0.5)),
      ),
    );
  }

  Widget _buildAddressSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Local do Evento',
          style: TextStyle(
            color: Color(0xFF0A2463),
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _cepController,
          style: const TextStyle(color: Color(0xFF0A2463)),
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(8),
          ],
          decoration: InputDecoration(
            labelText: 'CEP',
            labelStyle: TextStyle(color: Colors.grey[600]),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide:
                  BorderSide(color: const Color(0xFF0A2463).withOpacity(0.3)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide:
                  BorderSide(color: const Color(0xFF0A2463).withOpacity(0.3)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFD4AF37)),
            ),
            prefixIcon: const Icon(Icons.location_on, color: Color(0xFFD4AF37)),
            suffixIcon: _isSearchingCep
                ? const Padding(
                    padding: EdgeInsets.all(12.0),
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          Color(0xFFD4AF37),
                        ),
                      ),
                    ),
                  )
                : IconButton(
                    icon: const Icon(Icons.search, color: Color(0xFFD4AF37)),
                    onPressed: () => _buscarCep(_cepController.text),
                  ),
            filled: true,
            fillColor: Colors.grey[50],
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
          style: const TextStyle(color: Color(0xFF0A2463)),
          decoration: InputDecoration(
            labelText: 'Rua',
            labelStyle: TextStyle(color: Colors.grey[600]),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide:
                  BorderSide(color: const Color(0xFF0A2463).withOpacity(0.3)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide:
                  BorderSide(color: const Color(0xFF0A2463).withOpacity(0.3)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFD4AF37)),
            ),
            prefixIcon: const Icon(Icons.streetview, color: Color(0xFFD4AF37)),
            filled: true,
            fillColor: Colors.grey[50],
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
                style: const TextStyle(color: Color(0xFF0A2463)),
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Número',
                  labelStyle: TextStyle(color: Colors.grey[600]),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                        color: const Color(0xFF0A2463).withOpacity(0.3)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                        color: const Color(0xFF0A2463).withOpacity(0.3)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFFD4AF37)),
                  ),
                  filled: true,
                  fillColor: Colors.grey[50],
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
                style: const TextStyle(color: Color(0xFF0A2463)),
                decoration: InputDecoration(
                  labelText: 'Bairro',
                  labelStyle: TextStyle(color: Colors.grey[600]),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                        color: const Color(0xFF0A2463).withOpacity(0.3)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                        color: const Color(0xFF0A2463).withOpacity(0.3)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFFD4AF37)),
                  ),
                  filled: true,
                  fillColor: Colors.grey[50],
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
                style: const TextStyle(color: Color(0xFF0A2463)),
                decoration: InputDecoration(
                  labelText: 'Cidade',
                  labelStyle: TextStyle(color: Colors.grey[600]),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                        color: const Color(0xFF0A2463).withOpacity(0.3)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                        color: const Color(0xFF0A2463).withOpacity(0.3)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFFD4AF37)),
                  ),
                  filled: true,
                  fillColor: Colors.grey[50],
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
                style: const TextStyle(color: Color(0xFF0A2463)),
                maxLength: 2,
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(
                  labelText: 'UF',
                  labelStyle: TextStyle(color: Colors.grey[600]),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                        color: const Color(0xFF0A2463).withOpacity(0.3)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                        color: const Color(0xFF0A2463).withOpacity(0.3)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFFD4AF37)),
                  ),
                  counterText: '',
                  filled: true,
                  fillColor: Colors.grey[50],
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
