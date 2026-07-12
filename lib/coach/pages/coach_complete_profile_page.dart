import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_masked_text2/flutter_masked_text2.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CoachCompleteProfilePage extends StatefulWidget {
  const CoachCompleteProfilePage({
    super.key,
    this.isEditing = false,
  });

  final bool isEditing;

  @override
  State<CoachCompleteProfilePage> createState() =>
      _CoachCompleteProfilePageState();
}

class _CoachCompleteProfilePageState extends State<CoachCompleteProfilePage> {
  final SupabaseClient supabase = Supabase.instance.client;
  final ImagePicker _picker = ImagePicker();
  final _formKey = GlobalKey<FormState>();

  static const Color olympusBlue = Color(0xFF1E3A5F);
  static const Color olympusGold = Color(0xFFD4AF37);
  static const Color olympusLightBlue = Color(0xFF2C5F8D);
  static const Color olympusDark = Color(0xFF0B1420);

  final TextEditingController _nameController = TextEditingController();
  final MaskedTextController _cpfController =
      MaskedTextController(mask: '000.000.000-00');
  final MaskedTextController _phoneController =
      MaskedTextController(mask: '(00) 00000-0000');
  final TextEditingController _rgController = TextEditingController();
  final MaskedTextController _birthDateController =
      MaskedTextController(mask: '00/00/0000');
  final MaskedTextController _cepController =
      MaskedTextController(mask: '00000-000');
  final TextEditingController _streetController = TextEditingController();
  final TextEditingController _numberController = TextEditingController();
  final TextEditingController _complementController = TextEditingController();
  final TextEditingController _neighborhoodController = TextEditingController();
  final TextEditingController _cityController = TextEditingController();
  final TextEditingController _stateController = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  bool _uploadingImage = false;
  bool _loadingCep = false;
  String? _errorMessage;
  String _avatarUrl = '';
  XFile? _selectedImage;
  Uint8List? _selectedImageBytes;
  Timer? _cepDebounce;

  @override
  void initState() {
    super.initState();
    _cepController.addListener(_onCepChanged);
    _loadProfile();
  }

  @override
  void dispose() {
    _cepDebounce?.cancel();
    _cepController.removeListener(_onCepChanged);
    _nameController.dispose();
    _cpfController.dispose();
    _phoneController.dispose();
    _rgController.dispose();
    _birthDateController.dispose();
    _cepController.dispose();
    _streetController.dispose();
    _numberController.dispose();
    _complementController.dispose();
    _neighborhoodController.dispose();
    _cityController.dispose();
    _stateController.dispose();
    super.dispose();
  }

  String _onlyNumbers(String value) => value.replaceAll(RegExp(r'\D'), '');

  String _formatCpf(String value) {
    final numbers = _onlyNumbers(value);
    if (numbers.length != 11) return value;
    return '${numbers.substring(0, 3)}.${numbers.substring(3, 6)}.${numbers.substring(6, 9)}-${numbers.substring(9)}';
  }

  String _formatPhone(String value) {
    final numbers = _onlyNumbers(value);
    if (numbers.length == 11) {
      return '(${numbers.substring(0, 2)}) ${numbers.substring(2, 7)}-${numbers.substring(7)}';
    }
    if (numbers.length == 10) {
      return '(${numbers.substring(0, 2)}) ${numbers.substring(2, 6)}-${numbers.substring(6)}';
    }
    return value;
  }

  String _formatCep(String value) {
    final numbers = _onlyNumbers(value);
    if (numbers.length != 8) return value;
    return '${numbers.substring(0, 5)}-${numbers.substring(5)}';
  }

  String _formatBirthDate(dynamic value) {
    final raw = (value ?? '').toString().trim();
    if (raw.isEmpty) return '';

    try {
      final parsed = DateTime.tryParse(raw);
      if (parsed != null) {
        return '${parsed.day.toString().padLeft(2, '0')}/'
            '${parsed.month.toString().padLeft(2, '0')}/'
            '${parsed.year.toString().padLeft(4, '0')}';
      }
    } catch (_) {}

    final numbers = _onlyNumbers(raw);
    if (numbers.length == 8) {
      return '${numbers.substring(0, 2)}/${numbers.substring(2, 4)}/${numbers.substring(4)}';
    }
    return raw;
  }

