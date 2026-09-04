import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:olympus_voleibol/pages/athlete_dashboard_page.dart';
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

  testWidgets('ranking e regras permanecem visíveis mesmo sem dados',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: AthleteDashboardPage(
          initialProfileForTest: {'gender': 'Feminino'},
          initialGenderRankingForTest: [],
        ),
      ),
    );
    await tester.pump();

    final rankingCard = find.byKey(
      const Key('athlete-monthly-ranking-card'),
    );
    expect(rankingCard, findsOneWidget);
    expect(find.text('Ranking do mês • Feminino'), findsOneWidget);
    expect(
      find.byKey(const Key('athlete-ranking-rules-button')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('athlete-ranking-list-button')),
      findsOneWidget,
    );

    await tester.ensureVisible(rankingCard);
    await tester.pump();
    await tester.tap(find.byKey(const Key('athlete-ranking-rules-button')));
    await tester.pump();
    expect(
      find.byKey(const Key('athlete-ranking-rules-card')),
      findsOneWidget,
    );
    expect(
      find.text(
        '• O ranking ordena por pontos, depois por treinos válidos, depois por chegadas em 1º e por fim por nome.',
      ),
      findsOneWidget,
    );

    await tester.ensureVisible(rankingCard);
    await tester.pump();
    await tester.tap(find.byKey(const Key('athlete-ranking-list-button')));
    await tester.pump();
    expect(
      find.byKey(const Key('athlete-ranking-empty-state')),
      findsOneWidget,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('ranking renderiza atletas e mantém as regras acessíveis',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: AthleteDashboardPage(
          initialProfileForTest: {'gender': 'Feminino'},
          initialGenderRankingForTest: [
            {
              'id': '2',
              'first_name': 'Bruna',
              'total_points': 8,
              'presence_count': 4,
              'first_checkins': 1,
            },
            {
              'id': '1',
              'first_name': 'Amanda',
              'total_points': 10,
              'presence_count': 5,
              'first_checkins': 2,
            },
          ],
        ),
      ),
    );
    await tester.pump();

    final rankingCard = find.byKey(
      const Key('athlete-monthly-ranking-card'),
    );
    expect(rankingCard, findsOneWidget);
    await tester.ensureVisible(rankingCard);
    await tester.pump();
    await tester.tap(find.byKey(const Key('athlete-ranking-list-button')));
    await tester.pump();

    expect(find.text('Amanda'), findsOneWidget);
    expect(find.text('Bruna'), findsOneWidget);
    expect(
        find.text('10 pts • 5 treinos • 2 primeiras chegadas'), findsOneWidget);
    expect(find.text('8 pts • 4 treinos • 1 primeira chegada'), findsOneWidget);

    await tester.ensureVisible(rankingCard);
    await tester.pump();
    await tester.tap(find.byKey(const Key('athlete-ranking-rules-button')));
    await tester.pump();
    expect(
      find.byKey(const Key('athlete-ranking-rules-card')),
      findsOneWidget,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}
