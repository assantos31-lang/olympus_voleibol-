import 'package:flutter_test/flutter_test.dart';
import 'package:olympus_voleibol/models/chat_message.dart';

ChatMessage messageWith({
  required int recipients,
  required int delivered,
  required int read,
}) {
  return ChatMessage(
    id: 'message-1',
    roomId: 'room-1',
    senderId: 'sender-1',
    content: 'Teste',
    createdAt: DateTime.utc(2026, 8, 1),
    recipientCount: recipients,
    deliveredCount: delivered,
    readCount: read,
  );
}

void main() {
  group('status de entrega do chat', () {
    test('permanece enviado enquanto nenhum destinatario confirmou entrega',
        () {
      final message = messageWith(recipients: 1, delivered: 0, read: 0);

      expect(message.isDelivered, false);
      expect(message.isReadByAll, false);
    });

    test('fica entregue quando todos os destinatarios receberam', () {
      final message = messageWith(recipients: 1, delivered: 1, read: 0);

      expect(message.isDelivered, true);
      expect(message.isReadByAll, false);
    });

    test('fica lido somente quando todos visualizaram', () {
      final message = messageWith(recipients: 3, delivered: 3, read: 3);

      expect(message.isDelivered, true);
      expect(message.isReadByAll, true);
    });
  });
}
