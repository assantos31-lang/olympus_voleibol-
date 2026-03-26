import 'dart:async';

class ActiveMessageThreadRegistry {
  ActiveMessageThreadRegistry._();

  static final ActiveMessageThreadRegistry instance =
      ActiveMessageThreadRegistry._();

  String? _activeRoomId;
  String? _activeUserId;

  final StreamController<String?> _roomController =
      StreamController<String?>.broadcast();

  final StreamController<bool> _openController =
      StreamController<bool>.broadcast();

  String? get activeRoomId => _activeRoomId;
  String? get activeUserId => _activeUserId;

  bool get hasOpenThread => _activeRoomId != null;

  Stream<String?> get activeRoomStream => _roomController.stream;
  Stream<bool> get isOpenStream => _openController.stream;

  void openThread({
    required String roomId,
    String? userId,
  }) {
    _activeRoomId = roomId;
    _activeUserId = userId;
    _roomController.add(_activeRoomId);
    _openController.add(true);
  }

  void closeThread() {
    _activeRoomId = null;
    _activeUserId = null;
    _roomController.add(null);
    _openController.add(false);
  }

  bool isActive(String roomId) {
    return _activeRoomId == roomId;
  }

  void dispose() {
    _roomController.close();
    _openController.close();
  }
}
