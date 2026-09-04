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
  });
}
