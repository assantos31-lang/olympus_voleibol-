class ActiveChatService {
  ActiveChatService._();

  static String? _activeRoomId;

  static String? get activeRoomId => _activeRoomId;

  static bool isRoomOpen(String? roomId) {
    final cleanRoomId = roomId?.trim();
    return cleanRoomId != null &&
        cleanRoomId.isNotEmpty &&
        cleanRoomId == _activeRoomId;
  }

  static void openRoom(String roomId) {
    final cleanRoomId = roomId.trim();
    if (cleanRoomId.isEmpty) return;
    _activeRoomId = cleanRoomId;
  }

  static void closeRoom(String roomId) {
    if (_activeRoomId == roomId.trim()) {
      _activeRoomId = null;
    }
  }
}
