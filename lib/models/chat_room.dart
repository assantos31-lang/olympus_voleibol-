class ChatRoom {
  final String id;
  final String? name;
  final String type;
  final String createdBy;
  final bool isLocked;
  final bool allowMessages;
  final bool adminOnly;
  final DateTime createdAt;
  final String? avatarUrl;

  ChatRoom({
    required this.id,
    required this.name,
    required this.type,
    required this.createdBy,
    required this.isLocked,
    required this.allowMessages,
    required this.adminOnly,
    required this.createdAt,
    this.avatarUrl,
  });

  factory ChatRoom.fromMap(Map<String, dynamic> map) {
    return ChatRoom(
      id: map['id'] as String,
      name: map['name'] as String?,
      type: map['type'] as String,
      createdBy: map['created_by'] as String,
      isLocked: map['is_locked'] as bool? ?? false,
      allowMessages: map['allow_messages'] as bool? ?? true,
      adminOnly: map['admin_only'] as bool? ?? false,
      createdAt: DateTime.parse(map['created_at'] as String),
      avatarUrl: map['avatar_url'] as String?,
    );
  }

  ChatRoom copyWith({
    String? id,
    String? name,
    String? type,
    String? createdBy,
    bool? isLocked,
    bool? allowMessages,
    bool? adminOnly,
    DateTime? createdAt,
    String? avatarUrl,
  }) {
    return ChatRoom(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      createdBy: createdBy ?? this.createdBy,
      isLocked: isLocked ?? this.isLocked,
      allowMessages: allowMessages ?? this.allowMessages,
      adminOnly: adminOnly ?? this.adminOnly,
      createdAt: createdAt ?? this.createdAt,
      avatarUrl: avatarUrl ?? this.avatarUrl,
    );
  }
}
