import 'package:matrix/matrix.dart';

/// A node in the space tree representing a joined space and its children.
class SpaceNode {
  final Room room;
  final List<SpaceNode> subspaces;
  final List<String> directChildRoomIds;

  const SpaceNode({
    required this.room,
    this.subspaces = const [],
    this.directChildRoomIds = const [],
  });
}
