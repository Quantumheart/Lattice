import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:lattice/core/models/space_node.dart';
import 'package:lattice/core/utils/order_utils.dart' as order_utils;
import 'package:matrix/matrix.dart';

class SelectionService extends ChangeNotifier {
  SelectionService({required Client client}) : _client = client {
    _syncSub = _client.onSync.stream.listen((_) {
      invalidateSpaceTree();
      notifyListeners();
    });
  }

  final Client _client;
  StreamSubscription<SyncUpdate>? _syncSub;

  // ── Space multi-select ──────────────────────────────────────
  final Set<String> _selectedSpaceIds = {};
  Set<String> get selectedSpaceIds => Set.unmodifiable(_selectedSpaceIds);

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

  void toggleSpaceSelection(String spaceId) {
    if (!_selectedSpaceIds.remove(spaceId)) {
      _selectedSpaceIds.add(spaceId);
    }
    _spaceTreeDirty = true;
    notifyListeners();
  }

  void clearSpaceSelection() {
    _selectedSpaceIds.clear();
    _spaceTreeDirty = true;
    notifyListeners();
  }

  // ── Room selection ──────────────────────────────────────────
  String? _selectedRoomId;
  String? get selectedRoomId => _selectedRoomId;

  Room? get selectedRoom =>
      _selectedRoomId != null ? _client.getRoomById(_selectedRoomId!) : null;

  void selectRoom(String? roomId) {
    _selectedRoomId = roomId;
    notifyListeners();
  }

  void resetSelection() {
    _selectedSpaceIds.clear();
    _selectedRoomId = null;
  }

  // ── Custom space ordering ──────────────────────────────────
  List<String> _customSpaceOrder = [];

  void updateSpaceOrder(List<String> order) {
    if (listEquals(_customSpaceOrder, order)) return;
    _customSpaceOrder = order;
    _spaceTreeDirty = true;
    notifyListeners();
  }

  List<T> _sortByCustomOrder<T>(
    List<T> items,
    String Function(T) getId,
    String Function(T) getName,
  ) {
    if (_customSpaceOrder.isEmpty) {
      return items..sort((a, b) => getName(a).compareTo(getName(b)));
    }
    final orderIndex = <String, int>{};
    for (var i = 0; i < _customSpaceOrder.length; i++) {
      orderIndex[_customSpaceOrder[i]] = i;
    }
    final ordered = <T>[];
    final unordered = <T>[];
    for (final item in items) {
      if (orderIndex.containsKey(getId(item))) {
        ordered.add(item);
      } else {
        unordered.add(item);
      }
    }
    ordered.sort((a, b) => orderIndex[getId(a)]!.compareTo(orderIndex[getId(b)]!));
    unordered.sort((a, b) => getName(a).compareTo(getName(b)));
    return [...ordered, ...unordered];
  }

  // ── Space tree with lazy caching ────────────────────────────
  List<SpaceNode>? _cachedSpaceTree;
  Set<String>? _cachedAllSpaceRoomIds;
  Map<String, Set<String>>? _cachedRoomToSpaces;
  Map<String, SpaceNode>? _cachedNodeById;
  List<Room>? _cachedRooms;
  bool _spaceTreeDirty = true;

  void invalidateSpaceTree() {
    _spaceTreeDirty = true;
  }

