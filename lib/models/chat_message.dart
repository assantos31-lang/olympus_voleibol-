class ChatMessage {
  final String id;
  final String roomId;
  final String senderId;
  final String? senderName;
  final String? content;
  final DateTime createdAt;

  ChatMessage({
    required this.id,
    required this.roomId,
    required this.senderId,
    this.senderName,
    required this.content,
    required this.createdAt,
  });

  factory ChatMessage.fromMap(Map<String, dynamic> map) {
    return ChatMessage(
      id: map['id'] as String,
      roomId: map['room_id'] as String,
      senderId: map['sender_id'] as String,
      senderName: map['sender_name'] as String?,
      content: map['content'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  ChatMessage copyWith({
    String? senderName,
  }) {
    return ChatMessage(
      id: id,
      roomId: roomId,
      senderId: senderId,
      senderName: senderName ?? this.senderName,
      content: content,
      createdAt: createdAt,
    );
  }
}
