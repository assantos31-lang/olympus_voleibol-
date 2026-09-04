import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:olympus_voleibol/models/award_models.dart';
import 'package:olympus_voleibol/pages/awards_page.dart';
import 'package:olympus_voleibol/theme/olympus_theme.dart';
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
          loadProfiles: () async => const [
            {'id': '2', 'full_name': 'Bruna'},
            {'id': '1', 'full_name': 'Amanda'},
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Período da premiação'), findsOneWidget);
    expect(find.byKey(const Key('award-shared-form-layout')), findsOneWidget);
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
    expect(find.text('Tipo de prêmio'), findsOneWidget);
    expect(find.byKey(const Key('award-custom-source-label')), findsOneWidget);

    await tester.drag(find.byType(ListView), const Offset(0, -500));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('award-inline-winner-picker')), findsOneWidget);
    expect(find.byKey(const Key('award-winner-slot-0-')), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('award-winner-slot-0-')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('award-winner-slot-0-')));
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.text('Amanda').last).dy,
      lessThan(tester.getTopLeft(find.text('Bruna').last).dy),
    );
    await tester.tap(find.text('Amanda').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('award-winner-slot-0-1')), findsOneWidget);

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

  testWidgets('formulário permite várias fotos, capa, ordem e remoção',
      (tester) async {
    final uploads = <String>[
      'https://example.com/primeira.jpg',
      'https://example.com/segunda.jpg',
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: AwardDefinitionFormPage(
          initialYear: 2026,
          initialMonth: 9,
          uploadImage: () async => uploads.removeAt(0),
          loadProfiles: () async => const [
            {'id': '1', 'full_name': 'Amanda'},
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Nenhuma foto adicionada.'), findsNothing);
    await tester.drag(find.byType(ListView), const Offset(0, -1400));
    await tester.pumpAndSettle();
    expect(find.text('Nenhuma foto adicionada.'), findsOneWidget);

    await tester.tap(find.byKey(const Key('award-add-image')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('award-add-image')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('award-image-0')), findsOneWidget);
    expect(find.byKey(const Key('award-image-1')), findsOneWidget);
    expect(find.text('2 foto(s) • A estrela indica a capa'), findsOneWidget);

    await tester.tap(find.byKey(const Key('award-cover-1')));
    await tester.pumpAndSettle();
    final coverButton = tester.widget<IconButton>(
      find.byKey(const Key('award-cover-0')),
    );
    expect(coverButton.onPressed, isNull);

    await tester.tap(find.byKey(const Key('award-remove-image-1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('award-image-1')), findsNothing);
    expect(find.text('1 foto(s) • A estrela indica a capa'), findsOneWidget);
  });

  testWidgets('entrega usa apenas o controle publicar no mural',
      (tester) async {
    const definition = AwardDefinition(
      id: 'award-1',
      title: 'Ranking do mês',
      description: '',
      sourceType: 'manual',
      winnerCount: 1,
      isVisible: true,
      sortOrder: 0,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: AwardEditionFormPage(
          definitions: const [definition],
          initialDefinition: definition,
          initialYear: 2026,
          initialMonth: 9,
          uploadImage: () async => null,
          createAward: () async => true,
          loadProfiles: () async => const [
            {'id': '1', 'full_name': 'Amanda'},
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('award-shared-form-layout')), findsOneWidget);
    expect(
        find.byKey(const Key('award-shared-period-selector')), findsOneWidget);
    final title = tester.widget<Text>(find.text('Premiação'));
    expect(
      title.style?.color,
      OlympusBrandingController.instance.branding.fieldTitleColor,
    );
    await tester.tap(find.byKey(const Key('award-edition-definition')));
    await tester.pumpAndSettle();
    expect(find.text('＋ Criar nova premiação').last, findsOneWidget);
    await tester.tap(find.text('Ranking do mês').last);
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, -1100));
    await tester.pumpAndSettle();
    expect(find.text('Mostrar esta entrega'), findsNothing);
    expect(find.widgetWithText(SwitchListTile, 'Publicar no mural'),
        findsOneWidget);
    expect(
      find.text(
        'A publicação exige pelo menos um vencedor; as fotos são opcionais.',
      ),
      findsOneWidget,
    );
    expect(find.text('Nenhuma foto adicionada.'), findsOneWidget);
    expect(find.byKey(const Key('award-winner-slot-0-')), findsOneWidget);
  });

  testWidgets('galeria navega no celular e mantém a capa primeiro',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(
        home: AwardGalleryPage(
          urls: [
            'https://example.com/capa.jpg',
            'https://example.com/outra.jpg',
          ],
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('award-gallery')), findsOneWidget);
    expect(find.text('1 de 2'), findsOneWidget);
    await tester.drag(find.byType(PageView), const Offset(-320, 0));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('2 de 2'), findsOneWidget);
  });

  testWidgets('galeria navega no desktop pelos controles', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(
        home: AwardGalleryPage(
          urls: [
            'https://example.com/capa.jpg',
            'https://example.com/outra.jpg',
          ],
        ),
      ),
    );
    await tester.pump();

    expect(find.text('1 de 2'), findsOneWidget);
    tester
        .widget<IconButton>(find.byKey(const Key('award-gallery-next')))
        .onPressed!();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('2 de 2'), findsOneWidget);
    tester
        .widget<IconButton>(find.byKey(const Key('award-gallery-previous')))
        .onPressed!();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('1 de 2'), findsOneWidget);
  });

  testWidgets('controle de visibilidade permanece dentro de cartão',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AwardDefinitionFormPage(
          initialYear: 2026,
          initialMonth: 9,
          uploadImage: () async => null,
          loadProfiles: () async => const [],
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
