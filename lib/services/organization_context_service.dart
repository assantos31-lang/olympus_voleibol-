import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

@immutable
class OrganizationContext {
  const OrganizationContext({
    required this.id,
    required this.slug,
    required this.name,
    required this.role,
    required this.isActive,
    this.branding = const <String, dynamic>{},
  });

  final String id;
  final String slug;
  final String name;
  final String role;
  final bool isActive;
  final Map<String, dynamic> branding;

  bool get canManage => role == 'owner' || role == 'admin';

  factory OrganizationContext.fromMap(Map<String, dynamic> map) {
    final rawBranding = map['branding'];
    return OrganizationContext(
      id: (map['id'] ?? '').toString(),
      slug: (map['slug'] ?? '').toString(),
      name: (map['name'] ?? '').toString(),
      role: (map['role'] ?? 'member').toString().toLowerCase(),
      isActive: map['is_active'] != false,
      branding: rawBranding is Map
          ? Map<String, dynamic>.from(rawBranding)
          : const <String, dynamic>{},
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'slug': slug,
        'name': name,
        'role': role,
        'is_active': isActive,
        'branding': branding,
      };
}

class OrganizationContextService extends ChangeNotifier {
  OrganizationContextService._();

  static final OrganizationContextService instance =
      OrganizationContextService._();

  static const String olympusOrganizationId =
      '00000000-0000-4000-8000-000000000001';
  static const String _lastContextKey = 'organization_context_last_v1';

  final SupabaseClient _client = Supabase.instance.client;
  OrganizationContext? _current;
  String? _contextUserId;
  Future<OrganizationContext?>? _initialization;

  OrganizationContext? get current => _current;
  String get currentId => _current?.id ?? olympusOrganizationId;
  String get currentName => _current?.name ?? 'Olympus Voleibol';
  String get currentRole => _current?.role ?? 'member';
  bool get canManage => _current?.canManage ?? false;

  Future<OrganizationContext?> initialize({bool force = false}) {
    if (!force && _initialization != null) return _initialization!;
    final operation = _load();
    _initialization = operation;
    return operation;
  }

  Future<OrganizationContext?> _load() async {
    await _restoreCachedContext();

    final user = _client.auth.currentUser;
    if (user == null) return _current;

    try {
      final rpcValue = await _client.rpc('current_organization_id');
      var organizationId = rpcValue?.toString().trim() ?? '';

      if (organizationId.isEmpty || organizationId == 'null') {
        final profile = await _client
            .from('profiles')
            .select('organization_id')
            .eq('id', user.id)
            .maybeSingle();
        organizationId = (profile?['organization_id'] ?? '').toString().trim();
      }

      if (organizationId.isEmpty) {
        debugPrint('Usuário autenticado ainda não possui clube ativo.');
        return _current;
      }

      final membership = await _client
          .from('organization_members')
          .select('role, status')
          .eq('organization_id', organizationId)
          .eq('user_id', user.id)
          .maybeSingle();

      final organization = await _client
          .from('organizations')
          .select('id, slug, name, is_active, branding')
          .eq('id', organizationId)
          .maybeSingle();

      if (organization == null || membership == null) return _current;
      if ((membership['status'] ?? '').toString() != 'active') return _current;

      final next = OrganizationContext.fromMap({
        ...organization,
        'role': membership['role'],
      });
      await _setCurrent(next, persist: true);
      return next;
    } catch (error) {
      debugPrint('Não foi possível carregar o clube ativo: $error');
      return _current;
    }
  }

  Future<void> _restoreCachedContext() async {
    final authenticatedUserId = _client.auth.currentUser?.id;
    if (_current != null &&
        (authenticatedUserId == null ||
            _contextUserId == authenticatedUserId)) {
      return;
    }

    if (authenticatedUserId != null &&
        _contextUserId != null &&
        _contextUserId != authenticatedUserId) {
      _current = null;
      _contextUserId = null;
      notifyListeners();
    }

    try {
      final preferences = await SharedPreferences.getInstance();
      final raw = preferences.getString(_lastContextKey);
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        final map = Map<String, dynamic>.from(decoded);
        final cachedUserId = (map['_user_id'] ?? '').toString();
        if (authenticatedUserId != null &&
            cachedUserId != authenticatedUserId) {
          return;
        }
        _contextUserId = cachedUserId.isEmpty ? null : cachedUserId;
        await _setCurrent(
          OrganizationContext.fromMap(map),
          persist: false,
        );
      }
    } catch (error) {
      debugPrint('Não foi possível restaurar o clube em cache: $error');
    }
  }

  Future<void> _setCurrent(
    OrganizationContext value, {
    required bool persist,
  }) async {
    final changed = _current?.id != value.id ||
        _current?.name != value.name ||
        _current?.role != value.role ||
        !mapEquals(_current?.branding, value.branding);
    _current = value;
    _contextUserId ??= _client.auth.currentUser?.id;

    if (persist) {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(
        _lastContextKey,
        jsonEncode({
          ...value.toMap(),
          '_user_id': _client.auth.currentUser?.id,
        }),
      );
    }

    if (changed) notifyListeners();
  }

  Future<OrganizationContext?> refresh() => initialize(force: true);

  Future<void> reset() async {
    _current = null;
    _contextUserId = null;
    _initialization = null;
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_lastContextKey);
    notifyListeners();
  }
}
