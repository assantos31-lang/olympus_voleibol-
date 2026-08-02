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
  final Map<String, int> reactionCounts;
  final String? myReactionEmoji;
  final DateTime createdAt;
  final DateTime? editedAt;
  final DateTime? deletedAt;
  final int recipientCount;
  final int deliveredCount;
  final int readCount;
  final String localStatus;
  final String? localError;

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
    this.reactionCounts = const <String, int>{},
    this.myReactionEmoji,
    required this.createdAt,
    this.editedAt,
    this.deletedAt,
    this.recipientCount = 0,
    this.deliveredCount = 0,
    this.readCount = 0,
    this.localStatus = 'sent',
    this.localError,
  });

  factory ChatMessage.fromMap(Map<String, dynamic> map) {
    final createdAt = DateTime.tryParse((map['created_at'] ?? '').toString());
    return ChatMessage(
      id: (map['id'] ?? '').toString(),
      roomId: (map['room_id'] ?? '').toString(),
      senderId: (map['sender_id'] ?? '').toString(),
      senderName: map['sender_name']?.toString(),
      content: map['content']?.toString(),
      messageType: (map['message_type'] ?? 'text').toString(),
      imageUrl: map['image_url']?.toString(),
      mediaQuality: map['media_quality']?.toString(),
      mediaExpiresAt: map['media_expires_at'] == null
          ? null
          : DateTime.tryParse(map['media_expires_at'].toString()),
      mediaDeletedAt: map['media_deleted_at'] == null
          ? null
          : DateTime.tryParse(map['media_deleted_at'].toString()),
      replyToMessageId: map['reply_to_message_id']?.toString(),
      replyToText: map['reply_to_text']?.toString(),
      replyToSenderName: map['reply_to_sender_name']?.toString(),
      reactionEmoji: map['reaction_emoji']?.toString(),
      reactionCounts: _parseReactionCounts(map['reaction_counts']),
      myReactionEmoji: map['my_reaction_emoji']?.toString(),
      createdAt:
          createdAt ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      editedAt: map['edited_at'] == null
          ? null
          : DateTime.tryParse(map['edited_at'].toString()),
      deletedAt: map['deleted_at'] == null
          ? null
          : DateTime.tryParse(map['deleted_at'].toString()),
      recipientCount: _parseCount(map['recipient_count']),
      deliveredCount: _parseCount(map['delivered_count']),
      readCount: _parseCount(map['read_count']),
      localStatus: (map['local_status'] ?? 'sent').toString(),
      localError: map['local_error']?.toString(),
    );
  }

  ChatMessage copyWith({
    String? senderName,
    String? reactionEmoji,
    bool clearReactionEmoji = false,
    Map<String, int>? reactionCounts,
    String? myReactionEmoji,
    bool clearMyReactionEmoji = false,
    int? recipientCount,
    int? deliveredCount,
    int? readCount,
    String? localStatus,
    String? localError,
    bool clearLocalError = false,
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
      reactionCounts: reactionCounts ?? this.reactionCounts,
      myReactionEmoji:
          clearMyReactionEmoji ? null : myReactionEmoji ?? this.myReactionEmoji,
      createdAt: createdAt,
      editedAt: editedAt,
      deletedAt: deletedAt,
      recipientCount: recipientCount ?? this.recipientCount,
      deliveredCount: deliveredCount ?? this.deliveredCount,
      readCount: readCount ?? this.readCount,
      localStatus: localStatus ?? this.localStatus,
      localError: clearLocalError ? null : localError ?? this.localError,
    );
  }

  bool get isDelivered => deliveredCount > 0 || readCount > 0;

  bool get isReadByAll => recipientCount > 0 && readCount >= recipientCount;

  bool get isReadBySomeone => readCount > 0;

  bool get isLocalSending => localStatus == 'sending';

  bool get isLocalFailed => localStatus == 'failed';

  bool get isDeleted => deletedAt != null;

  bool get isImage => messageType == 'image' && imageUrl != null;

  bool get isSticker => messageType == 'sticker' && imageUrl != null;

  bool get isVideoSticker => messageType == 'video_sticker' && imageUrl != null;

  bool get isOfficialSticker =>
      isSticker && (imageUrl?.startsWith('asset:') ?? false);

  bool get isVideo => messageType == 'video';

  bool get isAudio => messageType == 'audio' && imageUrl != null;

  int get audioDurationSeconds {
    if (!isAudio) return 0;
    return int.tryParse((content ?? '').trim()) ?? 0;
  }

  bool get hasVideo => isVideo && imageUrl != null && mediaDeletedAt == null;

  bool get isVideoExpired => isVideo && !hasVideo;

  bool get isPoll => messageType == 'poll' && imageUrl != null;

  static Map<String, int> _parseReactionCounts(dynamic raw) {
    if (raw is! Map) return const <String, int>{};
    final result = <String, int>{};
    raw.forEach((key, value) {
      final emoji = key.toString().trim();
      final count = value is num ? value.toInt() : int.tryParse('$value') ?? 0;
      if (emoji.isNotEmpty && count > 0) result[emoji] = count;
    });
    return result;
  }

  static int _parseCount(dynamic raw) {
    if (raw is num) return raw.toInt();
    return int.tryParse((raw ?? '').toString()) ?? 0;
  }
}
