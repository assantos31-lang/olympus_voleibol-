import 'dart:convert';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'events_by_championship_page.dart';

class ChampionshipsPage extends StatefulWidget {
  const ChampionshipsPage({super.key});

  @override
  State<ChampionshipsPage> createState() => _ChampionshipsPageState();
}

class _ChampionshipsPageState extends State<ChampionshipsPage> {
  static const Color olympusBlue = Color(0xFF1E3A5F);
  static const Color olympusGold = Color(0xFFD4AF37);
  static const Color olympusLightBlue = Color(0xFF2C5F8D);
  static const Color futuristicDark = Color(0xFF0B1420);
  static const Color futuristicCard = Color(0xFF122235);

  final TextEditingController _searchController = TextEditingController();
  final ImagePicker _imagePicker = ImagePicker();

  List<Map<String, dynamic>> _allChampionships = [];
  List<Map<String, dynamic>> _filteredChampionships = [];
  bool _isLoading = true;
  bool _isAdmin = false;
  final Set<String> _uploadingChampionships = {};

  @override
  void initState() {
    super.initState();
    _loadChampionships();
    _checkIfAdmin();
    _searchController.addListener(_applyFilter);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _checkIfAdmin() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return;

      final response = await Supabase.instance.client
          .from('users')
          .select('role')
          .eq('id', user.id)
          .maybeSingle();

      if (!mounted) return;

      setState(() {
        _isAdmin =
            (response?['role'] ?? '').toString().toUpperCase() == 'ADMIN';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isAdmin = false;
      });
    }
  }

  Future<void> _loadChampionships() async {
    try {
      if (mounted) {
        setState(() => _isLoading = true);
      }

      final supabase = Supabase.instance.client;

      final response = await supabase.from('events').select(
            'id, championship_name, event_name, event_date, event_time, image_url, created_at',
          );

      final Map<String, List<Map<String, dynamic>>> grouped = {};

      for (final item in response) {
        final rawName = (item['championship_name'] ?? '').toString().trim();
        if (rawName.isEmpty) continue;

        grouped.putIfAbsent(rawName, () => []);
        grouped[rawName]!.add(Map<String, dynamic>.from(item));
      }

      final championships = grouped.entries.map((entry) {
        final events = entry.value;

        events.sort((a, b) {
          final bCreated = (b['created_at'] ?? '').toString();
          final aCreated = (a['created_at'] ?? '').toString();
          return bCreated.compareTo(aCreated);
        });

        final latestEvent = events.first;

        String imageUrl = '';
        for (final event in events) {
          final currentImage = (event['image_url'] ?? '').toString().trim();
          if (currentImage.isNotEmpty) {
            imageUrl = currentImage;
            break;
          }
        }

        return {
          'name': entry.key,
          'count': events.length,
          'latest_event_name': latestEvent['event_name'] ?? '',
          'latest_event_date': latestEvent['event_date'] ?? '',
          'latest_event_time': latestEvent['event_time'] ?? '',
          'image_url': imageUrl,
        };
      }).toList();

      championships.sort((a, b) {
        final aName = (a['name'] ?? '').toString().toLowerCase();
        final bName = (b['name'] ?? '').toString().toLowerCase();
        return aName.compareTo(bName);
      });

      if (!mounted) return;

      setState(() {
        _allChampionships = championships;
        _filteredChampionships = championships;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _allChampionships = [];
        _filteredChampionships = [];
        _isLoading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao carregar campeonatos: $e'),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _applyFilter() {
    final query = _searchController.text.trim().toLowerCase();

    setState(() {
      if (query.isEmpty) {
        _filteredChampionships = List.from(_allChampionships);
      } else {
        _filteredChampionships = _allChampionships.where((championship) {
          final name = (championship['name'] ?? '').toString().toLowerCase();
          final latestEvent = (championship['latest_event_name'] ?? '')
              .toString()
              .toLowerCase();

          return name.contains(query) || latestEvent.contains(query);
        }).toList();
      }
    });
  }

  void _openChampionship(Map<String, dynamic> championship) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EventsByChampionshipPage(
          name: championship['name'],
        ),
      ),
    );
  }

  Future<void> _pickAndSaveChampionshipImage(
    Map<String, dynamic> championship,
  ) async {
    final championshipName = (championship['name'] ?? '').toString().trim();
    if (championshipName.isEmpty) return;

    try {
      final XFile? pickedFile = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
      );

      if (pickedFile == null) return;

      if (!mounted) return;
      setState(() {
        _uploadingChampionships.add(championshipName);
      });

      final bytes = await pickedFile.readAsBytes();
      final extension = pickedFile.name.toLowerCase();

      String mimeType = 'image/jpeg';
      if (extension.endsWith('.png')) {
        mimeType = 'image/png';
      } else if (extension.endsWith('.webp')) {
        mimeType = 'image/webp';
      } else if (extension.endsWith('.gif')) {
        mimeType = 'image/gif';
      }

      final imageDataUrl = 'data:$mimeType;base64,${base64Encode(bytes)}';

      final supabase = Supabase.instance.client;

      await supabase.from('events').update({'image_url': imageDataUrl}).eq(
          'championship_name', championshipName);

      setState(() {
        _allChampionships = _allChampionships.map((item) {
          if ((item['name'] ?? '').toString() == championshipName) {
            return {
              ...item,
              'image_url': imageDataUrl,
            };
          }
          return item;
        }).toList();

        _filteredChampionships = _filteredChampionships.map((item) {
          if ((item['name'] ?? '').toString() == championshipName) {
            return {
              ...item,
              'image_url': imageDataUrl,
            };
          }
          return item;
        }).toList();
      });
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao salvar imagem: $e'),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (!mounted) return;
      setState(() {
        _uploadingChampionships.remove(championshipName);
      });
    }
  }

  Widget _buildCardImage(String imageUrl) {
    final trimmed = imageUrl.trim();

    if (trimmed.startsWith('data:image')) {
      try {
        final commaIndex = trimmed.indexOf(',');
        if (commaIndex != -1) {
          final bytes = base64Decode(trimmed.substring(commaIndex + 1));
          return Image.memory(
            bytes,
            height: 155,
            width: double.infinity,
            fit: BoxFit.cover,
            gaplessPlayback: true,
            errorBuilder: (_, __, ___) => _buildImageFallback(),
          );
        }
      } catch (_) {
        return _buildImageFallback();
      }
    }

    return Image.network(
      trimmed,
      height: 155,
      width: double.infinity,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => _buildImageFallback(),
    );
  }

  Widget _buildImageFallback() {
    return Container(
      height: 155,
      width: double.infinity,
      color: const Color(0xFF16304A),
      child: const Center(
        child: Icon(
          Icons.image_not_supported_outlined,
          color: Colors.white54,
          size: 34,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: futuristicDark,
      body: Stack(
        children: [
          IgnorePointer(
            child: Stack(
              children: [
                Positioned.fill(
                  child: Opacity(
                    opacity: 0.78,
                    child: Image.asset(
                      'assets/images/monte_olimpo.png',
                      fit: BoxFit.cover,
                      alignment: Alignment.topCenter,
                    ),
                  ),
                ),
                Positioned.fill(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 0.8, sigmaY: 0.8),
                    child: Container(color: Colors.transparent),
                  ),
                ),
                Positioned.fill(
                  child: Container(
                    color: futuristicDark.withOpacity(0.46),
                  ),
                ),
                Positioned.fill(
                  child: Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Color.fromRGBO(9, 17, 27, 0.26),
                          Color.fromRGBO(17, 37, 58, 0.14),
                          Color.fromRGBO(30, 58, 95, 0.28),
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: CustomPaint(
                    painter: _FuturisticBackgroundPainter(),
                  ),
                ),
              ],
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                _buildHeader(),
                Expanded(
                  child: RefreshIndicator(
                    color: olympusGold,
                    backgroundColor: futuristicCard,
                    onRefresh: _loadChampionships,
                    child: _isLoading
                        ? _buildLoadingState()
                        : _filteredChampionships.isEmpty
                            ? _buildEmptyState()
                            : ListView(
                                physics: const AlwaysScrollableScrollPhysics(),
                                padding:
                                    const EdgeInsets.fromLTRB(16, 8, 16, 20),
                                children: [
                                  _buildSearchField(),
                                  const SizedBox(height: 16),
                                  _buildSummaryCard(),
                                  const SizedBox(height: 18),
                                  ..._filteredChampionships.asMap().entries.map(
                                    (entry) {
                                      final index = entry.key;
                                      final item = entry.value;

                                      return TweenAnimationBuilder<double>(
                                        tween: Tween(begin: 0, end: 1),
                                        duration: Duration(
                                          milliseconds: 260 + (index * 70),
                                        ),
                                        curve: Curves.easeOutCubic,
                                        builder: (context, value, child) {
                                          return Transform.translate(
                                            offset: Offset(
                                              0,
                                              20 * (1 - value),
                                            ),
                                            child: Opacity(
                                              opacity: value,
                                              child: child,
                                            ),
                                          );
                                        },
                                        child: _buildChampionshipCard(item),
                                      );
                                    },
                                  ),
                                ],
                              ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [
            Color(0xFF122235),
            Color(0xFF18324D),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: olympusGold.withOpacity(0.30)),
        boxShadow: [
          BoxShadow(
            color: olympusGold.withOpacity(0.08),
            blurRadius: 18,
            spreadRadius: 1,
          ),
          BoxShadow(
            color: Colors.black.withOpacity(0.35),
            blurRadius: 22,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: olympusGold.withOpacity(0.14),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: olympusGold.withOpacity(0.25),
              ),
            ),
            child: IconButton(
              padding: EdgeInsets.zero,
              onPressed: () => Navigator.pop(context),
              icon: const Icon(
                Icons.arrow_back_ios_new_rounded,
                color: Colors.white,
                size: 20,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Campeonatos',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Explore ligas e veja todos os jogos cadastrados',
                  style: TextStyle(
                    color: olympusGold.withOpacity(0.95),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: olympusGold.withOpacity(0.12),
              border: Border.all(
                color: olympusGold.withOpacity(0.25),
              ),
            ),
            child: const Icon(
              Icons.emoji_events_rounded,
              color: olympusGold,
              size: 24,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchField() {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [
            Color(0xFF122235),
            Color(0xFF18324D),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: olympusGold.withOpacity(0.22),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.24),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: TextField(
        controller: _searchController,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          hintText: 'Buscar campeonato ou jogo...',
          hintStyle: TextStyle(
            color: Colors.white.withOpacity(0.45),
          ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 16,
          ),
          prefixIcon: const Icon(
            Icons.search_rounded,
            color: olympusGold,
          ),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
                  onPressed: () {
                    _searchController.clear();
                    _applyFilter();
                  },
                  icon: const Icon(
                    Icons.close_rounded,
                    color: Colors.white70,
                  ),
                )
              : null,
        ),
      ),
    );
  }

  Widget _buildSummaryCard() {
    final totalChampionships = _allChampionships.length;
    final totalGames = _allChampionships.fold<int>(
      0,
      (sum, item) => sum + ((item['count'] ?? 0) as int),
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.06),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: olympusGold.withOpacity(0.18),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: _buildMiniStat(
                  icon: Icons.emoji_events_rounded,
                  label: 'Campeonatos',
                  value: '$totalChampionships',
                ),
              ),
              Container(
                width: 1,
                height: 42,
                color: Colors.white.withOpacity(0.12),
              ),
              Expanded(
                child: _buildMiniStat(
                  icon: Icons.sports_volleyball_rounded,
                  label: 'Jogos',
                  value: '$totalGames',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMiniStat({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: olympusGold.withOpacity(0.14),
            border: Border.all(
              color: olympusGold.withOpacity(0.28),
            ),
          ),
          child: Icon(
            icon,
            color: olympusGold,
            size: 20,
          ),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            Text(
              label,
              style: TextStyle(
                color: Colors.white.withOpacity(0.62),
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildChampionshipCard(Map<String, dynamic> championship) {
    final String name = championship['name'] ?? '';
    final int count = championship['count'] ?? 0;
    final String latestEventName = championship['latest_event_name'] ?? '';
    final String latestEventDate = championship['latest_event_date'] ?? '';
    final String latestEventTime = championship['latest_event_time'] ?? '';
    final String imageUrl = (championship['image_url'] ?? '').toString().trim();
    final bool isUploading = _uploadingChampionships.contains(name);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [
            Color(0xFF122235),
            Color(0xFF18324D),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: olympusGold.withOpacity(0.28),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.30),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
          BoxShadow(
            color: olympusGold.withOpacity(0.06),
            blurRadius: 18,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _openChampionship(championship),
          borderRadius: BorderRadius.circular(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (imageUrl.isNotEmpty)
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(24),
                  ),
                  child: Stack(
                    children: [
                      _buildCardImage(imageUrl),
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.black.withOpacity(0.10),
                                Colors.black.withOpacity(0.35),
                              ],
                            ),
                          ),
                        ),
                      ),
                      if (_isAdmin)
                        Positioned(
                          top: 12,
                          left: 12,
                          child: _buildImageActionButton(
                            championship: championship,
                            isUploading: isUploading,
                          ),
                        ),
                      Positioned(
                        top: 12,
                        right: 12,
                        child:
                            _buildBadge('$count jogo${count > 1 ? 's' : ''}'),
                      ),
                    ],
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: Row(
                    children: [
                      if (_isAdmin)
                        _buildImageActionButton(
                          championship: championship,
                          isUploading: isUploading,
                        ),
                      if (_isAdmin) const Spacer() else const Spacer(),
                      _buildBadge('$count jogo${count > 1 ? 's' : ''}'),
                    ],
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: olympusGold.withOpacity(0.14),
                        border: Border.all(
                          color: olympusGold.withOpacity(0.30),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: olympusGold.withOpacity(0.16),
                            blurRadius: 14,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.emoji_events_rounded,
                        color: olympusGold,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              height: 1.2,
                            ),
                          ),
                          const SizedBox(height: 7),
                          if (latestEventName.isNotEmpty)
                            Text(
                              latestEventName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: olympusLightBlue.withOpacity(0.95),
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Icon(
                                Icons.calendar_month_rounded,
                                color: Colors.white.withOpacity(0.60),
                                size: 15,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  latestEventDate.isNotEmpty
                                      ? latestEventDate
                                      : 'Sem data informada',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.66),
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                              if (latestEventTime.isNotEmpty) ...[
                                const SizedBox(width: 10),
                                Icon(
                                  Icons.access_time_rounded,
                                  color: Colors.white.withOpacity(0.60),
                                  size: 15,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  latestEventTime,
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.66),
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.05),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white.withOpacity(0.08),
                        ),
                      ),
                      child: Icon(
                        Icons.arrow_forward_ios_rounded,
                        color: Colors.white.withOpacity(0.74),
                        size: 16,
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

  Widget _buildImageActionButton({
    required Map<String, dynamic> championship,
    required bool isUploading,
  }) {
    return GestureDetector(
      onTap: isUploading
          ? null
          : () => _pickAndSaveChampionshipImage(championship),
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.35),
          shape: BoxShape.circle,
          border: Border.all(
            color: olympusGold.withOpacity(0.35),
          ),
        ),
        child: isUploading
            ? const Padding(
                padding: EdgeInsets.all(10),
                child: CircularProgressIndicator(
                  strokeWidth: 2.2,
                  color: olympusGold,
                ),
              )
            : const Icon(
                Icons.photo_camera_outlined,
                color: Colors.white,
                size: 20,
              ),
      ),
    );
  }

  Widget _buildBadge(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 7,
      ),
      decoration: BoxDecoration(
        color: olympusGold.withOpacity(0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: olympusGold.withOpacity(0.30),
        ),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: olympusGold,
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _buildLoadingState() {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
      children: [
        _buildSearchField(),
        const SizedBox(height: 16),
        _buildSummaryCard(),
        const SizedBox(height: 18),
        ...List.generate(
          4,
          (index) => Container(
            height: 220,
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [
                  Color(0xFF122235),
                  Color(0xFF18324D),
                ],
              ),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: olympusGold.withOpacity(0.18),
              ),
            ),
            child: const Center(
              child: CircularProgressIndicator(
                color: olympusGold,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    final bool hasSearch = _searchController.text.trim().isNotEmpty;

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
      children: [
        _buildSearchField(),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [
                Color(0xFF122235),
                Color(0xFF18324D),
              ],
            ),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: olympusGold.withOpacity(0.22),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.28),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            children: [
              Container(
                width: 82,
                height: 82,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: olympusGold.withOpacity(0.12),
                  border: Border.all(
                    color: olympusGold.withOpacity(0.24),
                  ),
                ),
                child: Icon(
                  hasSearch
                      ? Icons.search_off_rounded
                      : Icons.emoji_events_outlined,
                  color: olympusGold,
                  size: 38,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                hasSearch
                    ? 'Nenhum campeonato encontrado'
                    : 'Nenhum campeonato cadastrado',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                hasSearch
                    ? 'Tente buscar com outro nome.'
                    : 'Cadastre eventos com o campo "Nome do Campeonato/Liga" preenchido para que apareçam aqui.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.66),
                  fontSize: 13.5,
                  fontWeight: FontWeight.w500,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _FuturisticBackgroundPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final wavePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..color = const Color(0xFFD4AF37).withOpacity(0.07)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);

    final wavePaint2 = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..color = const Color(0xFF8FE8FF).withOpacity(0.06)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);

    final path1 = Path();
    path1.moveTo(0, size.height * 0.18);
    path1.cubicTo(
      size.width * 0.20,
      size.height * 0.10,
      size.width * 0.35,
      size.height * 0.28,
      size.width * 0.52,
      size.height * 0.18,
    );
    path1.cubicTo(
      size.width * 0.68,
      size.height * 0.08,
      size.width * 0.82,
      size.height * 0.23,
      size.width,
      size.height * 0.15,
    );
    canvas.drawPath(path1, wavePaint);

    final path2 = Path();
    path2.moveTo(0, size.height * 0.80);
    path2.cubicTo(
      size.width * 0.18,
      size.height * 0.70,
      size.width * 0.36,
      size.height * 0.90,
      size.width * 0.56,
      size.height * 0.80,
    );
    path2.cubicTo(
      size.width * 0.74,
      size.height * 0.72,
      size.width * 0.86,
      size.height * 0.86,
      size.width,
      size.height * 0.78,
    );
    canvas.drawPath(path2, wavePaint2);

    final nodePaint = Paint()
      ..color = const Color(0xFFE8FCFF).withOpacity(0.12)
      ..style = PaintingStyle.fill;

    final linePaint = Paint()
      ..color = const Color(0xFFC7F6FF).withOpacity(0.10)
      ..strokeWidth = 1;

    final points = <Offset>[
      Offset(size.width * 0.72, size.height * 0.34),
      Offset(size.width * 0.82, size.height * 0.38),
      Offset(size.width * 0.90, size.height * 0.33),
      Offset(size.width * 0.76, size.height * 0.44),
      Offset(size.width * 0.88, size.height * 0.47),
      Offset(size.width * 0.69, size.height * 0.52),
      Offset(size.width * 0.83, size.height * 0.56),
      Offset(size.width * 0.93, size.height * 0.52),
      Offset(size.width * 0.73, size.height * 0.64),
      Offset(size.width * 0.86, size.height * 0.67),
    ];

    for (int i = 0; i < points.length - 1; i++) {
      canvas.drawLine(points[i], points[i + 1], linePaint);
    }
    canvas.drawLine(points[0], points[3], linePaint);
    canvas.drawLine(points[1], points[4], linePaint);
    canvas.drawLine(points[3], points[5], linePaint);
    canvas.drawLine(points[4], points[6], linePaint);
    canvas.drawLine(points[6], points[8], linePaint);
    canvas.drawLine(points[7], points[9], linePaint);

    for (final point in points) {
      canvas.drawCircle(point, 1.8, nodePaint);
    }

    final glowPaint = Paint()
      ..color = const Color(0xFFD4AF37).withOpacity(0.05)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 26);

    canvas.drawCircle(
      Offset(size.width * 0.20, size.height * 0.25),
      70,
      glowPaint,
    );
    canvas.drawCircle(
      Offset(size.width * 0.78, size.height * 0.55),
      90,
      glowPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
