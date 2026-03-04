import 'package:matrix/matrix.dart';

import 'package:lattice/features/rooms/services/room_list_search_controller.dart';

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

  RoomItem({required this.room, this.depth = 0});
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
    this.resultCount,
    required this.isLoading,
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
