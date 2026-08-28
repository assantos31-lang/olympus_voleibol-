import 'package:supabase_flutter/supabase_flutter.dart';

import 'organization_context_service.dart';

class TechnicalStaffRole {
  const TechnicalStaffRole._();

  static const coordinator = 'technical_coordinator';
  static const headCoach = 'head_coach';
  static const assistantCoach = 'assistant_coach';
  static const intern = 'intern';

  static const values = <String>[
    coordinator,
    headCoach,
    assistantCoach,
    intern,
  ];

  static const labels = <String, String>{
    coordinator: 'Coordenador Técnico',
    headCoach: 'Treinador Responsável',
    assistantCoach: 'Treinador Assistente',
    intern: 'Estagiário',
  };

  static String label(String value) => labels[value] ?? value;
}

class TechnicalStaffAssignment {
  const TechnicalStaffAssignment({
    required this.id,
    required this.organizationId,
    required this.userId,
    required this.technicalRole,
    required this.teamScope,
    required this.canCreateTraining,
    required this.canPublishTraining,
    required this.canApproveTraining,
    required this.canManageStaff,
    required this.status,
    this.supervisorUserId,
  });

  final String id;
  final String organizationId;
  final String userId;
  final String technicalRole;
  final String? supervisorUserId;
  final String teamScope;
  final bool canCreateTraining;
  final bool canPublishTraining;
  final bool canApproveTraining;
  final bool canManageStaff;
  final String status;

  bool get isActive => status == 'active';
  bool get isCoordinator =>
      technicalRole == TechnicalStaffRole.coordinator && isActive;

  factory TechnicalStaffAssignment.fromMap(Map<String, dynamic> map) {
    return TechnicalStaffAssignment(
      id: (map['id'] ?? '').toString(),
      organizationId: (map['organization_id'] ?? '').toString(),
      userId: (map['user_id'] ?? '').toString(),
      technicalRole: (map['technical_role'] ?? '').toString(),
      supervisorUserId: map['supervisor_user_id']?.toString(),
      teamScope: (map['team_scope'] ?? 'all').toString(),
      canCreateTraining: map['can_create_training'] == true,
      canPublishTraining: map['can_publish_training'] == true,
      canApproveTraining: map['can_approve_training'] == true,
      canManageStaff: map['can_manage_staff'] == true,
      status: (map['status'] ?? 'active').toString(),
    );
  }
}

class TechnicalStaffService {
  TechnicalStaffService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  String get _organizationId => OrganizationContextService.instance.currentId;

  Future<List<Map<String, dynamic>>> loadAvailableProfiles() async {
    dynamic rows;
    var loadedFromDirectory = false;
    try {
      rows = await _client.rpc('get_technical_staff_directory_v1');
      loadedFromDirectory = true;
    } catch (_) {
      rows = await _client
          .from('profiles')
          .select('id, full_name, email, avatar_url, user_type, is_active')
          .eq('organization_id', _organizationId)
          .eq('is_active', true)
          .order('full_name');
    }
    final profiles = List<Map<String, dynamic>>.from(rows);
    if (loadedFromDirectory) {
      return profiles;
    }
    final coachUserIds = <String>{};

    try {
      final roleRows = await _client
          .from('user_roles')
          .select('user_id, role')
          .eq('organization_id', _organizationId)
          .eq('is_active', true)
          .eq('role', 'coach');
      for (final row in List<Map<String, dynamic>>.from(roleRows)) {
        final userId = (row['user_id'] ?? '').toString().trim();
        if (userId.isNotEmpty) coachUserIds.add(userId);
      }
    } catch (_) {
      // Contas antigas continuam sendo reconhecidas pelo papel principal.
    }

    return profiles.where((profile) {
      final userId = (profile['id'] ?? '').toString();
      final primaryRole =
          (profile['user_type'] ?? '').toString().trim().toLowerCase();
      final isCoachProfile = const {
        'coach',
        'treinador',
        'tecnico',
        'técnico',
      }.contains(primaryRole);
      return isCoachProfile || coachUserIds.contains(userId);
    }).toList();
  }

  Future<List<TechnicalStaffAssignment>> loadAssignments({
    bool includeInactive = false,
  }) async {
    var query = _client
        .from('technical_staff_assignments')
        .select()
        .eq('organization_id', _organizationId);
    if (!includeInactive) query = query.eq('status', 'active');
    final rows = await query.order('technical_role').order('created_at');
    return List<Map<String, dynamic>>.from(rows)
        .map(TechnicalStaffAssignment.fromMap)
        .toList();
  }

  Future<TechnicalStaffAssignment?> loadCurrentAssignment() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return null;
    final row = await _client
        .from('technical_staff_assignments')
        .select()
        .eq('organization_id', _organizationId)
        .eq('user_id', userId)
        .eq('status', 'active')
        .maybeSingle();
    return row == null ? null : TechnicalStaffAssignment.fromMap(row);
  }

  Future<void> saveAssignment({
    required String userId,
    required String technicalRole,
    String? supervisorUserId,
    required String teamScope,
    required bool canCreateTraining,
    required bool canPublishTraining,
    required bool canApproveTraining,
    required bool canManageStaff,
  }) async {
    if (!TechnicalStaffRole.values.contains(technicalRole)) {
      throw ArgumentError('Função técnica inválida.');
    }
    final currentUserId = _client.auth.currentUser?.id;
    if (currentUserId == null) throw StateError('Usuário não autenticado.');

    await _client.rpc('admin_set_technical_staff_v1', params: {
      'p_user_id': userId,
      'p_technical_role': technicalRole,
      'p_supervisor_user_id': technicalRole == TechnicalStaffRole.coordinator
          ? null
          : supervisorUserId,
      'p_team_scope': teamScope,
      'p_can_create_training': canCreateTraining,
      'p_can_publish_training': canPublishTraining,
      'p_can_approve_training': canApproveTraining,
      'p_can_manage_staff': canManageStaff,
    });
  }

  Future<void> setStatus(String userId, String status) async {
    await _client
        .from('technical_staff_assignments')
        .update({
          'status': status,
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('organization_id', _organizationId)
        .eq('user_id', userId);
  }
}
