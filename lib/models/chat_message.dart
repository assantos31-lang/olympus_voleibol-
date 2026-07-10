class ChatMessage {
  final String id;
  final String roomId;
  final String senderId;
  final String? senderName;
  final String? content;
  final String messageType;
  final String? imageUrl;
  final String? replyToMessageId;
  final String? replyToText;
  final String? replyToSenderName;
  final String? reactionEmoji;
  final DateTime createdAt;
  final DateTime? editedAt;
  final DateTime? deletedAt;

  ChatMessage({
    required this.id,
    required this.roomId,
    required this.senderId,
    this.senderName,
    required this.content,
    this.messageType = 'text',
    this.imageUrl,
    this.replyToMessageId,
    this.replyToText,
    this.replyToSenderName,
    this.reactionEmoji,
    required this.createdAt,
    this.editedAt,
    this.deletedAt,
  });

  factory ChatMessage.fromMap(Map<String, dynamic> map) {
    return ChatMessage(
      id: map['id'] as String,
      roomId: map['room_id'] as String,
      senderId: map['sender_id'] as String,
      senderName: map['sender_name'] as String?,
      content: map['content'] as String?,
      messageType: (map['message_type'] ?? 'text').toString(),
      imageUrl: map['image_url'] as String?,
      replyToMessageId: map['reply_to_message_id'] as String?,
      replyToText: map['reply_to_text'] as String?,
      replyToSenderName: map['reply_to_sender_name'] as String?,
      reactionEmoji: map['reaction_emoji'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
      editedAt: map['edited_at'] == null
          ? null
          : DateTime.tryParse(map['edited_at'].toString()),
      deletedAt: map['deleted_at'] == null
          ? null
          : DateTime.tryParse(map['deleted_at'].toString()),
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
      messageType: messageType,
      imageUrl: imageUrl,
      replyToMessageId: replyToMessageId,
      replyToText: replyToText,
      replyToSenderName: replyToSenderName,
      reactionEmoji: reactionEmoji,
      createdAt: createdAt,
      editedAt: editedAt,
      deletedAt: deletedAt,
    );
  }

  bool get isDeleted => deletedAt != null;

  bool get isImage => messageType == 'image' && imageUrl != null;

  bool get isPoll => messageType == 'poll' && imageUrl != null;
}
