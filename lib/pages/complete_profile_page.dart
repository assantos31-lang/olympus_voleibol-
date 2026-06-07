import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_masked_text2/flutter_masked_text2.dart';
import 'dart:convert';
import 'dart:typed_data';

class CompleteProfilePage extends StatefulWidget {
  const CompleteProfilePage({super.key});

  @override
  State<CompleteProfilePage> createState() => _CompleteProfilePageState();
}

class _CompleteProfilePageState extends State<CompleteProfilePage> {
  final _formKey = GlobalKey<FormState>();
  final _picker = ImagePicker();
  final supabase = Supabase.instance.client;

  final _fullNameController = TextEditingController();
  final _phoneController = MaskedTextController(mask: '(00) 00000-0000');
  final _birthDateController = TextEditingController();
  final _rgController = MaskedTextController(mask: '00.000.000-0');
  final _cpfController = MaskedTextController(mask: '000.000.000-00');
  final _zipCodeController = MaskedTextController(mask: '00000-000');
  final _streetController = TextEditingController();
  final _streetNumberController = TextEditingController();
  final _complementController = TextEditingController();
  final _neighborhoodController = TextEditingController();
  final _cityController = TextEditingController();
  final _stateController = TextEditingController();

  String _selectedGender = '';
  String _selectedPosition = '';
  String _existingAvatarUrl = '';
  XFile? _selectedImage;
  bool _isLoading = false;
  bool _isFetchingCep = false;
  bool _isUploading = false;

  // 🔹 LocationIQ API Key (substitua pelo seu token)
  final String _locationIQToken = 'pk.5a7a05184e41c916429dceb50cf02718';

  final Map<String, List<Map<String, String>>> _positions = {
    'Masculino': [
      {'value': 'Ponteiro', 'label': 'Ponteiro'},
      {'value': 'Levantador', 'label': 'Levantador'},
      {'value': 'Central', 'label': 'Central'},
      {'value': 'Oposto', 'label': 'Oposto'},
      {'value': 'Líbero', 'label': 'Líbero'},
    ],
    'Feminino': [
      {'value': 'Ponteira', 'label': 'Ponteira'},
      {'value': 'Levantadora', 'label': 'Levantadora'},
      {'value': 'Central', 'label': 'Central'},
      {'value': 'Oposta', 'label': 'Oposta'},
      {'value': 'Líbero', 'label': 'Líbero'},
    ],
  };

  @override
  void initState() {
    super.initState();
    _zipCodeController.addListener(_onZipCodeChanged);
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    final user = supabase.auth.currentUser;
    if (user != null) {
      final profile = await supabase
          .from('profiles')
          .select()
          .eq('id', user.id)
          .maybeSingle();

      if (profile != null && mounted) {
        setState(() {
          _fullNameController.text = profile['full_name'] ?? '';
          _phoneController.text = profile['phone'] ?? '';
          _birthDateController.text = profile['birth_date'] ?? '';
          _rgController.text = profile['rg'] ?? '';
          _cpfController.text = profile['cpf'] ?? '';
          _zipCodeController.text = profile['zip_code'] ?? '';
          _streetController.text = profile['street'] ?? '';
          _streetNumberController.text = profile['street_number'] ?? '';
          _complementController.text = profile['complement'] ?? '';
          _neighborhoodController.text = profile['neighborhood'] ?? '';
          _cityController.text = profile['city'] ?? '';
          _stateController.text = profile['state'] ?? '';
          _selectedGender = profile['gender'] ?? '';
          _selectedPosition = profile['court_position'] ?? '';
          _existingAvatarUrl = profile['avatar_url'] ?? '';
        });
      }
    }
  }

  void _onZipCodeChanged() {
    final cep = _zipCodeController.text.replaceAll(RegExp(r'\D'), '');
    if (cep.length == 8 && !_isFetchingCep) {
      _fetchAddressByCep(cep);
    }
  }

