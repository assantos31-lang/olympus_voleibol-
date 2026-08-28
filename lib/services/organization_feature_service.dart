import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'organization_context_service.dart';

class OrganizationFeatureService {
  OrganizationFeatureService._();

  static final OrganizationFeatureService instance =
      OrganizationFeatureService._();

  final SupabaseClient _client = Supabase.instance.client;
  static const Duration _cacheDuration = Duration(minutes: 2);

  String? _cachedOrganizationId;
  Map<String, bool> _cachedFeatures = const {};
  DateTime? _expiresAt;
  Future<Map<String, bool>>? _inFlight;

  Future<Map<String, bool>> getFeatures({bool force = false}) async {
    final organizationService = OrganizationContextService.instance;
    await organizationService.initialize();
    final organizationId = organizationService.currentId;
    final now = DateTime.now();

    if (!force &&
        _cachedOrganizationId == organizationId &&
        _expiresAt?.isAfter(now) == true) {
      return Map<String, bool>.from(_cachedFeatures);
    }

    if (!force && _inFlight != null) {
      return Map<String, bool>.from(await _inFlight!);
    }

    final request = _load(organizationId);
    _inFlight = request;
    try {
      final features = await request;
      _cachedOrganizationId = organizationId;
      _cachedFeatures = Map<String, bool>.unmodifiable(features);
      _expiresAt = now.add(_cacheDuration);
      return Map<String, bool>.from(features);
    } finally {
      if (identical(_inFlight, request)) _inFlight = null;
    }
  }

  Future<Map<String, bool>> _load(String organizationId) async {
    try {
      final response = await _client
          .from('organization_features')
          .select('feature_key, enabled')
          .eq('organization_id', organizationId);
      return <String, bool>{
        for (final item in response)
          (item['feature_key'] ?? '').toString(): item['enabled'] != false,
      }..remove('');
    } catch (error) {
      // Compatibilidade durante a implantacao: se a migracao ainda nao estiver
      // aplicada, nenhum modulo existente e bloqueado.
      debugPrint('Catalogo de funcionalidades indisponivel: $error');
      return const <String, bool>{};
    }
  }

  Future<bool> isEnabled(String featureKey) async {
    final features = await getFeatures();
    return features[featureKey] ?? true;
  }

  void invalidate() {
    _cachedOrganizationId = null;
    _cachedFeatures = const {};
    _expiresAt = null;
    _inFlight = null;
  }
}