  DateTime? _parseBirthDateInput() {
    final numbers = _onlyNumbers(_birthDateController.text);
    if (numbers.length != 8) return null;

    final day = int.tryParse(numbers.substring(0, 2));
    final month = int.tryParse(numbers.substring(2, 4));
    final year = int.tryParse(numbers.substring(4, 8));
    if (day == null || month == null || year == null) return null;

    final parsed = DateTime(year, month, day);
    if (parsed.day != day || parsed.month != month || parsed.year != year) {
      return null;
    }
    return parsed;
  }

  String? _birthDateToDatabase() {
    final parsed = _parseBirthDateInput();
    if (parsed == null) return null;
    return '${parsed.year.toString().padLeft(4, '0')}-'
        '${parsed.month.toString().padLeft(2, '0')}-'
        '${parsed.day.toString().padLeft(2, '0')}';
  }

  bool _hasCompleteName(String value) {
    final parts = value
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.trim().length >= 2)
        .toList();
    return parts.length >= 2;
  }

  bool get _hasPhoto =>
      _selectedImageBytes != null || _avatarUrl.trim().isNotEmpty;

  Future<void> _loadProfile() async {
    final user = supabase.auth.currentUser;

    if (user == null) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorMessage = 'Usuário não autenticado.';
      });
      return;
    }

    try {
      final profile = await supabase
          .from('profiles')
          .select(
            'full_name, cpf, phone, rg, birth_date, avatar_url, user_type, '
            'cep, address_street, address_number, address_complement, '
            'address_neighborhood, address_city, address_state',
          )
          .eq('id', user.id)
          .maybeSingle();

      final metadataName = user.userMetadata?['full_name']?.toString().trim();
      final fullName =
          (profile?['full_name'] ?? metadataName ?? '').toString().trim();
      final cpf = (profile?['cpf'] ?? '').toString();
      final phone = (profile?['phone'] ?? '').toString();
      final rg = (profile?['rg'] ?? '').toString();
      final birthDate = profile?['birth_date'];
      final avatarUrl = (profile?['avatar_url'] ?? '').toString().trim();
      final cep = (profile?['cep'] ?? '').toString();

      _nameController.text = fullName;
      _cpfController.text = _formatCpf(cpf);
      _phoneController.text = _formatPhone(phone);
      _rgController.text = rg;
      _birthDateController.text = _formatBirthDate(birthDate);
      _cepController.text = _formatCep(cep);
      _streetController.text =
          (profile?['address_street'] ?? '').toString().trim();
      _numberController.text =
          (profile?['address_number'] ?? '').toString().trim();
      _complementController.text =
          (profile?['address_complement'] ?? '').toString().trim();
      _neighborhoodController.text =
          (profile?['address_neighborhood'] ?? '').toString().trim();
      _cityController.text = (profile?['address_city'] ?? '').toString().trim();
      _stateController.text =
          (profile?['address_state'] ?? '').toString().trim().toUpperCase();
      _avatarUrl = avatarUrl;

      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorMessage = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorMessage = 'Erro ao carregar perfil: $e';
      });
    }
  }

  void _onCepChanged() {
    final cep = _onlyNumbers(_cepController.text);
    _cepDebounce?.cancel();

    if (cep.length != 8) return;

    _cepDebounce = Timer(
      const Duration(milliseconds: 450),
      () => _lookupCep(cep),
    );
  }

  Future<void> _lookupCep(String cep) async {
    if (_loadingCep || cep.length != 8) return;

    FocusScope.of(context).unfocus();

    setState(() {
      _loadingCep = true;
      _errorMessage = null;
    });

    try {
      final uri = Uri.parse('https://viacep.com.br/ws/$cep/json/');
      final response = await http.get(uri).timeout(const Duration(seconds: 8));

      if (response.statusCode != 200) {
        throw Exception('CEP não encontrado.');
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (data['erro'] == true) {
        throw Exception('CEP inválido ou não encontrado.');
      }

      if (!mounted) return;
      setState(() {
        _streetController.text = (data['logradouro'] ?? '').toString().trim();
        _neighborhoodController.text = (data['bairro'] ?? '').toString().trim();
        _cityController.text = (data['localidade'] ?? '').toString().trim();
        _stateController.text = (data['uf'] ?? '').toString().trim();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Não foi possível buscar o CEP automaticamente: $e';
      });
    } finally {
      if (mounted) {
        setState(() => _loadingCep = false);
      }
    }
  }

  Future<void> _selectBirthDate() async {
    if (_saving) return;

    final current = _parseBirthDateInput();
    final now = DateTime.now();
    final initialDate = current ?? DateTime(now.year - 25, now.month, now.day);

    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate.isAfter(now) ? now : initialDate,
      firstDate: DateTime(1930),
      lastDate: now,
      helpText: 'Data de nascimento',
      cancelText: 'Cancelar',
      confirmText: 'Selecionar',
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: olympusBlue,
              onPrimary: Colors.white,
              onSurface: olympusDark,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked == null) return;

    setState(() {
      _birthDateController.text = '${picked.day.toString().padLeft(2, '0')}/'
          '${picked.month.toString().padLeft(2, '0')}/'
          '${picked.year.toString().padLeft(4, '0')}';
    });
  }

  Future<void> _pickImage() async {
    try {
      final image = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 82,
        maxWidth: 1200,
      );

      if (image == null) return;

      final bytes = await image.readAsBytes();
      if (bytes.isEmpty) {
        _showSnack('Não foi possível carregar a imagem selecionada.');
        return;
      }

      if (!mounted) return;
      setState(() {
        _selectedImage = image;
        _selectedImageBytes = bytes;
        _errorMessage = null;
      });
    } catch (e) {
      _showSnack('Erro ao selecionar foto: $e');
    }
  }

  Future<String> _uploadAvatarIfNeeded(String userId) async {
    if (_selectedImage == null || _selectedImageBytes == null) {
      return _avatarUrl.trim();
    }

    setState(() => _uploadingImage = true);

    try {
      final rawExt = _selectedImage!.name.split('.').last.toLowerCase();
      final ext =
          ['jpg', 'jpeg', 'png', 'webp'].contains(rawExt) ? rawExt : 'jpg';
      final contentType = ext == 'png'
          ? 'image/png'
          : ext == 'webp'
              ? 'image/webp'
              : 'image/jpeg';
      final path =
          'coaches/$userId/avatar_${DateTime.now().millisecondsSinceEpoch}.$ext';

      await supabase.storage.from('avatars').uploadBinary(
            path,
            _selectedImageBytes!,
            fileOptions: FileOptions(
              contentType: contentType,
              upsert: true,
            ),
          );

      return supabase.storage.from('avatars').getPublicUrl(path);
    } finally {
      if (mounted) setState(() => _uploadingImage = false);
    }
  }

  Future<void> _saveProfile() async {
    if (!_hasPhoto) {
      setState(() {
        _errorMessage = 'Selecione uma foto de perfil para continuar.';
      });
      return;
    }

    if (!_formKey.currentState!.validate()) return;

    final user = supabase.auth.currentUser;
    if (user == null) return;

    FocusScope.of(context).unfocus();

    setState(() {
      _saving = true;
      _errorMessage = null;
    });

    try {
      final now = DateTime.now().toUtc().toIso8601String();
      final avatarUrl = await _uploadAvatarIfNeeded(user.id);

      if (avatarUrl.trim().isEmpty) {
        throw Exception('Foto de perfil obrigatória.');
      }

      final payload = <String, dynamic>{
        'full_name': _nameController.text.trim(),
        'cpf': _onlyNumbers(_cpfController.text),
        'phone': _onlyNumbers(_phoneController.text),
        'rg': _rgController.text.trim(),
        'birth_date': _birthDateToDatabase(),
        'avatar_url': avatarUrl.trim(),
        'cep': _onlyNumbers(_cepController.text),
        'address_street': _streetController.text.trim(),
        'address_number': _numberController.text.trim(),
        'address_complement': _complementController.text.trim().isEmpty
            ? null
            : _complementController.text.trim(),
        'address_neighborhood': _neighborhoodController.text.trim(),
        'address_city': _cityController.text.trim(),
        'address_state': _stateController.text.trim().toUpperCase(),
        'user_type': 'coach',
        'profile_completed_at': now,
        'updated_at': now,
      };

      await supabase.from('profiles').update(payload).eq('id', user.id);

      await supabase.auth.updateUser(
        UserAttributes(
          data: {
            'full_name': _nameController.text.trim(),
            'avatar_url': avatarUrl.trim(),
          },
        ),
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.isEditing
                ? 'Dados atualizados com sucesso.'
                : 'Cadastro concluído com sucesso.',
          ),
          backgroundColor: Colors.green,
        ),
      );

      if (widget.isEditing) {
        Navigator.pop(context, true);
      } else {
        Navigator.pushNamedAndRemoveUntil(
          context,
          '/dashboard',
          (route) => false,
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Erro ao salvar perfil: $e';
      });
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  void _showSnack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Widget _buildBackground() {
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.asset(
          'assets/images/monte_olimpo_v2.png',
          fit: BoxFit.cover,
          alignment: Alignment.center,
          errorBuilder: (_, __, ___) {
            return Container(color: olympusDark);
          },
        ),
        Container(color: Colors.black.withOpacity(0.35)),
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                olympusBlue.withOpacity(0.64),
                olympusLightBlue.withOpacity(0.24),
                olympusDark.withOpacity(0.86),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAvatarPreview(bool isCompact) {
    final initials = _nameController.text.trim().isEmpty
        ? 'T'
        : _nameController.text.trim().characters.first.toUpperCase();

    Widget child;
    if (_selectedImageBytes != null) {
      child = Image.memory(_selectedImageBytes!, fit: BoxFit.cover);
    } else if (_avatarUrl.trim().isNotEmpty) {
      child = Image.network(
        _avatarUrl.trim(),
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _buildInitials(initials, isCompact),
      );
    } else {
      child = _buildInitials(initials, isCompact);
    }

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: isCompact ? 98 : 116,
          height: isCompact ? 98 : 116,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              colors: [
                Color(0xFFF0D771),
                Color(0xFFB48A23),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(
                color: olympusGold.withOpacity(0.30),
                blurRadius: 24,
                spreadRadius: 2,
              ),
            ],
          ),
          padding: const EdgeInsets.all(3),
          child: ClipOval(
            child: Container(
              color: const Color(0xFF113457),
              child: child,
            ),
          ),
        ),
        Positioned(
          right: -2,
          bottom: -2,
          child: Material(
            color: olympusGold,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: _saving ? null : _pickImage,
              child: const Padding(
                padding: EdgeInsets.all(10),
                child: Icon(
                  Icons.photo_camera_rounded,
                  color: olympusBlue,
                  size: 20,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInitials(String initials, bool isCompact) {
    return Center(
      child: Text(
        initials,
        style: TextStyle(
          color: const Color(0xFFFFF2B8),
          fontSize: isCompact ? 30 : 36,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  Widget _buildHeader(bool isCompact) {
    return Column(
      children: [
        GestureDetector(
          onTap: _saving ? null : _pickImage,
          child: _buildAvatarPreview(isCompact),
        ),
        const SizedBox(height: 12),
        TextButton.icon(
          onPressed: _saving ? null : _pickImage,
          icon: const Icon(Icons.upload_file_rounded),
          label: Text(
            _hasPhoto ? 'Alterar foto' : 'Selecionar foto obrigatória',
          ),
          style: TextButton.styleFrom(
            foregroundColor: olympusGold,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          widget.isEditing ? 'Editar meus dados' : 'Complete seu cadastro',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white,
            fontSize: isCompact ? 22 : 26,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Dados obrigatórios do treinador',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white.withOpacity(0.82),
            fontSize: isCompact ? 13 : 14,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  InputDecoration _decoration({
    required String label,
    required IconData icon,
    String? hint,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: Icon(icon, color: olympusGold),
      suffixIcon: suffixIcon,
      labelStyle: TextStyle(color: Colors.white.withOpacity(0.76)),
      hintStyle: TextStyle(color: Colors.white.withOpacity(0.38)),
      filled: true,
      fillColor: const Color(0xFF0A1A2C).withOpacity(0.78),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: olympusGold.withOpacity(0.22)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: olympusGold.withOpacity(0.22)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: olympusGold, width: 1.8),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: Colors.redAccent),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: Colors.redAccent, width: 1.8),
      ),
      errorStyle: const TextStyle(color: Color(0xFFFFB4B4)),
    );
  }

  Widget _sectionTitle(String title) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        title,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 15,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  Widget _buildForm(bool isCompact) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(26),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          width: double.infinity,
          padding: EdgeInsets.all(isCompact ? 16 : 22),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(26),
            gradient: LinearGradient(
              colors: [
                Colors.white.withOpacity(0.15),
                Colors.white.withOpacity(0.07),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            border: Border.all(color: olympusGold.withOpacity(0.24)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.22),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                _sectionTitle('Identificação'),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _nameController,
                  enabled: !_saving,
                  style: const TextStyle(color: Colors.white),
                  textCapitalization: TextCapitalization.words,
                  decoration: _decoration(
                    label: 'Nome completo *',
                    icon: Icons.person_outline,
                  ),
                  validator: (value) {
                    final text = (value ?? '').trim();
                    if (text.isEmpty) return 'Informe seu nome completo.';
                    if (!_hasCompleteName(text)) {
                      return 'Informe nome e sobrenome.';
                    }
                    return null;
                  },
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _cpfController,
                  enabled: !_saving,
                  style: const TextStyle(color: Colors.white),
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: _decoration(
                    label: 'CPF *',
                    icon: Icons.badge_outlined,
                  ),
                  validator: (value) {
                    final numbers = _onlyNumbers(value ?? '');
                    if (numbers.length != 11) {
                      return 'Informe um CPF válido com 11 dígitos.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _rgController,
                  enabled: !_saving,
                  style: const TextStyle(color: Colors.white),
                  textCapitalization: TextCapitalization.characters,
                  decoration: _decoration(
                    label: 'RG *',
                    icon: Icons.credit_card_outlined,
                  ),
                  validator: (value) {
                    final text = (value ?? '').trim();
                    if (text.isEmpty) return 'Informe o RG.';
                    if (text.length < 5) return 'Informe um RG válido.';
                    return null;
                  },
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _birthDateController,
                  enabled: !_saving,
                  readOnly: true,
                  style: const TextStyle(color: Colors.white),
                  keyboardType: TextInputType.datetime,
                  decoration: _decoration(
                    label: 'Data de nascimento *',
                    icon: Icons.cake_outlined,
                    hint: 'dd/mm/aaaa',
                    suffixIcon: IconButton(
                      tooltip: 'Selecionar data',
                      onPressed: _saving ? null : _selectBirthDate,
                      icon: const Icon(
                        Icons.calendar_month_rounded,
                        color: olympusGold,
                      ),
                    ),
                  ),
                  onTap: _selectBirthDate,
                  validator: (value) {
                    final parsed = _parseBirthDateInput();
                    if ((value ?? '').trim().isEmpty || parsed == null) {
                      return 'Informe uma data de nascimento válida.';
                    }
                    if (parsed.isAfter(DateTime.now())) {
                      return 'A data não pode ser futura.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _phoneController,
                  enabled: !_saving,
                  style: const TextStyle(color: Colors.white),
                  keyboardType: TextInputType.phone,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: _decoration(
                    label: 'Telefone *',
                    icon: Icons.phone_outlined,
                  ),
                  validator: (value) {
                    final numbers = _onlyNumbers(value ?? '');
                    if (numbers.length < 10 || numbers.length > 11) {
                      return 'Informe um telefone válido.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 20),
                _sectionTitle('Endereço'),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _cepController,
                  enabled: !_saving,
                  style: const TextStyle(color: Colors.white),
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: _decoration(
                    label: 'CEP *',
                    icon: Icons.location_searching_rounded,
                    hint: '00000-000',
                    suffixIcon: _loadingCep
                        ? const Padding(
                            padding: EdgeInsets.all(14),
                            child: SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: olympusGold,
                              ),
                            ),
                          )
                        : IconButton(
                            tooltip: 'Buscar CEP',
                            onPressed: _saving
                                ? null
                                : () => _lookupCep(
                                      _onlyNumbers(_cepController.text),
                                    ),
                            icon: const Icon(
                              Icons.search_rounded,
                              color: olympusGold,
                            ),
                          ),
                  ),
                  validator: (value) {
                    final numbers = _onlyNumbers(value ?? '');
                    if (numbers.length != 8) return 'Informe um CEP válido.';
                    return null;
                  },
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _streetController,
                  enabled: !_saving,
                  style: const TextStyle(color: Colors.white),
                  textCapitalization: TextCapitalization.words,
                  decoration: _decoration(
                    label: 'Endereço *',
                    icon: Icons.home_outlined,
                  ),
                  validator: (value) {
                    if ((value ?? '').trim().isEmpty) {
                      return 'Informe o endereço.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: TextFormField(
                        controller: _numberController,
                        enabled: !_saving,
                        style: const TextStyle(color: Colors.white),
                        keyboardType: TextInputType.text,
                        decoration: _decoration(
                          label: 'Número *',
                          icon: Icons.numbers_rounded,
                        ),
                        validator: (value) {
                          if ((value ?? '').trim().isEmpty) {
                            return 'Obrigatório.';
                          }
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 3,
                      child: TextFormField(
                        controller: _complementController,
                        enabled: !_saving,
                        style: const TextStyle(color: Colors.white),
                        textCapitalization: TextCapitalization.words,
                        decoration: _decoration(
                          label: 'Complemento',
                          icon: Icons.apartment_rounded,
                          hint: 'Opcional',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _neighborhoodController,
                  enabled: !_saving,
                  style: const TextStyle(color: Colors.white),
                  textCapitalization: TextCapitalization.words,
                  decoration: _decoration(
                    label: 'Bairro *',
                    icon: Icons.location_city_outlined,
                  ),
                  validator: (value) {
                    if ((value ?? '').trim().isEmpty) {
                      return 'Informe o bairro.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: TextFormField(
                        controller: _cityController,
                        enabled: !_saving,
                        style: const TextStyle(color: Colors.white),
                        textCapitalization: TextCapitalization.words,
                        decoration: _decoration(
                          label: 'Cidade *',
                          icon: Icons.location_on_outlined,
                        ),
                        validator: (value) {
                          if ((value ?? '').trim().isEmpty) {
                            return 'Informe a cidade.';
                          }
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 1,
                      child: TextFormField(
                        controller: _stateController,
                        enabled: !_saving,
                        style: const TextStyle(color: Colors.white),
                        textCapitalization: TextCapitalization.characters,
                        inputFormatters: [
                          LengthLimitingTextInputFormatter(2),
                        ],
                        decoration: _decoration(
                          label: 'UF *',
                          icon: Icons.flag_outlined,
                        ),
                        validator: (value) {
                          final text = (value ?? '').trim();
                          if (text.length != 2) return 'UF';
                          return null;
                        },
                      ),
                    ),
                  ],
                ),
                if (_errorMessage != null) ...[
                  const SizedBox(height: 14),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.red.withOpacity(0.28)),
                    ),
                    child: Text(
                      _errorMessage!,
                      style: const TextStyle(
                        color: Color(0xFFFFD1D1),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton.icon(
                    onPressed: _saving || _uploadingImage ? null : _saveProfile,
                    icon: _saving || _uploadingImage
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: olympusBlue,
                            ),
                          )
                        : const Icon(Icons.save_rounded),
                    label: Text(
                      _saving
                          ? 'Salvando...'
                          : _uploadingImage
                              ? 'Enviando foto...'
                              : widget.isEditing
                                  ? 'Salvar alterações'
                                  : 'Concluir cadastro',
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.2,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: olympusGold,
                      foregroundColor: olympusBlue,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isCompact = MediaQuery.of(context).size.width < 390;

    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: olympusDark,
      appBar: widget.isEditing
          ? AppBar(
              title: const Text('Editar dados'),
              backgroundColor: Colors.transparent,
              elevation: 0,
              foregroundColor: Colors.white,
            )
          : null,
      body: Stack(
        children: [
          _buildBackground(),
          SafeArea(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(color: olympusGold),
                  )
                : Center(
                    child: SingleChildScrollView(
                      padding: EdgeInsets.fromLTRB(
                        isCompact ? 16 : 20,
                        widget.isEditing ? 16 : 28,
                        isCompact ? 16 : 20,
                        28,
                      ),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 560),
                        child: Column(
                          children: [
                            _buildHeader(isCompact),
                            const SizedBox(height: 22),
                            _buildForm(isCompact),
                          ],
                        ),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
