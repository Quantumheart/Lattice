import 'package:lattice/features/rooms/services/room_list_search_controller.dart';
import 'package:matrix/matrix.dart';

// ── List item types for the flat interleaved list ──────────
sealed class ListItem {}

class HeaderItem extends ListItem {
  final String name;
  final String sectionKey;
  final int depth;
  final int roomCount;
  final bool isSpace;

  HeaderItem({
    required this.name,
    required this.sectionKey,
    required this.depth,
    required this.roomCount,
    this.isSpace = false,
  });
}

class RoomItem extends ListItem {
  final Room room;
  final int depth;
  final String? parentSpaceId;
  final List<Room>? sectionRooms;

  RoomItem({
    required this.room,
    this.depth = 0,
    this.parentSpaceId,
    List<Room>? sectionRooms,
  }) : sectionRooms = sectionRooms != null
           ? List.unmodifiable(sectionRooms)
           : null;
}

class InviteItem extends ListItem {
  final Room room;
  InviteItem({required this.room});
}

class MessageSearchHeaderItem extends ListItem {
  final int? resultCount;
  final bool isLoading;
  final String? error;

  MessageSearchHeaderItem({
    required this.isLoading, this.resultCount,
    this.error,
  });
}

class MessageSearchResultItem extends ListItem {
  final MessageSearchResult result;
  MessageSearchResultItem({required this.result});
}

class LoadMoreMessagesItem extends ListItem {
  final bool isLoading;
  LoadMoreMessagesItem({required this.isLoading});
}