  void _rebuildSpaceTree() {
    final allSpaces = _client.rooms
        .where((r) => r.isSpace && r.membership == Membership.join)
        .toList();

    final nodeMap = <String, _MutableNode>{};
    for (final space in allSpaces) {
      final subspaceIds = <String>[];
      final childRoomIds = <String>[];
      for (final child in space.spaceChildren) {
        final childId = child.roomId;
        if (childId == null) continue;
        final childRoom = _client.getRoomById(childId);
        if (childRoom == null || childRoom.membership != Membership.join) {
          continue;
        }
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

    final childSpaceIds = <String>{};
    for (final node in nodeMap.values) {
      childSpaceIds.addAll(node.subspaceIds);
    }

    SpaceNode buildNode(String spaceId) {
      final mutable = nodeMap[spaceId]!;
      return SpaceNode(
        room: mutable.room,
        subspaces: mutable.subspaceIds
            .where(nodeMap.containsKey)
            .map(buildNode)
            .toList()
          ..sort((a, b) => a.room
              .getLocalizedDisplayname()
              .compareTo(b.room.getLocalizedDisplayname()),),
        directChildRoomIds: mutable.directChildRoomIds,
      );
    }

    final topLevel = _sortByCustomOrder(
      nodeMap.keys
          .where((id) => !childSpaceIds.contains(id))
          .map(buildNode)
          .toList(),
      (n) => n.room.id,
      (n) => n.room.getLocalizedDisplayname(),
    );

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

    final flatNodeMap = <String, SpaceNode>{};
    void indexNodes(List<SpaceNode> nodes) {
      for (final node in nodes) {
        flatNodeMap[node.room.id] = node;
        indexNodes(node.subspaces);
      }
    }
    indexNodes(topLevel);

    final sortedRooms = _client.rooms
        .where((r) => !r.isSpace && r.membership == Membership.join)
        .toList()
      ..sort((a, b) {
        final aTs = a.lastEvent?.originServerTs ?? DateTime(1970);
        final bTs = b.lastEvent?.originServerTs ?? DateTime(1970);
        return bTs.compareTo(aTs);
      });

    _cachedSpaceTree = topLevel;
    _cachedAllSpaceRoomIds = allRoomIds;
    _cachedRoomToSpaces = roomToSpaces;
    _cachedNodeById = flatNodeMap;
    _cachedRooms = sortedRooms;
    _spaceTreeDirty = false;
  }

  void _ensureTreeFresh() {
    if (_spaceTreeDirty) _rebuildSpaceTree();
  }

  List<SpaceNode> get spaceTree {
    _ensureTreeFresh();
    return _cachedSpaceTree!;
  }

  // ── Helpers ──────────────────────────────────────────────────

  List<Room> get spaces => _sortByCustomOrder(
        _client.rooms
            .where((r) => r.isSpace && r.membership == Membership.join)
            .toList(),
        (r) => r.id,
        (r) => r.getLocalizedDisplayname(),
      );

  List<Room> get topLevelSpaces => spaceTree.map((n) => n.room).toList();

  List<Room> get rooms {
    _ensureTreeFresh();
    return _cachedRooms!;
  }

  List<Room> get invitedRooms => _client.rooms
      .where((r) => !r.isSpace && r.membership == Membership.invite)
      .toList()
    ..sort((a, b) => a.getLocalizedDisplayname().compareTo(
        b.getLocalizedDisplayname(),),);

  List<Room> get invitedSpaces => _client.rooms
      .where((r) => r.isSpace && r.membership == Membership.invite)
      .toList()
    ..sort((a, b) => a.getLocalizedDisplayname().compareTo(
        b.getLocalizedDisplayname(),),);

  String? inviterDisplayName(Room room) {
    final userId = _client.userID;
    if (userId == null) return null;
    final inviteState = room.getState(EventTypes.RoomMember, userId);
    if (inviteState == null) return null;
    final senderId = inviteState.senderId;
    return room.unsafeGetUserFromMemoryOrFallback(senderId).calcDisplayname();
  }

  List<Room> get orphanRooms {
    _ensureTreeFresh();
    final spaceRoomIds = _cachedAllSpaceRoomIds!;
    return rooms.where((r) => !spaceRoomIds.contains(r.id)).toList();
  }

  List<Room> roomsForSpace(String spaceId) {
    _ensureTreeFresh();
    final space = _client.getRoomById(spaceId);
    if (space == null) return [];
    final childIds = <String>{};
    for (final child in space.spaceChildren) {
      final childId = child.roomId;
      if (childId == null) continue;
      final childRoom = _client.getRoomById(childId);
      if (childRoom != null && !childRoom.isSpace) {
        childIds.add(childId);
      }
    }
    final orderMap = order_utils.buildOrderMap(space);
    final result = rooms.where((r) => childIds.contains(r.id)).toList();
    result.sort((a, b) {
      final aOrder = orderMap[a.id];
      final bOrder = orderMap[b.id];
      if (aOrder != null && bOrder != null) return aOrder.compareTo(bOrder);
      if (aOrder != null) return -1;
      if (bOrder != null) return 1;
      return a.getLocalizedDisplayname().compareTo(b.getLocalizedDisplayname());
    });
    return result;
  }

  Set<String> spaceMemberships(String roomId) {
    _ensureTreeFresh();
    return _cachedRoomToSpaces?[roomId] ?? const {};
  }

  @override
  void dispose() {
    unawaited(_syncSub?.cancel());
    _syncSub = null;
    super.dispose();
  }

  int unreadCountForSpace(String spaceId) {
    _ensureTreeFresh();
    final node = _cachedNodeById![spaceId];
    if (node == null) return 0;

    var count = 0;
    void walk(SpaceNode n) {
      for (final roomId in n.directChildRoomIds) {
        final room = _client.getRoomById(roomId);
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
