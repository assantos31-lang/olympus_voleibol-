import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:math';

class CheckInPage extends StatefulWidget {
  const CheckInPage({super.key});

  @override
  State<CheckInPage> createState() => _CheckInPageState();
}

class _CheckInPageState extends State<CheckInPage> {
  bool _isLoading = true;
  bool _isCheckingIn = false;
  List<Map<String, dynamic>> _myEvents = [];
  Position? _currentPosition;
  String? _locationError;

  @override
  void initState() {
    super.initState();
    _fetchMyEvents();
    _getCurrentLocation();
  }

  Future<void> _getCurrentLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() {
          _locationError = 'Serviço de localização desativado';
        });
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          setState(() {
            _locationError = 'Permissão de localização negada';
          });
          return;
        }
      }

      _currentPosition = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
    } catch (e) {
      setState(() {
        _locationError = 'Erro ao obter localização: ${e.toString()}';
      });
    }
  }

  // ✅ NOVO: Método para forçar atualização da posição GPS
  Future<Position?> _forceRefreshLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return null;

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return null;
      }

      // ✅ Força obtenção de nova posição (ignora cache)
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        forceAndroidLocationManager: true, // ✅ Força GPS real no Android
      );

      setState(() {
        _currentPosition = position;
      });

      return position;
    } catch (e) {
      print('Erro ao forçar atualização de localização: $e');
      return null;
    }
  }

  Future<void> _fetchMyEvents() async {
    try {
      final supabase = Supabase.instance.client;
      final user = supabase.auth.currentUser;

      if (user == null) {
        setState(() => _isLoading = false);
        return;
      }

      // Busca checkins do usuário
      final response = await supabase
          .from('checkins')
          .select('*, events(*)')
          .eq('user_id', user.id);

      setState(() {
        _myEvents = List<Map<String, dynamic>>.from(response);
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      _showError('Erro ao carregar eventos: ${e.toString()}');
    }
  }

  double _calculateDistance(
      double lat1, double lon1, double lat2, double lon2) {
    const p = 0.017453292519943295;
    const c = cos;
    final a = 0.5 -
        c((lat2 - lat1) * p) / 2 +
        c(lat1 * p) * c(lat2 * p) * (1 - c((lon2 - lon1) * p)) / 2;
    return 12742 * asin(sqrt(a));
  }

  Future<void> _doCheckIn(String eventId, String eventName) async {
    // ✅ CORREÇÃO PRINCIPAL: Força atualização da posição ANTES do check-in
    final freshPosition = await _forceRefreshLocation();

    if (freshPosition == null && _currentPosition == null) {
      _showError('Localização não disponível. Tente novamente.');
      return;
    }

    // Usa a posição mais recente
    final positionToUse = freshPosition ?? _currentPosition!;

    setState(() => _isCheckingIn = true);

    try {
      final supabase = Supabase.instance.client;
      final user = supabase.auth.currentUser;

      if (user == null) {
        _showError('Usuário não autenticado');
        setState(() => _isCheckingIn = false);
        return;
      }

      // Busca dados do evento para validar localização
      final eventResponse = await supabase
          .from('events')
          .select('latitude, longitude, allow_checkin')
          .eq('id', eventId)
          .single();

      if (eventResponse['allow_checkin'] != true) {
        _showError('Check-in não está habilitado para este evento');
        setState(() => _isCheckingIn = false);
        return;
      }

      // Verifica se já fez check-in
      final existingCheckIn = await supabase
          .from('checkins')
          .select()
          .eq('event_id', eventId)
          .eq('user_id', user.id)
          .maybeSingle();

      if (existingCheckIn != null) {
        _showError('Você já fez check-in neste evento!');
        setState(() => _isCheckingIn = false);
        return;
      }

      // Valida distância (máximo 100 metros do local do evento)
      // Se o evento não tiver latitude/longitude, permite check-in
      if (eventResponse['latitude'] != null &&
          eventResponse['longitude'] != null) {
        final distance = _calculateDistance(
          positionToUse.latitude,
          positionToUse.longitude,
          eventResponse['latitude'],
          eventResponse['longitude'],
        );

        // distance está em km, converter para metros
        if (distance * 1000 > 100) {
          _showError(
            'Você está muito longe do local do evento!\n'
            'Distância: ${(distance * 1000).toStringAsFixed(0)}m\n'
            'Máximo permitido: 100m',
          );
          setState(() => _isCheckingIn = false);
          return;
        }
      }

      // Atualiza check-in com localização
      await supabase
          .from('checkins')
          .update({
            'checked_in_at': DateTime.now().toIso8601String(),
            'check_in_latitude': positionToUse.latitude,
            'check_in_longitude': positionToUse.longitude,
            'check_in_status': 'confirmed',
          })
          .eq('event_id', eventId)
          .eq('user_id', user.id);

      setState(() => _isCheckingIn = false);
      _showSuccess('Check-in realizado com sucesso!');
      _fetchMyEvents();
    } catch (e) {
      setState(() => _isCheckingIn = false);
      _showError('Erro ao fazer check-in: ${e.toString()}');
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red.shade700,
      ),
    );
  }

  void _showSuccess(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green.shade700,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Meus Eventos - Check-in'),
        backgroundColor: const Color(0xFF0A2463),
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _myEvents.isEmpty
              ? const Center(
                  child: Text(
                    'Nenhum evento encontrado',
                    style: TextStyle(fontSize: 16, color: Colors.grey),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: () async {
                    await _fetchMyEvents();
                    await _getCurrentLocation();
                  },
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _myEvents.length,
                    itemBuilder: (context, index) {
                      final checkIn = _myEvents[index];
                      final event = checkIn['events'] as Map<String, dynamic>;
                      final isCheckedIn =
                          checkIn['check_in_status'] == 'confirmed';

                      return Card(
                        margin: const EdgeInsets.only(bottom: 16),
                        elevation: 4,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isCheckedIn
                                  ? Colors.green
                                  : const Color(0xFFD4AF37),
                              width: 2,
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      isCheckedIn
                                          ? Icons.check_circle
                                          : Icons.event,
                                      color: isCheckedIn
                                          ? Colors.green
                                          : const Color(0xFFD4AF37),
                                      size: 32,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            event['event_name'] ?? 'Evento',
                                            style: const TextStyle(
                                              fontSize: 18,
                                              fontWeight: FontWeight.bold,
                                              color: Color(0xFF0A2463),
                                            ),
                                          ),
                                          Text(
                                            event['event_type'] ?? '',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.grey[600],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                _buildInfoRow(
                                  Icons.calendar_today,
                                  '${event['event_date']} às ${event['event_time']}',
                                ),
                                if (event['street'] != null)
                                  _buildInfoRow(
                                    Icons.location_on,
                                    '${event['street']}, ${event['street_number']} - ${event['neighborhood']}',
                                  ),
                                const SizedBox(height: 16),
                                if (isCheckedIn)
                                  Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: Colors.green.shade50,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(
                                          Icons.check_circle_outline,
                                          color: Colors.green,
                                        ),
                                        const SizedBox(width: 8),
                                        const Text(
                                          'Check-in realizado!',
                                          style: TextStyle(
                                            color: Colors.green,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  )
                                else
                                  ElevatedButton.icon(
                                    onPressed: _isCheckingIn
                                        ? null
                                        : () => _doCheckIn(
                                              event['id'],
                                              event['event_name'],
                                            ),
                                    icon: _isCheckingIn
                                        ? const SizedBox(
                                            width: 20,
                                            height: 20,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: Colors.white,
                                            ),
                                          )
                                        : const Icon(Icons.check),
                                    label: Text(_isCheckingIn
                                        ? 'Verificando...'
                                        : 'Fazer Check-in'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFFD4AF37),
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 12,
                                        horizontal: 16,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }

  Widget _buildInfoRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.grey[600]),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: Colors.grey[700],
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
