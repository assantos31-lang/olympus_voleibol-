import 'package:flutter_test/flutter_test.dart';
import 'package:olympus_voleibol/pages/awards_page.dart';

void main() {
  test('mural de premiações é somente leitura por padrão', () {
    expect(const AwardsPage().canManage, isFalse);
  });

  test('somente a rota administrativa libera gerenciamento', () {
    expect(const AwardsPage(canManage: true).canManage, isTrue);
  });
}
