import 'package:flutter/foundation.dart';
import 'package:matrix/matrix.dart';

import '../../models/space_node.dart';

/// Room/space selection state, space tree, and filtered-room helpers.
mixin SelectionMixin on ChangeNotifier {
  Client get client;

  // ── Space multi-select ──────────────────────────────────────
  final Set<String> _selectedSpaceIds = {};
  Set<String> get selectedSpaceIds => Set.unmodifiable(_selectedSpaceIds);

  /// Replace selection with a single space, or clear if [spaceId] is null
  /// or already the only selected space.
  void selectSpace(String? spaceId) {
    if (spaceId == null) {
      _selectedSpaceIds.clear();
    } else if (_selectedSpaceIds.length == 1 &&
        _selectedSpaceIds.contains(spaceId)) {
      _selectedSpaceIds.clear();
    } else {
      _selectedSpaceIds
        ..clear()
        ..add(spaceId);
    }
    _spaceTreeDirty = true;
    notifyListeners();
  }

  /// Toggle a space in/out of the multi-select set.
  void toggleSpaceSelection(String spaceId) {
    if (!_selectedSpaceIds.remove(spaceId)) {
      _selectedSpaceIds.add(spaceId);
    }
    _spaceTreeDirty = true;
    notifyListeners();
  }

  /// Clear all space selections (show all rooms).
  void clearSpaceSelection() {
    _selectedSpaceIds.clear();
    _spaceTreeDirty = true;
    notifyListeners();
  }

  // ── Room selection ──────────────────────────────────────────
  String? _selectedRoomId;
  String? get selectedRoomId => _selectedRoomId;

  Room? get selectedRoom =>
      _selectedRoomId != null ? client.getRoomById(_selectedRoomId!) : null;

  void selectRoom(String? roomId) {
    _selectedRoomId = roomId;
    notifyListeners();
  }

  /// Reset selection state (e.g. on logout).
  @protected
  void resetSelection() {
    _selectedSpaceIds.clear();
    _selectedRoomId = null;
  }

  // ── Space tree with lazy caching ────────────────────────────
  List<SpaceNode>? _cachedSpaceTree;
  Set<String>? _cachedAllSpaceRoomIds;
  Map<String, Set<String>>? _cachedRoomToSpaces;
  bool _spaceTreeDirty = true;

  @override
  void notifyListeners() {
    _spaceTreeDirty = true;
    super.notifyListeners();
  }

  void _rebuildSpaceTree() {
    final allSpaces = client.rooms.where((r) => r.isSpace).toList();

    // Build a map: spaceId → SpaceNode (flat, no nesting yet)
    final nodeMap = <String, _MutableNode>{};
    for (final space in allSpaces) {
      final subspaceIds = <String>[];
      final childRoomIds = <String>[];
      for (final child in space.spaceChildren) {
        final childId = child.roomId;
        if (childId == null) continue;
        final childRoom = client.getRoomById(childId);
        if (childRoom == null) continue; // unjoined — skip
        if (childRoom.isSpace) {
          subspaceIds.add(childId);
        } else {
          childRoomIds.add(childId);
        }
      }
      nodeMap[space.id] = _MutableNode(
        room: space,
        subspaceIds: subspaceIds,
        directChildRoomIds: childRoomIds,
      );
    }

    // Determine which spaces are children of another space.
    final childSpaceIds = <String>{};
    for (final node in nodeMap.values) {
      childSpaceIds.addAll(node.subspaceIds);
    }

    // Recursively build SpaceNode tree.
    SpaceNode buildNode(String spaceId) {
      final mutable = nodeMap[spaceId]!;
      return SpaceNode(
        room: mutable.room,
        subspaces: mutable.subspaceIds
            .where((id) => nodeMap.containsKey(id))
            .map((id) => buildNode(id))
            .toList()
          ..sort((a, b) => a.room
              .getLocalizedDisplayname()
              .compareTo(b.room.getLocalizedDisplayname())),
        directChildRoomIds: mutable.directChildRoomIds,
      );
    }

    // Top-level = spaces not a child of any other joined space.
    final topLevel = nodeMap.keys
        .where((id) => !childSpaceIds.contains(id))
        .map((id) => buildNode(id))
        .toList()
      ..sort((a, b) => a.room
          .getLocalizedDisplayname()
          .compareTo(b.room.getLocalizedDisplayname()));

    // Build allSpaceRoomIds and roomToSpaces in a single tree walk.
    final allRoomIds = <String>{};
    final roomToSpaces = <String, Set<String>>{};

    void walkTree(SpaceNode node) {
      for (final roomId in node.directChildRoomIds) {
        allRoomIds.add(roomId);
        (roomToSpaces[roomId] ??= {}).add(node.room.id);
      }
      for (final sub in node.subspaces) {
        walkTree(sub);
      }
    }

    for (final node in topLevel) {
      walkTree(node);
    }

    _cachedSpaceTree = topLevel;
    _cachedAllSpaceRoomIds = allRoomIds;
    _cachedRoomToSpaces = roomToSpaces;
    _spaceTreeDirty = false;
  }

  void _ensureTreeFresh() {
    if (_spaceTreeDirty) _rebuildSpaceTree();
  }

  /// The space tree rooted at top-level spaces.
  List<SpaceNode> get spaceTree {
    _ensureTreeFresh();
    return _cachedSpaceTree!;
  }

  // ── Helpers ──────────────────────────────────────────────────

  /// Returns spaces (rooms with type m.space).
  List<Room> get spaces => client.rooms
      .where((r) => r.isSpace)
      .toList()
    ..sort((a, b) =>
        a.getLocalizedDisplayname().compareTo(b.getLocalizedDisplayname()));

  /// Returns all non-space rooms sorted by recency.
  List<Room> get rooms {
    final list = client.rooms.where((r) => !r.isSpace).toList()
      ..sort((a, b) {
        final aTs = a.lastEvent?.originServerTs ?? DateTime(1970);
        final bTs = b.lastEvent?.originServerTs ?? DateTime(1970);
        return bTs.compareTo(aTs);
      });
    return list;
  }

  /// Rooms that don't belong to any space.
  List<Room> get orphanRooms {
    _ensureTreeFresh();
    final spaceRoomIds = _cachedAllSpaceRoomIds!;
    return rooms.where((r) => !spaceRoomIds.contains(r.id)).toList();
  }

  /// Direct child rooms of a specific space (not recursive into subspaces).
  List<Room> roomsForSpace(String spaceId) {
    _ensureTreeFresh();
    final space = client.getRoomById(spaceId);
    if (space == null) return [];
    final childIds = <String>{};
    for (final child in space.spaceChildren) {
      final childId = child.roomId;
      if (childId == null) continue;
      final childRoom = client.getRoomById(childId);
      if (childRoom != null && !childRoom.isSpace) {
        childIds.add(childId);
      }
    }
    return rooms.where((r) => childIds.contains(r.id)).toList();
  }

  /// Which spaces a room belongs to (O(1) map lookup).
  Set<String> spaceMemberships(String roomId) {
    _ensureTreeFresh();
    return _cachedRoomToSpaces?[roomId] ?? const {};
  }

  /// Aggregate unread count for a space (including subspace children).
  int unreadCountForSpace(String spaceId) {
    _ensureTreeFresh();
    SpaceNode? findNode(List<SpaceNode> nodes, String id) {
      for (final node in nodes) {
        if (node.room.id == id) return node;
        final found = findNode(node.subspaces, id);
        if (found != null) return found;
      }
      return null;
    }

    final node = findNode(_cachedSpaceTree!, spaceId);
    if (node == null) return 0;

    var count = 0;
    void walk(SpaceNode n) {
      for (final roomId in n.directChildRoomIds) {
        final room = client.getRoomById(roomId);
        if (room != null) count += room.notificationCount;
      }
      for (final sub in n.subspaces) {
        walk(sub);
      }
    }

    walk(node);
    return count;
  }
}

/// Internal mutable helper used only during tree construction.
class _MutableNode {
  final Room room;
  final List<String> subspaceIds;
  final List<String> directChildRoomIds;

  _MutableNode({
    required this.room,
    required this.subspaceIds,
    required this.directChildRoomIds,
  });
}
