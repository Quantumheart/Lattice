import 'package:flutter/foundation.dart';
import 'package:matrix/matrix.dart';

/// Filter categories for the room list.
enum RoomFilter {
  all,
  directMessages,
  groups,
  unread,
  favourites,
}

/// Room/space selection state and filtered-room helpers.
mixin SelectionMixin on ChangeNotifier {
  Client get client;

  // ── Currently selected space & room ──────────────────────────
  String? _selectedSpaceId;
  String? get selectedSpaceId => _selectedSpaceId;

  String? _selectedRoomId;
  String? get selectedRoomId => _selectedRoomId;

  Room? get selectedRoom =>
      _selectedRoomId != null ? client.getRoomById(_selectedRoomId!) : null;

  // ── Room filter ────────────────────────────────────────────────
  RoomFilter _roomFilter = RoomFilter.all;
  RoomFilter get roomFilter => _roomFilter;

  void setRoomFilter(RoomFilter filter) {
    _roomFilter = filter;
    notifyListeners();
  }

  void selectSpace(String? spaceId) {
    _selectedSpaceId = spaceId;
    notifyListeners();
  }

  void selectRoom(String? roomId) {
    _selectedRoomId = roomId;
    notifyListeners();
  }

  /// Reset selection state (e.g. on logout).
  @protected
  void resetSelection() {
    _selectedSpaceId = null;
    _selectedRoomId = null;
    _roomFilter = RoomFilter.all;
  }

  // ── Helpers ──────────────────────────────────────────────────

  /// Returns spaces (rooms with type m.space).
  List<Room> get spaces => client.rooms
      .where((r) => r.isSpace)
      .toList()
    ..sort((a, b) => a.getLocalizedDisplayname().compareTo(b.getLocalizedDisplayname()));

  /// Returns non-space rooms, optionally filtered by current space and
  /// room filter category.
  List<Room> get rooms {
    var list = client.rooms.where((r) => !r.isSpace).toList();

    if (_selectedSpaceId != null) {
      final space = client.getRoomById(_selectedSpaceId!);
      if (space != null) {
        final childIds = space.spaceChildren.map((c) => c.roomId).toSet();
        list = list.where((r) => childIds.contains(r.id)).toList();
      }
    }

    // Apply room filter
    switch (_roomFilter) {
      case RoomFilter.all:
        break;
      case RoomFilter.directMessages:
        list = list.where((r) => r.isDirectChat).toList();
      case RoomFilter.groups:
        list = list.where((r) => !r.isDirectChat).toList();
      case RoomFilter.unread:
        list = list.where((r) => r.notificationCount > 0).toList();
      case RoomFilter.favourites:
        list = list.where((r) => r.isFavourite).toList();
    }

    list.sort((a, b) {
      final aTs = a.lastEvent?.originServerTs ?? DateTime(1970);
      final bTs = b.lastEvent?.originServerTs ?? DateTime(1970);
      return bTs.compareTo(aTs);
    });

    return list;
  }
}