  Future<void> _fetchAddressByCep(String cep) async {
    setState(() => _isFetchingCep = true);

    try {
      // 🔹 Tentativa 1: ViaCEP (gratuito, sem token)
      debugPrint('🔍 Buscando CEP $cep via ViaCEP...');
      final viaCepSuccess = await _tryViaCep(cep);

      if (!viaCepSuccess) {
        // 🔹 Tentativa 2: LocationIQ (fallback)
        debugPrint('⚠️ ViaCEP falhou. Tentando LocationIQ...');
        final locationIQSuccess = await _tryLocationIQ(cep);

        if (!locationIQSuccess) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('❌ CEP não encontrado em nenhuma base de dados'),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
      }
    } catch (e) {
      debugPrint('❌ Erro ao buscar CEP: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('❌ Erro de conexão. Verifique sua internet.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isFetchingCep = false);
      }
    }
  }

  /// 🔹 ViaCEP - API gratuita para CEPs brasileiros
  Future<bool> _tryViaCep(String cep) async {
    try {
      final response = await http
          .get(Uri.parse('https://viacep.com.br/ws/$cep/json/'))
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        // Verifica se CEP é válido
        if (data['erro'] == true) {
          debugPrint('❌ ViaCEP: CEP não encontrado');
          return false;
        }

        // Preenche os campos
        if (mounted) {
          setState(() {
            _streetController.text = data['logradouro'] ?? '';
            _neighborhoodController.text = data['bairro'] ?? '';
            _cityController.text = data['localidade'] ?? '';
            _stateController.text = data['uf'] ?? '';
          });

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ Endereço encontrado via ViaCEP!'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 2),
            ),
          );
        }

        debugPrint('✅ ViaCEP: Endereço encontrado com sucesso!');
        return true;
      }

      return false;
    } catch (e) {
      debugPrint('❌ ViaCEP: Erro de conexão - $e');
      return false;
    }
  }

  /// 🔹 LocationIQ - Fallback quando ViaCEP falha
  Future<bool> _tryLocationIQ(String cep) async {
    try {
      // Formata CEP para formato brasileiro (com hífen)
      final formattedCep = '${cep.substring(0, 5)}-${cep.substring(5)}';

      final response = await http
          .get(Uri.parse('https://us1.locationiq.com/v1/search.php'
              '?key=$_locationIQToken'
              '&postalcode=$formattedCep'
              '&format=json'
              '&addressdetails=1'))
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if (data is List && data.isNotEmpty) {
          final address = data[0]['address'];

          if (mounted) {
            setState(() {
              _streetController.text = address['road'] ??
                  address['pedestrian'] ??
                  address['footway'] ??
                  '';
              _neighborhoodController.text = address['suburb'] ??
                  address['neighbourhood'] ??
                  address['quarter'] ??
                  '';
              _cityController.text = address['city'] ??
                  address['town'] ??
                  address['village'] ??
                  address['municipality'] ??
                  '';
              _stateController.text = address['state'] ?? '';
            });

            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('✅ Endereço encontrado via LocationIQ!'),
                backgroundColor: Colors.orange,
                duration: Duration(seconds: 2),
              ),
            );
          }

          debugPrint('✅ LocationIQ: Endereço encontrado com sucesso!');
          return true;
        }

        debugPrint('❌ LocationIQ: Nenhum resultado encontrado');
        return false;
      }

      return false;
    } catch (e) {
      debugPrint('❌ LocationIQ: Erro de conexão - $e');
      return false;
    }
  }

  Future<void> _pickImage() async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 85,
      );
      if (image != null && mounted) {
        setState(() {
          _selectedImage = image;
        });
      }
    } catch (e) {
      debugPrint('Erro ao selecionar imagem: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Erro ao selecionar imagem'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<String?> _uploadImage() async {
    if (_selectedImage == null) return null;

    setState(() => _isUploading = true);

    try {
      final user = supabase.auth.currentUser;
      final fileName =
          '${DateTime.now().millisecondsSinceEpoch}_${user?.id}.jpg';
      final Uint8List? fileBytes = await _selectedImage!.readAsBytes();
      if (fileBytes == null) return null;

      await supabase.storage.from('avatars').uploadBinary(fileName, fileBytes,
          fileOptions: const FileOptions(upsert: true));

      final publicUrl = supabase.storage.from('avatars').getPublicUrl(fileName);
      return publicUrl;
    } catch (e) {
      debugPrint('Erro ao fazer upload: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao fazer upload: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return null;
    } finally {
      if (mounted) {
        setState(() => _isUploading = false);
      }
    }
  }

  Future<void> _selectDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
    );
    if (picked != null && mounted) {
      setState(() {
        _birthDateController.text = DateFormat('yyyy-MM-dd').format(picked);
      });
    }
  }

  String _removeMask(String? text) {
    if (text == null || text.isEmpty) return '';
    return text.replaceAll(RegExp(r'\D'), '');
  }

  bool _isFullName(String value) {
    final name = value.trim();

    if (name.isEmpty) return false;

    final parts = name
        .split(RegExp(r'\s+'))
        .where((part) => part.trim().isNotEmpty)
        .toList();

    if (parts.length < 2) return false;

    final validNamePattern = RegExp(r"^[A-Za-zÀ-ÖØ-öø-ÿ' -]+$");
    if (!validNamePattern.hasMatch(name)) return false;

    return parts.every((part) => part.trim().length >= 2);
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;

    if (!_isFullName(_fullNameController.text)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Informe nome completo válido (nome e sobrenome)'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (_selectedImage == null && _existingAvatarUrl.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Selecione uma foto para continuar'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      String? avatarUrl = _existingAvatarUrl;
      if (_selectedImage != null) {
        avatarUrl = await _uploadImage();
      }

      final user = supabase.auth.currentUser;
      if (user == null) throw Exception('Usuário não autenticado');

      final data = <String, dynamic>{
        'full_name': _fullNameController.text.trim(),
        'phone': _removeMask(_phoneController.text),
        'birth_date': _birthDateController.text,
        'rg': _removeMask(_rgController.text),
        'cpf': _removeMask(_cpfController.text),
        'gender': _selectedGender,
        'court_position': _selectedPosition,
        'zip_code': _removeMask(_zipCodeController.text),
        'street': _streetController.text.trim(),
        'street_number': _streetNumberController.text.trim(),
        'complement': _complementController.text.trim(),
        'neighborhood': _neighborhoodController.text.trim(),
        'city': _cityController.text.trim(),
        'state': _stateController.text.trim().toUpperCase(),
        'updated_at': DateTime.now().toIso8601String(),
        if (avatarUrl != null && avatarUrl.isNotEmpty) 'avatar_url': avatarUrl,
      };

      await supabase.from('profiles').update(data).eq('id', user.id);

      if (!mounted) return;

      if (mounted) {
        Navigator.pushNamedAndRemoveUntil(
          context,
          '/dashboard',
          (route) => false,
        );
      }
    } catch (e) {
      debugPrint('❌ Erro ao salvar perfil: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao salvar: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Completar Cadastro'),
        backgroundColor: Colors.orange,
        foregroundColor: Colors.white,
        leading: const SizedBox(), // Remove botão de voltar
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Bem-vindo, Atleta!',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.orange,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Complete seu cadastro para continuar',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 24),

              // Foto
              Center(
                child: GestureDetector(
                  onTap: _pickImage,
                  child: Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      color: Colors.grey[200],
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.orange, width: 3),
                    ),
                    child: ClipOval(
                      child: _getAvatarImage(),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Center(
                child: TextButton.icon(
                  onPressed: _pickImage,
                  icon: const Icon(Icons.photo_camera, color: Colors.orange),
                  label: const Text('Selecionar Foto'),
                ),
              ),
              const SizedBox(height: 24),

              // Nome Completo
              TextFormField(
                controller: _fullNameController,
                decoration: const InputDecoration(
                  labelText: 'Nome Completo *',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.person),
                ),
                validator: (value) {
                  final name = value?.trim() ?? '';

                  if (name.isEmpty) {
                    return 'Pendente preenchimento do campo Nome Completo';
                  }

                  if (!_isFullName(name)) {
                    return 'Informe nome completo válido';
                  }

                  return null;
                },
              ),
              const SizedBox(height: 12),

              // CPF e RG
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _cpfController,
                      decoration: const InputDecoration(
                        labelText: 'CPF *',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.credit_card),
                      ),
                      keyboardType: TextInputType.number,
                      validator: (value) => _removeMask(value).length != 11
                          ? 'Pendente preenchimento do campo CPF'
                          : null,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      controller: _rgController,
                      decoration: const InputDecoration(
                        labelText: 'RG *',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.credit_card),
                      ),
                      keyboardType: TextInputType.number,
                      validator: (value) => value?.isEmpty ?? true
                          ? 'Pendente preenchimento do campo RG'
                          : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Telefone e Gênero
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _phoneController,
                      decoration: const InputDecoration(
                        labelText: 'Telefone *',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.phone),
                      ),
                      keyboardType: TextInputType.phone,
                      validator: (value) => _removeMask(value).length < 10
                          ? 'Pendente preenchimento do campo Telefone'
                          : null,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value:
                          _selectedGender.isNotEmpty ? _selectedGender : null,
                      decoration: const InputDecoration(
                        labelText: 'Gênero *',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.transgender),
                      ),
                      items: const [
                        DropdownMenuItem(
                            value: 'Masculino', child: Text('Masculino')),
                        DropdownMenuItem(
                            value: 'Feminino', child: Text('Feminino')),
                      ],
                      onChanged: (value) {
                        setState(() {
                          _selectedGender = value ?? '';
                          _selectedPosition = '';
                        });
                      },
                      validator: (value) => value == null
                          ? 'Pendente preenchimento do campo Gênero'
                          : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Data de Nascimento
              TextFormField(
                controller: _birthDateController,
                decoration: InputDecoration(
                  labelText: 'Data de Nascimento',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.calendar_today),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.calendar_today),
                    onPressed: _selectDate,
                  ),
                ),
                readOnly: true,
                validator: (value) => value == null || value.isEmpty
                    ? 'Pendente preenchimento do campo Data de Nascimento'
                    : null,
              ),
              const SizedBox(height: 12),

              // Posição na Quadra (apenas para atletas)
              if (_selectedGender.isNotEmpty)
                DropdownButtonFormField<String>(
                  value:
                      _selectedPosition.isNotEmpty ? _selectedPosition : null,
                  decoration: const InputDecoration(
                    labelText: 'Posição na Quadra',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.sports_volleyball),
                  ),
                  items: _positions[_selectedGender]!
                      .map((pos) => DropdownMenuItem(
                            value: pos['value'],
                            child: Text(pos['label']!),
                          ))
                      .toList(),
                  onChanged: (value) =>
                      setState(() => _selectedPosition = value ?? ''),
                ),
              const SizedBox(height: 24),

              // Endereço
              const Text('Endereço',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),

              TextFormField(
                controller: _zipCodeController,
                decoration: InputDecoration(
                  labelText: 'CEP *',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.location_on),
                  suffixIcon: _isFetchingCep
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : null,
                ),
                keyboardType: TextInputType.number,
                maxLength: 9,
                validator: (value) => _removeMask(value).length != 8
                    ? 'Pendente preenchimento do campo CEP'
                    : null,
              ),
              const SizedBox(height: 8),

              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: TextFormField(
                      controller: _streetController,
                      decoration: const InputDecoration(
                        labelText: 'Rua *',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) => value?.isEmpty ?? true
                          ? 'Pendente preenchimento do campo Rua'
                          : null,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      controller: _streetNumberController,
                      decoration: const InputDecoration(
                        labelText: 'Número *',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                      validator: (value) => value?.isEmpty ?? true
                          ? 'Pendente preenchimento do campo Número'
                          : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              TextFormField(
                controller: _complementController,
                decoration: const InputDecoration(
                  labelText: 'Complemento',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),

              TextFormField(
                controller: _neighborhoodController,
                decoration: const InputDecoration(
                  labelText: 'Bairro *',
                  border: OutlineInputBorder(),
                ),
                validator: (value) => value?.isEmpty ?? true
                    ? 'Pendente preenchimento do campo Bairro'
                    : null,
              ),
              const SizedBox(height: 8),

              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: TextFormField(
                      controller: _cityController,
                      decoration: const InputDecoration(
                        labelText: 'Cidade *',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) => value?.isEmpty ?? true
                          ? 'Pendente preenchimento do campo Cidade'
                          : null,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      controller: _stateController,
                      decoration: const InputDecoration(
                        labelText: 'Estado *',
                        border: OutlineInputBorder(),
                      ),
                      maxLength: 2,
                      validator: (value) => value?.isEmpty ?? true
                          ? 'Pendente preenchimento do campo Estado'
                          : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),

              // Botão Salvar
              SizedBox(
                height: 50,
                child: ElevatedButton(
                  onPressed: _isLoading || _isUploading ? null : _saveProfile,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: _isLoading || _isUploading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation(Colors.white),
                          ),
                        )
                      : const Text(
                          'Completar Cadastro',
                          style: TextStyle(fontSize: 16),
                        ),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _getAvatarImage() {
    if (_selectedImage != null) {
      return FutureBuilder<Uint8List?>(
        future: _selectedImage!.readAsBytes(),
        builder: (context, snapshot) {
          if (snapshot.hasData && snapshot.data != null) {
            return Image.memory(snapshot.data!, fit: BoxFit.cover);
          }
          return const Icon(Icons.person, size: 60, color: Colors.grey);
        },
      );
    }
    if (_existingAvatarUrl.isNotEmpty) {
      return Image.network(
        _existingAvatarUrl,
        fit: BoxFit.cover,
        errorBuilder: (c, o, s) =>
            const Icon(Icons.person, size: 60, color: Colors.grey),
      );
    }
    return const Icon(Icons.person, size: 60, color: Colors.grey);
  }

  @override
  void dispose() {
    _zipCodeController.removeListener(_onZipCodeChanged);
    _fullNameController.dispose();
    _phoneController.dispose();
    _birthDateController.dispose();
    _rgController.dispose();
    _cpfController.dispose();
    _zipCodeController.dispose();
    _streetController.dispose();
    _streetNumberController.dispose();
    _complementController.dispose();
    _neighborhoodController.dispose();
    _cityController.dispose();
    _stateController.dispose();
    super.dispose();
  }
}
