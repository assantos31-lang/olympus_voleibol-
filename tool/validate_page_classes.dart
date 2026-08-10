import 'dart:io';

const expectedClasses = <String, String>{
  'lib/pages/admin_financial_page.dart': 'class AdminFinancialPage',
  'lib/pages/athlete_financial_page.dart': 'class AthleteFinancialPage',
  'lib/pages/add_event_page.dart': 'class AddEventPage',
  'lib/pages/chat_page.dart': 'class ChatPage',
  'lib/pages/athlete_dashboard_page.dart': 'class AthleteDashboardPage',
  'lib/coach/pages/coach_dashboard_page.dart': 'class CoachDashboardPage',
};

void main() {
  final errors = <String>[];

  for (final entry in expectedClasses.entries) {
    final file = File(entry.key);
    if (!file.existsSync()) {
      errors.add('${entry.key}: arquivo não encontrado');
      continue;
    }

    final source = file.readAsStringSync();
    if (!source.contains(entry.value)) {
      errors.add('${entry.key}: deveria conter ${entry.value}');
    }
  }

  if (errors.isNotEmpty) {
    stderr.writeln('VALIDAÇÃO DE TELAS FALHOU');
    for (final error in errors) {
      stderr.writeln('- $error');
    }
    exitCode = 1;
    return;
  }

  stdout.writeln('PAGE_CLASS_GUARD_OK');
}
