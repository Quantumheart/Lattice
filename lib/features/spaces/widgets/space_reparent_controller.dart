import 'package:flutter/foundation.dart';

import 'package:kohera/core/models/space_node.dart';

// ── Drag data types ─────────────────────────────────────────
sealed class ReparentDragData {}

class SpaceDragData extends ReparentDragData {
  final String spaceId;
  SpaceDragData({required this.spaceId});
}

class RoomDragData extends ReparentDragData {
  final String roomId;
  final String? currentParentSpaceId;
  RoomDragData({required this.roomId, this.currentParentSpaceId});
}

// ── Controller ──────────────────────────────────────────────
class SpaceReparentController extends ChangeNotifier {
  ReparentDragData? _draggingData;
  String? _hoveredHeaderId;

  ReparentDragData? get draggingData => _draggingData;
  String? get hoveredHeaderId => _hoveredHeaderId;
  bool get isDragging => _draggingData != null;

  void startDrag(ReparentDragData data) {
    _draggingData = data;
    notifyListeners();
  }

  void setHoveredHeader(String? sectionKey) {
    if (_hoveredHeaderId == sectionKey) return;
    _hoveredHeaderId = sectionKey;
    notifyListeners();
  }

  void endDrag() {
    _draggingData = null;
    _hoveredHeaderId = null;
    notifyListeners();
  }
}

// ── Cycle detection ─────────────────────────────────────────
/// Returns `true` if reparenting [candidateId] under [newParentId]
/// would create a cycle in the space tree.
///
/// Walks the candidate's subtree to check whether [newParentId]
/// is a descendant of [candidateId].
bool wouldCreateCycle(
  List<SpaceNode> tree,
  String newParentId,
  String candidateId,
) {
  // Dropping onto itself is a cycle.
  if (newParentId == candidateId) return true;

  // Find the candidate node and check if newParentId is in its subtree.
  SpaceNode? findNode(List<SpaceNode> nodes, String id) {
    for (final node in nodes) {
      if (node.room.id == id) return node;
      final found = findNode(node.subspaces, id);
      if (found != null) return found;
    }
    return null;
  }

  final candidateNode = findNode(tree, candidateId);
  if (candidateNode == null) return false;

  bool isDescendant(SpaceNode node, String targetId) {
    for (final sub in node.subspaces) {
      if (sub.room.id == targetId) return true;
      if (isDescendant(sub, targetId)) return true;
    }
    return false;
  }

  return isDescendant(candidateNode, newParentId);
}
