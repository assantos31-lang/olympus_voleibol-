import 'package:flutter_test/flutter_test.dart';
import 'package:olympus_voleibol/services/awards_service.dart';

void main() {
  test('realtime acompanha todas as tabelas do mural de premiações', () {
    expect(
      awardRealtimeTables,
      [
        'award_definitions',
        'award_editions',
        'award_winners',
        'award_images',
      ],
    );
  });
}
