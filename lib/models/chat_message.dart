class ChatMessage {
  final String id;
  final String roomId;
  final String senderId;
  final String? senderName;
  final String? content;
  final String messageType;
  final String? imageUrl;
  final String? mediaQuality;
  final DateTime? mediaExpiresAt;
  final DateTime? mediaDeletedAt;
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
    this.mediaQuality,
    this.mediaExpiresAt,
    this.mediaDeletedAt,
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
      mediaQuality: map['media_quality'] as String?,
      mediaExpiresAt: map['media_expires_at'] == null
          ? null
          : DateTime.tryParse(map['media_expires_at'].toString()),
      mediaDeletedAt: map['media_deleted_at'] == null
          ? null
          : DateTime.tryParse(map['media_deleted_at'].toString()),
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
    String? reactionEmoji,
    bool clearReactionEmoji = false,
  }) {
    return ChatMessage(
      id: id,
      roomId: roomId,
      senderId: senderId,
      senderName: senderName ?? this.senderName,
      content: content,
      messageType: messageType,
      imageUrl: imageUrl,
      mediaQuality: mediaQuality,
      mediaExpiresAt: mediaExpiresAt,
      mediaDeletedAt: mediaDeletedAt,
      replyToMessageId: replyToMessageId,
      replyToText: replyToText,
      replyToSenderName: replyToSenderName,
      reactionEmoji:
          clearReactionEmoji ? null : reactionEmoji ?? this.reactionEmoji,
      createdAt: createdAt,
      editedAt: editedAt,
      deletedAt: deletedAt,
    );
  }

  bool get isDeleted => deletedAt != null;

  bool get isImage => messageType == 'image' && imageUrl != null;

  bool get isSticker => messageType == 'sticker' && imageUrl != null;

  bool get isVideoSticker => messageType == 'video_sticker' && imageUrl != null;

  bool get isOfficialSticker =>
      isSticker && (imageUrl?.startsWith('asset:') ?? false);

  bool get isVideo => messageType == 'video';

  bool get hasVideo => isVideo && imageUrl != null && mediaDeletedAt == null;

  bool get isVideoExpired => isVideo && !hasVideo;

  bool get isPoll => messageType == 'poll' && imageUrl != null;
}
