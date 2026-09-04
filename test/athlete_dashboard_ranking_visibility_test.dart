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
      const MaterialApp(home: AthleteDashboardPage()),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Ranking do mês'), findsOneWidget);
    expect(find.text('Ver regras'), findsOneWidget);
    expect(find.text('Ver ranking'), findsOneWidget);

    await tester.ensureVisible(find.text('Ver regras'));
    await tester.pump();
    await tester.tap(find.text('Ver regras'));
    await tester.pump();
    expect(find.text('Regras do ranking'), findsOneWidget);
    expect(
      find.text(
        '• O ranking ordena por pontos, depois por treinos válidos, depois por chegadas em 1º e por fim por nome.',
      ),
      findsOneWidget,
    );

    await tester.ensureVisible(find.text('Ver ranking'));
    await tester.pump();
    await tester.tap(find.text('Ver ranking'));
    await tester.pump();
    expect(
      find.text('Nenhum check-in válido encontrado para o mês atual.'),
      findsOneWidget,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}
