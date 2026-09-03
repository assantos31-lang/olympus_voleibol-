import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/award_models.dart';
import 'organization_context_service.dart';

class AwardsService {
  AwardsService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Future<bool> hasPublishedAwards() async {
    try {
      final organization =
          await OrganizationContextService.instance.initialize();
      if (organization == null) return false;
      final rows = await _client
          .from('award_editions')
          .select('id')
          .eq('organization_id', organization.id)
          .eq('is_published', true)
          .eq('is_visible', true)
          .limit(1);
      return (rows as List).isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<List<AwardDefinition>> loadDefinitions({
    required bool canManage,
  }) async {
    final organization =
        await OrganizationContextService.instance.initialize(force: true);
    if (organization == null) return const [];
    dynamic query = _client
        .from('award_definitions')
        .select()
        .eq('organization_id', organization.id);
    if (!canManage) {
      query = query.eq('is_visible', true);
    }
    final rows = await query.order('sort_order').order('created_at');
    return List<Map<String, dynamic>>.from(rows)
        .map(AwardDefinition.fromMap)
        .toList();
  }

  Future<List<AwardEdition>> loadEditions({required bool canManage}) async {
    final organization =
        await OrganizationContextService.instance.initialize(force: true);
    if (organization == null) return const [];

    final definitions = await loadDefinitions(canManage: canManage);
    final byId = {for (final item in definitions) item.id: item};
    dynamic query = _client
        .from('award_editions')
        .select()
        .eq('organization_id', organization.id);
    if (!canManage) {
      query = query.eq('is_published', true).eq('is_visible', true);
    }
    final editionRows = await query
        .order('period_year', ascending: false)
        .order('period_month', ascending: false)
        .order('created_at', ascending: false);
    final rows = List<Map<String, dynamic>>.from(editionRows as List);
    if (rows.isEmpty) return const [];

    final editionIds = rows.map((row) => row['id'].toString()).toList();
    final winnerRows = await _client
        .from('award_winners')
        .select()
        .inFilter('award_edition_id', editionIds)
        .order('position');
    final winnersByEdition = <String, List<AwardWinner>>{};
    for (final row in List<Map<String, dynamic>>.from(winnerRows)) {
      winnersByEdition
          .putIfAbsent(row['award_edition_id'].toString(), () => [])
          .add(AwardWinner.fromMap(row));
    }

    return rows
        .map((row) {
          final definition = byId[row['award_definition_id'].toString()];
          if (definition == null) return null;
          final rawDate = (row['delivery_date'] ?? '').toString();
          return AwardEdition(
            id: row['id'].toString(),
            definition: definition,
            year: (row['period_year'] as num).toInt(),
            month: (row['period_month'] as num).toInt(),
            caption: (row['caption'] ?? '').toString(),
            deliveryDate: rawDate.isEmpty ? null : DateTime.tryParse(rawDate),
            deliveryPhotoUrl: (row['delivery_photo_url'] ?? '').toString(),
            isPublished: row['is_published'] == true,
            isVisible: row['is_visible'] != false,
            winners: winnersByEdition[row['id'].toString()] ?? const [],
          );
        })
        .whereType<AwardEdition>()
        .toList();
  }

  Future<List<Map<String, dynamic>>> loadEligibleProfiles() async {
    final rows = await _client
        .from('profiles')
        .select('id, full_name, avatar_url, user_type, is_active')
        .eq('is_active', true)
        .order('full_name');
    return List<Map<String, dynamic>>.from(rows);
  }

  Future<void> saveDefinition({
    String? id,
    required String title,
    required String description,
    required String sourceType,
    required int winnerCount,
    required bool isVisible,
    String coverImageUrl = '',
  }) async {
    final organization =
        await OrganizationContextService.instance.initialize(force: true);
    if (organization == null) throw StateError('Clube ativo não encontrado.');
    final payload = <String, dynamic>{
      'organization_id': organization.id,
      'title': title.trim(),
      'description': description.trim(),
      'source_type': sourceType,
      'winner_count': winnerCount,
      'is_visible': isVisible,
      'cover_image_url': coverImageUrl.trim().isEmpty ? null : coverImageUrl,
      'updated_at': DateTime.now().toIso8601String(),
    };
    if (id == null) {
      payload['created_by'] = _client.auth.currentUser?.id;
      await _client.from('award_definitions').insert(payload);
    } else {
      await _client.from('award_definitions').update(payload).eq('id', id);
    }
  }

  Future<void> deleteDefinition(String id) async {
    final definition = await _client
        .from('award_definitions')
        .select('cover_image_url')
        .eq('id', id)
        .maybeSingle();
    final editions = await _client
        .from('award_editions')
        .select('delivery_photo_url')
        .eq('award_definition_id', id);
    await _client.from('award_definitions').delete().eq('id', id);
    await _removeImageUrl((definition?['cover_image_url'] ?? '').toString());
    for (final row in List<Map<String, dynamic>>.from(editions)) {
      await _removeImageUrl((row['delivery_photo_url'] ?? '').toString());
    }
  }

  Future<void> setDefinitionVisible(String id, bool value) async {
    await _client.from('award_definitions').update({
      'is_visible': value,
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', id);
  }

  Future<void> saveEdition({
    String? id,
    required AwardDefinition definition,
    required int year,
    required int month,
    required String caption,
    required DateTime? deliveryDate,
    required String deliveryPhotoUrl,
    required bool isPublished,
    required bool isVisible,
    required List<Map<String, dynamic>> winners,
  }) async {
    final organization =
        await OrganizationContextService.instance.initialize(force: true);
    if (organization == null) throw StateError('Clube ativo não encontrado.');
    final payload = <String, dynamic>{
      'organization_id': organization.id,
      'award_definition_id': definition.id,
      'period_year': year,
      'period_month': month,
      'caption': caption.trim(),
      'delivery_date': deliveryDate == null
          ? null
          : '${deliveryDate.year.toString().padLeft(4, '0')}-'
              '${deliveryDate.month.toString().padLeft(2, '0')}-'
              '${deliveryDate.day.toString().padLeft(2, '0')}',
      'delivery_photo_url':
          deliveryPhotoUrl.trim().isEmpty ? null : deliveryPhotoUrl.trim(),
      'is_published': isPublished,
      'is_visible': isVisible,
      'updated_at': DateTime.now().toIso8601String(),
    };

    String editionId;
    if (id == null) {
      payload['created_by'] = _client.auth.currentUser?.id;
      final created = await _client
          .from('award_editions')
          .insert(payload)
          .select('id')
          .single();
      editionId = created['id'].toString();
    } else {
      await _client.from('award_editions').update(payload).eq('id', id);
      editionId = id;
      await _client
          .from('award_winners')
          .delete()
          .eq('award_edition_id', editionId);
    }

    if (winners.isNotEmpty) {
      await _client.from('award_winners').insert([
        for (final entry in winners.indexed)
          {
            'organization_id': organization.id,
            'award_edition_id': editionId,
            'profile_id': entry.$2['id'],
            'winner_name': entry.$2['full_name'],
            'winner_avatar_url': entry.$2['avatar_url'],
            'position': entry.$1 + 1,
            'result_label': entry.$2['result_label'] ?? '',
          },
      ]);
    }
  }

  Future<void> deleteEdition(String id) async {
    final edition = await _client
        .from('award_editions')
        .select('delivery_photo_url')
        .eq('id', id)
        .maybeSingle();
    await _client.from('award_editions').delete().eq('id', id);
    await _removeImageUrl((edition?['delivery_photo_url'] ?? '').toString());
  }

  Future<void> _removeImageUrl(String url) async {
    if (url.trim().isEmpty) return;
    try {
      final segments = Uri.parse(url).pathSegments;
      final bucketIndex = segments.indexOf('event-images');
      if (bucketIndex < 0 || bucketIndex + 1 >= segments.length) return;
      final path = segments.skip(bucketIndex + 1).join('/');
      await _client.storage.from('event-images').remove([path]);
    } catch (_) {
      // A exclusao do cadastro nao deve falhar por uma foto ja removida.
    }
  }
}
