class AppMessageThread {
  final String id;
  final String subject;
  final String createdBy;
  final String createdByName;
  final String createdByType;
  final bool allowReply;
  final DateTime createdAt;
  final DateTime? lastMessageAt;
  final int unreadCount;
  final String preview;

  AppMessageThread({
    required this.id,
    required this.subject,
    required this.createdBy,
    required this.createdByName,
    required this.createdByType,
    required this.allowReply,
    required this.createdAt,
    this.lastMessageAt,
    required this.unreadCount,
    required this.preview,
  });

  factory AppMessageThread.fromMap(Map<String, dynamic> map) {
    return AppMessageThread(
      id: (map['id'] ?? '').toString(),
      subject: (map['subject'] ?? '').toString(),
      createdBy: (map['created_by'] ?? '').toString(),
      createdByName: (map['created_by_name'] ?? '').toString(),
      createdByType: (map['created_by_type'] ?? '').toString(),
      allowReply: map['allow_reply'] == true,
      createdAt: DateTime.tryParse((map['created_at'] ?? '').toString()) ??
          DateTime.now(),
      lastMessageAt: map['last_message_at'] != null
          ? DateTime.tryParse(map['last_message_at'].toString())
          : null,
      unreadCount: int.tryParse((map['unread_count'] ?? 0).toString()) ?? 0,
      preview: (map['preview'] ?? '').toString(),
    );
  }
}

class AppMessageItem {
  final String id;
  final String threadId;
  final String senderId;
  final String senderName;
  final String senderType;
  final String body;
  final DateTime createdAt;

  AppMessageItem({
    required this.id,
    required this.threadId,
    required this.senderId,
    required this.senderName,
    required this.senderType,
    required this.body,
    required this.createdAt,
  });

  factory AppMessageItem.fromMap(Map<String, dynamic> map) {
    return AppMessageItem(
      id: (map['id'] ?? '').toString(),
      threadId: (map['thread_id'] ?? '').toString(),
      senderId: (map['sender_id'] ?? '').toString(),
      senderName: (map['sender_name'] ?? '').toString(),
      senderType: (map['sender_type'] ?? '').toString(),
      body: (map['body'] ?? '').toString(),
      createdAt: DateTime.tryParse((map['created_at'] ?? '').toString()) ??
          DateTime.now(),
    );
  }
}

class MessageRecipientOption {
  final String id;
  final String fullName;
  final String email;
  final String userType;
  final String? avatarUrl;

  MessageRecipientOption({
    required this.id,
    required this.fullName,
    required this.email,
    required this.userType,
    this.avatarUrl,
  });

  factory MessageRecipientOption.fromMap(Map<String, dynamic> map) {
    return MessageRecipientOption(
      id: (map['id'] ?? '').toString(),
      fullName: (map['full_name'] ?? '').toString(),
      email: (map['email'] ?? '').toString(),
      userType: (map['user_type'] ?? '').toString(),
      avatarUrl: map['avatar_url']?.toString(),
    );
  }
}
