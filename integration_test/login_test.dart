import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:olympus_voleibol/main.dart' as app;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('Login e captura de tela para Apple', (tester) async {
    app.main();
    await tester.pumpAndSettle();

    await tester.enterText(
        find.byType(TextFormField).at(0), 'teste@exemplo.com');
    await tester.enterText(find.byType(TextFormField).at(1), 'Senha123!');

    await tester.tap(find.text('Entrar'));
    await tester.pumpAndSettle(const Duration(seconds: 5));

    // Captura a screenshot
    await binding.takeScreenshot('login_sucesso_iphone');

    expect(find.text('Bem-vindo'), findsOneWidget);
  });
}
