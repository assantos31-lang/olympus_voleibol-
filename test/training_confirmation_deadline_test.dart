import 'package:flutter_test/flutter_test.dart';
import 'package:olympus_voleibol/services/training_confirmation_deadline_service.dart';

void main() {
  const enabled = TrainingConfirmationDeadlineSettings(
    enabled: true,
    hoursBefore: 3,
  );
  final training = <String, dynamic>{
    'event_type': 'treino',
    'event_date': '11/09/2026',
    'event_time': '20:00',
  };

  test('regra desabilitada não interfere no comportamento atual', () {
    final state = trainingConfirmationState(
      event: training,
      convocationStatus: 'pending',
      settings: const TrainingConfirmationDeadlineSettings.disabled(),
      now: DateTime(2026, 9, 11, 19),
    );
    expect(state, TrainingConfirmationState.notApplicable);
  });

  test('atleta pode confirmar antes do prazo', () {
    final state = trainingConfirmationState(
      event: training,
      convocationStatus: 'pending',
      settings: enabled,
      now: DateTime(2026, 9, 11, 16, 59),
    );
    expect(state, TrainingConfirmationState.canConfirm);
  });

  test('prazo encerra exatamente no horário limite', () {
    final state = trainingConfirmationState(
      event: training,
      convocationStatus: 'pending',
      settings: enabled,
      now: DateTime(2026, 9, 11, 17),
    );
    expect(state, TrainingConfirmationState.deadlineExpired);
    expect(
      trainingConfirmationStateLabel(state),
      'Não confirmou dentro do prazo',
    );
  });

  test('atleta já confirmado permanece confirmado após o prazo', () {
    final state = trainingConfirmationState(
      event: training,
      convocationStatus: 'accepted',
      settings: enabled,
      now: DateTime(2026, 9, 11, 19),
    );
    expect(state, TrainingConfirmationState.confirmed);
  });

  test('regra é aplicada a amistoso quando configurada', () {
    final state = trainingConfirmationState(
      event: {...training, 'event_type': 'amistoso'},
      convocationStatus: 'pending',
      settings: enabled,
      now: DateTime(2026, 9, 11, 19),
    );
    expect(state, TrainingConfirmationState.deadlineExpired);
    expect(
      eventConfirmationDeadlineExpiredMessage({
        ...training,
        'event_type': 'amistoso',
      }),
      'O prazo para confirmar sua presença neste amistoso expirou. '
      'Você não deverá comparecer ao amistoso.',
    );
  });

  test('regra é aplicada a campeonato quando configurada', () {
    final championship = {...training, 'event_type': 'campeonato'};
    final state = trainingConfirmationState(
      event: championship,
      convocationStatus: 'pending',
      settings: enabled,
      now: DateTime(2026, 9, 11, 19),
    );
    expect(state, TrainingConfirmationState.deadlineExpired);
    expect(
      eventConfirmationDeadlineExpiredMessage(championship),
      'O prazo para confirmar sua presença neste campeonato expirou. '
      'Você não deverá comparecer ao campeonato.',
    );
  });

  test('recusa explícita não é apresentada como perda de prazo', () {
    final state = trainingConfirmationState(
      event: training,
      convocationStatus: 'rejected',
      settings: enabled,
      now: DateTime(2026, 9, 11, 19),
    );
    expect(state, TrainingConfirmationState.notApplicable);
  });

  test('configuração limita horas a um intervalo seguro', () {
    expect(
      TrainingConfirmationDeadlineSettings.fromValue({
        'enabled': true,
        'hours_before': 0,
      }).hoursBefore,
      1,
    );
    expect(
      TrainingConfirmationDeadlineSettings.fromValue({
        'enabled': true,
        'hours_before': 999,
      }).hoursBefore,
      168,
    );
  });
}
