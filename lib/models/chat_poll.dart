class ChatPollOption {
  final String id;
  final String pollId;
  final String text;
  final int position;
  final int voteCount;

  const ChatPollOption({
    required this.id,
    required this.pollId,
    required this.text,
    required this.position,
    this.voteCount = 0,
  });

  factory ChatPollOption.fromMap(
    Map<String, dynamic> map, {
    int voteCount = 0,
  }) {
    return ChatPollOption(
      id: (map['id'] ?? '').toString(),
      pollId: (map['poll_id'] ?? '').toString(),
      text: (map['option_text'] ?? '').toString(),
      position: (map['position'] as num?)?.toInt() ?? 0,
      voteCount: voteCount,
    );
  }
}

class ChatPoll {
  final String id;
  final String roomId;
  final String createdBy;
  final String question;
  final bool isClosed;
  final bool isPinned;
  final DateTime createdAt;
  final List<ChatPollOption> options;
  final String? myOptionId;

  const ChatPoll({
    required this.id,
    required this.roomId,
    required this.createdBy,
    required this.question,
    required this.isClosed,
    this.isPinned = false,
    required this.createdAt,
    required this.options,
    this.myOptionId,
  });

  factory ChatPoll.fromMap(
    Map<String, dynamic> map, {
    List<ChatPollOption> options = const [],
    String? myOptionId,
  }) {
    return ChatPoll(
      id: (map['id'] ?? '').toString(),
      roomId: (map['room_id'] ?? '').toString(),
      createdBy: (map['created_by'] ?? '').toString(),
      question: (map['question'] ?? '').toString(),
      isClosed: map['is_closed'] == true,
      isPinned: map['is_pinned'] == true,
      createdAt: DateTime.tryParse((map['created_at'] ?? '').toString()) ??
          DateTime.now(),
      options: options,
      myOptionId: myOptionId,
    );
  }

  int get totalVotes =>
      options.fold<int>(0, (total, option) => total + option.voteCount);

  bool get hasMyVote => myOptionId != null && myOptionId!.isNotEmpty;
}
