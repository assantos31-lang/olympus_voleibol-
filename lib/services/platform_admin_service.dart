import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'organization_feature_service.dart';
import 'permission_service.dart';

class PlatformAdminService {
  PlatformAdminService._();

  static final PlatformAdminService instance = PlatformAdminService._();

  final SupabaseClient _client = Supabase.instance.client;
  bool? _cachedAccess;

  Future<bool> isPlatformAdmin({bool force = false}) async {
    if (!force && _cachedAccess != null) return _cachedAccess!;
    try {
      final result = await _client.rpc('is_platform_admin_v1');
      _cachedAccess = result == true;
    } catch (error) {
      debugPrint('Admin Master ainda nao disponivel: $error');
      _cachedAccess = false;
    }
    return _cachedAccess!;
  }

  Future<List<Map<String, dynamic>>> getOrganizations() async {
    _ensureAuthenticated();
    final responses = await Future.wait<dynamic>([
      _client
          .from('organizations')
          .select('id, slug, name, status, is_active, branding, created_at')
          .order('name'),
      _client.from('organization_subscriptions').select(
            'organization_id, plan_code, status, max_users, max_storage_mb, trial_ends_at, current_period_ends_at',
          ),
    ]);
    final organizations = List<Map<String, dynamic>>.from(responses[0] as List);
    final subscriptions = List<Map<String, dynamic>>.from(responses[1] as List);
    var dashboard = <String, dynamic>{};
    try {
      final result = await _client.rpc('platform_organization_dashboard_v1');
      dashboard = Map<String, dynamic>.from(result as Map);
    } catch (error) {
      debugPrint('Indicadores da Fase 9 ainda nao disponiveis: $error');
    }
    final subscriptionsByOrganization = <String, Map<String, dynamic>>{
      for (final item in subscriptions)
        (item['organization_id'] ?? '').toString(): item,
    };

    return organizations
        .map(
          (organization) => <String, dynamic>{
            ...organization,
            'subscription': subscriptionsByOrganization[
                    (organization['id'] ?? '').toString()] ??
                const <String, dynamic>{},
            'metrics': Map<String, dynamic>.from(
              dashboard[(organization['id'] ?? '').toString()] as Map? ??
                  const <String, dynamic>{},
            ),
          },
        )
        .toList();
  }

  Future<Map<String, dynamic>> renewAdminInvitation(
    String invitationId, {
    int days = 30,
  }) async {
    final result = await _client.rpc(
      'platform_renew_admin_invitation_v1',
      params: {'p_invitation_id': invitationId, 'p_days': days},
    );
    return Map<String, dynamic>.from(result as Map);
  }

  Future<void> cancelAdminInvitation(String invitationId) async {
    await _client.rpc(
      'platform_cancel_admin_invitation_v1',
      params: {'p_invitation_id': invitationId},
    );
  }

  Future<Map<String, dynamic>> replaceAdminInvitation({
    required String organizationId,
    required String adminEmail,
    int days = 30,
  }) async {
    final result = await _client.rpc(
      'platform_replace_admin_invitation_v1',
      params: {
        'p_organization_id': organizationId,
        'p_admin_email': adminEmail.trim().toLowerCase(),
        'p_days': days,
      },
    );
    return Map<String, dynamic>.from(result as Map);
  }

  Future<List<Map<String, dynamic>>> getFeatureCatalog() async {
    return List<Map<String, dynamic>>.from(
      await _client
          .from('platform_features')
          .select(
            'key, name, description, category, default_enabled, sort_order',
          )
          .eq('is_active', true)
          .order('sort_order'),
    );
  }

  Future<Map<String, Map<String, dynamic>>> getOrganizationFeatures(
    String organizationId,
  ) async {
    final response = List<Map<String, dynamic>>.from(
      await _client
          .from('organization_features')
          .select('feature_key, enabled, limits')
          .eq('organization_id', organizationId),
    );
    return <String, Map<String, dynamic>>{
      for (final item in response) (item['feature_key'] ?? '').toString(): item,
    }..remove('');
  }

  Future<List<Map<String, dynamic>>> getOrganizationAdmins(
    String organizationId,
  ) async {
    final result = await _client.rpc(
      'platform_organization_admins_v1',
      params: {'p_organization_id': organizationId},
    );
    return List<Map<String, dynamic>>.from(result as List);
  }

