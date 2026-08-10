import 'package:supabase_flutter/supabase_flutter.dart';

class FinancialAccessStatus {
  const FinancialAccessStatus({
    required this.enforcementEnabled,
    required this.selectedForBlock,
    required this.blocked,
    required this.overdueCount,
    required this.overdueAmount,
  });

  final bool enforcementEnabled;
  final bool selectedForBlock;
  final bool blocked;
  final int overdueCount;
  final double overdueAmount;

  factory FinancialAccessStatus.fromMap(Map<String, dynamic> map) {
    return FinancialAccessStatus(
      enforcementEnabled: map['enforcement_enabled'] == true,
      selectedForBlock: map['selected_for_block'] == true,
      blocked: map['blocked'] == true,
      overdueCount: (map['overdue_count'] as num?)?.toInt() ?? 0,
      overdueAmount: (map['overdue_amount'] as num?)?.toDouble() ?? 0,
    );
  }

  static const unrestricted = FinancialAccessStatus(
    enforcementEnabled: false,
    selectedForBlock: false,
    blocked: false,
    overdueCount: 0,
    overdueAmount: 0,
  );
}

class OverdueAthleteBlockCandidate {
  const OverdueAthleteBlockCandidate({
    required this.athleteId,
    required this.fullName,
    required this.avatarUrl,
    required this.overdueCount,
    required this.overdueAmount,
    required this.isBlocked,
    required this.isAdmin,
  });

  final String athleteId;
  final String fullName;
  final String? avatarUrl;
  final int overdueCount;
  final double overdueAmount;
  final bool isBlocked;
  final bool isAdmin;

  factory OverdueAthleteBlockCandidate.fromMap(Map<String, dynamic> map) {
    final avatar = map['avatar_url']?.toString().trim();
    return OverdueAthleteBlockCandidate(
      athleteId: map['athlete_id']?.toString() ?? '',
      fullName: map['full_name']?.toString().trim().isNotEmpty == true
          ? map['full_name'].toString().trim()
          : 'Atleta',
      avatarUrl: avatar == null || avatar.isEmpty ? null : avatar,
      overdueCount: (map['overdue_count'] as num?)?.toInt() ?? 0,
      overdueAmount: (map['overdue_amount'] as num?)?.toDouble() ?? 0,
      isBlocked: map['is_blocked'] == true,
      isAdmin: map['is_admin'] == true,
    );
  }

  OverdueAthleteBlockCandidate copyWith({bool? isBlocked}) {
    return OverdueAthleteBlockCandidate(
      athleteId: athleteId,
      fullName: fullName,
      avatarUrl: avatarUrl,
      overdueCount: overdueCount,
      overdueAmount: overdueAmount,
      isBlocked: isBlocked ?? this.isBlocked,
      isAdmin: isAdmin,
    );
  }
}

class FinancialAccessService {
  FinancialAccessService({SupabaseClient? client})
    : _supabase = client ?? Supabase.instance.client;

  final SupabaseClient _supabase;

  Future<FinancialAccessStatus> getCurrentAccessStatus() async {
    if (_supabase.auth.currentUser == null) {
      return FinancialAccessStatus.unrestricted;
    }
    final result = await _supabase.rpc('get_my_financial_access_v1');
    if (result is Map) {
      return FinancialAccessStatus.fromMap(Map<String, dynamic>.from(result));
    }
    return FinancialAccessStatus.unrestricted;
  }

  Future<bool> getBlockOverdueAthletes() async {
    final row = await _supabase
        .from('financial_access_settings')
        .select('block_overdue_athletes')
        .eq('id', true)
        .maybeSingle();
    return row?['block_overdue_athletes'] == true;
  }

  Future<void> setBlockOverdueAthletes(bool enabled) async {
    await _supabase.from('financial_access_settings').upsert({
      'id': true,
      'block_overdue_athletes': enabled,
      'updated_by': _supabase.auth.currentUser?.id,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  Future<List<OverdueAthleteBlockCandidate>>
  getOverdueAthleteBlockCandidates() async {
    final result = await _supabase.rpc('list_overdue_athlete_blocks_v1');
    if (result is! List) return const <OverdueAthleteBlockCandidate>[];
    return result
        .whereType<Map>()
        .map(
          (row) => OverdueAthleteBlockCandidate.fromMap(
            Map<String, dynamic>.from(row),
          ),
        )
        .where((candidate) => candidate.athleteId.isNotEmpty)
        .toList(growable: false);
  }

  Future<void> setAthleteTrainingBlocked({
    required String athleteId,
    required bool blocked,
  }) async {
    await _supabase.rpc(
      'set_overdue_athlete_block_v1',
      params: {'p_athlete_id': athleteId, 'p_blocked': blocked},
    );
  }
}

