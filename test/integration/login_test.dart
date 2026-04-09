import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:olympus_voleibol/main.dart' as app;

void main() {
  // 1. Inicializa o binding
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  // Garante que a UI esteja pronta para interagir
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('Login e captura de tela para Apple', (tester) async {
    app.main();
    await tester.pumpAndSettle();

    // 2. Preenche o formulário
    // Use keys se o find.byType falhar, mas vamos tentar manter simples
    await tester.enterText(
        find.byType(TextFormField).at(0), 'seu_email@teste.com');
    await tester.enterText(find.byType(TextFormField).at(1), 'sua_senha_aqui');

    await tester.tap(find.text('Entrar')); // Ou o texto exato do seu botão

    // 3. Espera a transição e o carregamento
    await tester.pumpAndSettle(const Duration(seconds: 5));

    // 4. TIRA O PRINT (O passo mágico)
    // Salva na pasta integration_test/screenshots (ou raiz do projeto)
    await binding.takeScreenshot('login_sucesso_iphone');

    // Validação final opcional
    expect(find.text('Bem-vindo'), findsOneWidget);
  });
}