  Future<String> resetUserPassword(String userId) async {
    final session = _client.auth.currentSession;
    if (session == null) {
      throw StateError('Sessao expirada. Entre novamente.');
    }
    final response = await _client.functions.invoke(
      'reset-user-password',
      headers: {'Authorization': 'Bearer ${session.accessToken}'},
      body: {'user_id': userId},
    );
    if (response.status < 200 || response.status >= 300) {
      final data = response.data;
      final message = data is Map ? data['error'] : null;
      throw StateError('${message ?? 'Nao foi possivel redefinir a senha.'}');
    }
    final data = response.data;
    final password = data is Map ? '${data['password'] ?? ''}' : '';
    if (password.isEmpty) {
      throw StateError('O Supabase nao retornou a senha temporaria.');
    }
    return password;
  }

  Future<void> createInvitedAdminAccount({
    required String organizationId,
    required String email,
    required String password,
  }) async {
    final session = _client.auth.currentSession;
    if (session == null) {
      throw StateError('Sessao expirada. Entre novamente.');
    }
    final response = await _client.functions.invoke(
      'create-club-admin',
      headers: {'Authorization': 'Bearer ${session.accessToken}'},
      body: {
        'organization_id': organizationId,
        'email': email.trim().toLowerCase(),
        'password': password,
      },
    );
    if (response.status < 200 || response.status >= 300) {
      final data = response.data;
      final message = data is Map ? data['error'] : null;
      throw StateError('${message ?? 'Nao foi possivel criar o acesso.'}');
    }
  }

  Future<Map<String, dynamic>> createOrganization({
    required String name,
    required String slug,
    required String planCode,
    required int maxUsers,
    required String adminEmail,
    required String adminPassword,
    required List<String> enabledFeatures,
    required Map<String, dynamic> branding,
  }) async {
    final result = await _client.rpc(
      'platform_onboard_organization_v2',
      params: {
        'p_name': name,
        'p_slug': slug,
        'p_plan_code': planCode,
        'p_max_users': maxUsers,
        'p_admin_email': adminEmail,
        'p_enabled_features': enabledFeatures,
        'p_branding': branding,
      },
    );
    final organization = Map<String, dynamic>.from(result as Map);
    final organizationId = '${organization['organization_id'] ?? ''}';
    if (organizationId.isEmpty) {
      throw StateError('O banco nao retornou o identificador do novo clube.');
    }

    final session = _client.auth.currentSession;
    if (session == null) {
      throw StateError(
        'Clube criado, mas a sessao expirou antes de criar o administrador.',
      );
    }

    try {
      await createInvitedAdminAccount(
        organizationId: organizationId,
        email: adminEmail,
        password: adminPassword,
      );
    } catch (error) {
      throw StateError(
        'O clube foi criado, mas a conta do administrador nao: $error',
      );
    }

    return {
      ...organization,
      'admin_account_created': true,
      'temporary_password': adminPassword,
    };
  }

  Future<void> setFeature({
    required String organizationId,
    required String featureKey,
    required bool enabled,
    Map<String, dynamic> limits = const {},
  }) async {
    await _client.rpc(
      'platform_set_feature_v1',
      params: {
        'p_organization_id': organizationId,
        'p_feature_key': featureKey,
        'p_enabled': enabled,
        'p_limits': limits,
      },
    );
    OrganizationFeatureService.instance.invalidate();
    PermissionService.clearCache();
  }

  Future<void> updateOrganization({
    required String organizationId,
    required String organizationStatus,
    required String subscriptionStatus,
    required String planCode,
    required int maxUsers,
  }) async {
    await _client.rpc(
      'platform_update_organization_v1',
      params: {
        'p_organization_id': organizationId,
        'p_organization_status': organizationStatus,
        'p_subscription_status': subscriptionStatus,
        'p_plan_code': planCode,
        'p_max_users': maxUsers,
      },
    );
    OrganizationFeatureService.instance.invalidate();
    PermissionService.clearCache();
  }

  void clearAccessCache() => _cachedAccess = null;

  void _ensureAuthenticated() {
    if (_client.auth.currentUser == null) {
      throw StateError('Usuario nao autenticado.');
    }
  }
}
