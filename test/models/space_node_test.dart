import 'package:flutter_test/flutter_test.dart';
import 'package:lattice/core/models/space_node.dart';
import 'package:matrix/matrix.dart';
import 'package:mockito/mockito.dart';

class _MockRoom extends Mock implements Room {}

void main() {
  group('SpaceNode', () {
    test('creates with defaults', () {
      final room = _MockRoom();
      final node = SpaceNode(room: room);
      expect(node.room, room);
      expect(node.subspaces, isEmpty);
      expect(node.directChildRoomIds, isEmpty);
    });

    test('creates with subspaces and child room IDs', () {
      final parent = _MockRoom();
      final child = _MockRoom();
      final childNode = SpaceNode(room: child);

      final node = SpaceNode(
        room: parent,
        subspaces: [childNode],
        directChildRoomIds: ['!room1:x.com', '!room2:x.com'],
      );

      expect(node.subspaces, hasLength(1));
      expect(node.subspaces[0].room, child);
      expect(node.directChildRoomIds, ['!room1:x.com', '!room2:x.com']);
    });
  });
}
