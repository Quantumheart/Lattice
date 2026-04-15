import 'package:kohera/core/models/space_node.dart';
import 'package:kohera/core/services/preferences_service.dart';
import 'package:kohera/core/services/sub_services/selection_service.dart';
import 'package:kohera/features/rooms/widgets/room_list_models.dart';
import 'package:matrix/matrix.dart';

// ── Section-building helpers for the room list ──────────

bool roomMatchesQuery(Room r, String q) {
  if (r.getLocalizedDisplayname().toLowerCase().contains(q)) return true;

  final alias = r.canonicalAlias;
  if (alias.isNotEmpty && alias.toLowerCase().contains(q)) return true;

  final dmPartner = r.directChatMatrixID;
  if (dmPartner != null && dmPartner.toLowerCase().contains(q)) return true;

  return false;
}

List<Room> applySearch(List<Room> rooms, String query) {
  if (query.isEmpty) return rooms;
  final q = query.toLowerCase();
  return rooms.where((r) => roomMatchesQuery(r, q)).toList();
}

Set<String>? spaceRoomIds(SelectionService matrix) {
  final selectedIds = matrix.selectedSpaceIds;
  if (selectedIds.isEmpty) return null;

  final ids = <String>{};
  void collect(SpaceNode node) {
    ids.addAll(node.directChildRoomIds);
    for (final sub in node.subspaces) {
      collect(sub);
    }
  }
  for (final node in matrix.spaceTree) {
    if (selectedIds.contains(node.room.id)) collect(node);
  }
  return ids;
}

List<ListItem> buildSectionItems(
  SelectionService matrix,
  PreferencesService prefs,
  String query,
) {
  final collapsed = prefs.collapsedSpaceSections;
  final selectedIds = matrix.selectedSpaceIds;
  final tree = matrix.spaceTree;
  final items = <ListItem>[];

  // Invited rooms at the top (filtered by search)
  final invitedRooms = applySearch(matrix.invitedRooms, query);
  for (final room in invitedRooms) {
    items.add(InviteItem(room: room));
  }

  final pinnedIds = <String>{};

  if (selectedIds.isNotEmpty) {
    // Space selected: show only that space's rooms with subspace hierarchy
    final visibleNodes = tree
        .where((n) => selectedIds.contains(n.room.id))
        .toList();
    for (final node in visibleNodes) {
      _addSpaceSection(items, node, 0, matrix, collapsed, pinnedIds, query);
    }
  } else {
    // No space selected (Home): Pinned → DMs → Unsorted

    // Pinned section
    final pinnedRooms = applySearch(
        matrix.rooms.where((r) => r.isFavourite).toList(), query,);
    pinnedIds.addAll(pinnedRooms.map((r) => r.id));
    if (pinnedRooms.isNotEmpty) {
      items.add(HeaderItem(
        name: 'Pinned',
        sectionKey: PreferencesService.pinnedSectionKey,
        depth: 0,
        roomCount: pinnedRooms.length,
      ),);
      if (!collapsed.contains(PreferencesService.pinnedSectionKey)) {
        for (final room in pinnedRooms) {
          items.add(RoomItem(room: room));
        }
      }
    }

    // DMs section — all direct chats
    final dmRooms = applySearch(
        matrix.rooms.where((r) => r.isDirectChat && !pinnedIds.contains(r.id)).toList(), query,);
    if (dmRooms.isNotEmpty) {
      items.add(HeaderItem(
        name: 'Direct Messages',
        sectionKey: PreferencesService.dmSectionKey,
        depth: 0,
        roomCount: dmRooms.length,
      ),);
      if (!collapsed.contains(PreferencesService.dmSectionKey)) {
        for (final room in dmRooms) {
          items.add(RoomItem(room: room));
        }
      }
    }

    // Unsorted section (orphan group rooms)
    final orphans = applySearch(matrix.orphanRooms, query)
        .where((r) => !pinnedIds.contains(r.id) && !r.isDirectChat)
        .toList();
    if (orphans.isNotEmpty) {
      items.add(HeaderItem(
        name: 'Rooms',
        sectionKey: PreferencesService.unsortedSectionKey,
        depth: 0,
        roomCount: orphans.length,
      ),);
      if (!collapsed.contains(PreferencesService.unsortedSectionKey)) {
        for (final room in orphans) {
          items.add(RoomItem(room: room));
        }
      }
    }
  }

  return items;
}

void _addSpaceSection(
  List<ListItem> items,
  SpaceNode node,
  int depth,
  SelectionService matrix,
  Set<String> collapsed,
  Set<String> pinnedIds,
  String query,
) {
  // Single pass: collect subspace room IDs (for dedup) and count them.
  final subspaceRoomIds = <String>{};
  void collectSubspaces(List<SpaceNode> subs) {
    for (final sub in subs) {
      final subRooms = applySearch(matrix.roomsForSpace(sub.room.id), query)
          .where((r) => !pinnedIds.contains(r.id));
      subspaceRoomIds.addAll(subRooms.map((r) => r.id));
      collectSubspaces(sub.subspaces);
    }
  }
  collectSubspaces(node.subspaces);

  final rooms = applySearch(matrix.roomsForSpace(node.room.id), query)
      .where((r) => !pinnedIds.contains(r.id) &&
          !subspaceRoomIds.contains(r.id),)
      .toList();

  final totalRooms = rooms.length + subspaceRoomIds.length;

  // Always show subspace headers so users can see and manage newly created
  // (empty) subspaces. Only skip empty top-level space sections.
  if (totalRooms == 0 && node.subspaces.isEmpty && depth == 0) return;

  items.add(HeaderItem(
    name: node.room.getLocalizedDisplayname(),
    sectionKey: node.room.id,
    depth: depth,
    roomCount: totalRooms,
    isSpace: true,
  ),);

  if (!collapsed.contains(node.room.id)) {
    for (final room in rooms) {
      items.add(RoomItem(
        room: room,
        depth: depth,
        parentSpaceId: node.room.id,
        sectionRooms: rooms,
      ),);
    }
    for (final sub in node.subspaces) {
      _addSpaceSection(
          items, sub, depth + 1, matrix, collapsed, pinnedIds, query,);
    }
  }
}
