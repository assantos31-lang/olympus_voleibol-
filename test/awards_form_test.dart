import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:olympus_voleibol/pages/awards_page.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('pt_BR');
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://example.supabase.co',
      anonKey: 'test-anon-key',
    );
  });

  testWidgets('novo tipo referencia mês e usa contador compacto',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AwardDefinitionFormPage(
          initialYear: 2026,
          initialMonth: 9,
          uploadImage: () async => null,
        ),
      ),
    );

    expect(find.text('Mês da premiação'), findsOneWidget);
    expect(find.text('A premiação será exibida aos atletas neste período.'),
        findsOneWidget);
    expect(
        find.byKey(const Key('award-winner-count-selector')), findsOneWidget);
    final titleField = tester.widget<TextField>(
      find.descendant(
        of: find.byKey(const Key('award-title-field')),
        matching: find.byType(TextField),
      ),
    );
    final descriptionField = tester.widget<TextField>(
      find.descendant(
        of: find.byKey(const Key('award-description-field')),
        matching: find.byType(TextField),
      ),
    );
    expect(titleField.decoration?.labelText, isNull);
    expect(descriptionField.decoration?.labelText, isNull);

    Text count = tester.widget(
      find.byKey(const Key('award-winner-count-value')),
    );
    expect(count.data, '1');

    await tester.tap(find.byKey(const Key('award-winner-count-plus')));
    await tester.pump();

    count = tester.widget(
      find.byKey(const Key('award-winner-count-value')),
    );
    expect(count.data, '2');
  });

  testWidgets('controle de visibilidade permanece dentro de cartão',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AwardDefinitionFormPage(
          initialYear: 2026,
          initialMonth: 9,
          uploadImage: () async => null,
        ),
      ),
    );

    await tester.drag(find.byType(ListView), const Offset(0, -700));
    await tester.pumpAndSettle();

    final switchTile = find.widgetWithText(SwitchListTile, 'Mostrar este tipo');
    expect(switchTile, findsOneWidget);
    final cardFinder =
        find.ancestor(of: switchTile, matching: find.byType(Card));
    expect(cardFinder, findsOneWidget);

    final card = tester.widget<Card>(cardFinder);
    final tile = tester.widget<SwitchListTile>(switchTile);
    final title = tile.title! as Text;
    final background = card.color!;
    final foreground = title.style!.color!;
    final lighter =
        background.computeLuminance() > foreground.computeLuminance()
            ? background.computeLuminance()
            : foreground.computeLuminance();
    final darker = background.computeLuminance() > foreground.computeLuminance()
        ? foreground.computeLuminance()
        : background.computeLuminance();

    expect((lighter + 0.05) / (darker + 0.05), greaterThanOrEqualTo(4.5));
  });
}
