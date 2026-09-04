import 'package:flutter_test/flutter_test.dart';
import 'package:olympus_voleibol/theme/olympus_theme.dart';

void main() {
  test('field title color defaults to white and persists in settings', () {
    const defaults = OlympusBranding();
    expect(defaults.fieldTitleHex, '#FFFFFF');

    final customized = defaults.copyWith(fieldTitleHex: '#AABBCC');
    final restored = OlympusBranding.fromMap(customized.toMap());

    expect(restored.fieldTitleHex, '#AABBCC');
    expect(restored.toMap()['field_title_color'], '#AABBCC');
  });
}
