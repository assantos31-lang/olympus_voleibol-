import 'package:flutter_test/flutter_test.dart';
import 'package:olympus_voleibol/models/award_models.dart';

void main() {
  group('award models', () {
    test('uses stable keys for monthly editions', () {
      expect(awardPeriodKey(2026, 9), '2026-09');
      expect(awardPeriodKey(2027, 12), '2027-12');
    });

    test('shows a readable label for every supported source', () {
      expect(awardSourceLabel('checkin_ranking'), 'Ranking de check-ins');
      expect(awardSourceLabel('training_highlight'), 'Destaque de treino');
      expect(awardSourceLabel('monthly_evaluation'), 'Avaliação mensal');
      expect(awardSourceLabel('manual'), 'Escolha manual');
    });

    test('uses the custom prize type for manual awards', () {
      final definition = AwardDefinition.fromMap({
        'id': 'award-1',
        'title': 'Destaque do mês',
        'description': '',
        'source_type': 'manual',
        'custom_source_label': 'Melhor saque',
        'winner_count': 1,
        'is_visible': true,
        'sort_order': 0,
      });

      expect(definition.sourceLabel, 'Melhor saque');
    });

    test('parses definition limits and visibility', () {
      final definition = AwardDefinition.fromMap({
        'id': 'award-1',
        'title': 'Ranking do mês',
        'description': 'Mais presenças',
        'source_type': 'checkin_ranking',
        'winner_count': 3,
        'is_visible': false,
        'sort_order': 2,
      });

      expect(definition.winnerCount, 3);
      expect(definition.isVisible, isFalse);
      expect(definition.sortOrder, 2);
    });

    test('resolves a reloaded definition by id', () {
      const reloaded = AwardDefinition(
        id: 'award-1',
        title: 'Premiação recarregada',
        description: '',
        sourceType: 'manual',
        winnerCount: 1,
        isVisible: true,
        sortOrder: 0,
      );
      const returnedAfterSave = AwardDefinition(
        id: 'award-1',
        title: 'Premiação salva',
        description: '',
        sourceType: 'manual',
        winnerCount: 1,
        isVisible: true,
        sortOrder: 0,
      );

      expect(
        resolveAwardDefinitionById(
          definitions: const [reloaded],
          preferred: returnedAfterSave,
        ),
        same(reloaded),
      );
    });

    test('orders athlete names alphabetically ignoring accents', () {
      final ordered = sortAwardProfilesAlphabetically([
        {'id': '3', 'full_name': 'Érica'},
        {'id': '2', 'full_name': 'bruno'},
        {'id': '1', 'full_name': 'Ana'},
        {'id': '4', 'full_name': 'Ágata'},
      ]);

      expect(
        ordered.map((item) => item['full_name']),
        ['Ágata', 'Ana', 'bruno', 'Érica'],
      );
    });

    test('keeps legacy photo as the gallery cover', () {
      const definition = AwardDefinition(
        id: 'award-1',
        title: 'Destaque',
        description: '',
        sourceType: 'manual',
        winnerCount: 1,
        isVisible: true,
        sortOrder: 0,
      );
      const edition = AwardEdition(
        id: 'edition-1',
        definition: definition,
        year: 2026,
        month: 9,
        caption: '',
        deliveryPhotoUrl: 'https://example.com/legacy.jpg',
        isPublished: true,
        isVisible: true,
        winners: [],
      );

      expect(edition.primaryImageUrl, 'https://example.com/legacy.jpg');
      expect(edition.galleryImageUrls, ['https://example.com/legacy.jpg']);
    });

    test('places the selected gallery cover first', () {
      const definition = AwardDefinition(
        id: 'award-1',
        title: 'Destaque',
        description: '',
        sourceType: 'manual',
        winnerCount: 1,
        isVisible: true,
        sortOrder: 0,
      );
      const edition = AwardEdition(
        id: 'edition-1',
        definition: definition,
        year: 2026,
        month: 9,
        caption: '',
        isPublished: true,
        isVisible: true,
        winners: [],
        images: [
          AwardImage(id: '1', url: 'second.jpg', sortOrder: 0, isCover: false),
          AwardImage(id: '2', url: 'cover.jpg', sortOrder: 1, isCover: true),
        ],
      );

      expect(edition.galleryImageUrls, ['cover.jpg', 'second.jpg']);
      expect(edition.primaryImageUrl, 'cover.jpg');
    });
  });
}
