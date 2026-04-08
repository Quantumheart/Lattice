import 'package:flutter_test/flutter_test.dart';
import 'package:lattice/core/services/sub_services/selection_service.dart';
import 'package:matrix/matrix.dart';
import 'package:matrix/src/utils/cached_stream_controller.dart';
import 'package:matrix/src/utils/space_child.dart';
import 'package:mockito/mockito.dart';

import 'matrix_service_test.mocks.dart';

SpaceChild _fakeSpaceChild(String roomId) {
  return SpaceChild.fromState(
    StrippedStateEvent(
      type: EventTypes.SpaceChild,
      content: {
        'via': ['example.com'],
      },
      senderId: '@admin:example.com',
      stateKey: roomId,
    ),
  );
}

void main() {
  late MockClient mockClient;
  late SelectionService service;
  late int changeCount;

  setUp(() {
    mockClient = MockClient();
    changeCount = 0;
    when(mockClient.rooms).thenReturn([]);
    when(mockClient.onSync)
        .thenReturn(CachedStreamController<SyncUpdate>());
    service = SelectionService(client: mockClient);
    service.addListener(() => changeCount++);
  });

  group('selectSpace', () {
    test('sets single selection and fires onChanged', () {
      service.selectSpace('!space:example.com');

      expect(service.selectedSpaceIds, {'!space:example.com'});
      expect(changeCount, 1);
    });

    test('clears on null', () {
      service.selectSpace('!space:example.com');
      service.selectSpace(null);

      expect(service.selectedSpaceIds, isEmpty);
      expect(changeCount, 2);
    });

    test('clears on re-select of sole selection', () {
      service.selectSpace('!space:example.com');
      service.selectSpace('!space:example.com');

      expect(service.selectedSpaceIds, isEmpty);
    });
  });

  group('toggleSpaceSelection', () {
    test('adds space to multi-select', () {
      service.toggleSpaceSelection('!s1:e.com');
      service.toggleSpaceSelection('!s2:e.com');

      expect(service.selectedSpaceIds, {'!s1:e.com', '!s2:e.com'});
    });

    test('removes space from multi-select', () {
      service.toggleSpaceSelection('!s1:e.com');
      service.toggleSpaceSelection('!s1:e.com');

      expect(service.selectedSpaceIds, isEmpty);
    });
  });

  group('clearSpaceSelection', () {
    test('clears all selections', () {
      service.toggleSpaceSelection('!s1:e.com');
      service.toggleSpaceSelection('!s2:e.com');
      service.clearSpaceSelection();

      expect(service.selectedSpaceIds, isEmpty);
    });
  });

  group('selectRoom', () {
    test('sets selected room and fires onChanged', () {
      service.selectRoom('!room:e.com');

      expect(service.selectedRoomId, '!room:e.com');
      expect(changeCount, 1);
    });

    test('selectedRoom returns Room from client', () {
      final mockRoom = MockRoom();
      when(mockClient.getRoomById('!room:e.com')).thenReturn(mockRoom);

      service.selectRoom('!room:e.com');

      expect(service.selectedRoom, mockRoom);
    });

    test('selectedRoom returns null when no room selected', () {
      expect(service.selectedRoom, isNull);
    });
  });

  group('resetSelection', () {
    test('clears all state', () {
      service.selectSpace('!space:e.com');
      service.selectRoom('!room:e.com');

      service.resetSelection();

      expect(service.selectedSpaceIds, isEmpty);
      expect(service.selectedRoomId, isNull);
    });
  });

  group('updateSpaceOrder', () {
    test('no-op if order is identical', () {
      service.updateSpaceOrder(['a', 'b']);
      final countBefore = changeCount;

      service.updateSpaceOrder(['a', 'b']);

      expect(changeCount, countBefore);
    });

    test('fires onChanged when order changes', () {
      service.updateSpaceOrder(['a', 'b']);
      final countBefore = changeCount;

      service.updateSpaceOrder(['b', 'a']);

      expect(changeCount, greaterThan(countBefore));
    });
  });

  group('spaceTree', () {
    test('builds correct hierarchy from client rooms', () {
      final parentSpace = MockRoom();
      final childSpace = MockRoom();
      final childRoom = MockRoom();

      when(parentSpace.id).thenReturn('!parent:e.com');
      when(parentSpace.isSpace).thenReturn(true);
      when(parentSpace.membership).thenReturn(Membership.join);
      when(parentSpace.getLocalizedDisplayname()).thenReturn('Parent');
      when(parentSpace.spaceChildren).thenReturn([
        _fakeSpaceChild('!child_space:e.com'),
        _fakeSpaceChild('!room:e.com'),
      ]);

      when(childSpace.id).thenReturn('!child_space:e.com');
      when(childSpace.isSpace).thenReturn(true);
      when(childSpace.membership).thenReturn(Membership.join);
      when(childSpace.getLocalizedDisplayname()).thenReturn('Child Space');
      when(childSpace.spaceChildren).thenReturn([]);

      when(childRoom.id).thenReturn('!room:e.com');
      when(childRoom.isSpace).thenReturn(false);
      when(childRoom.membership).thenReturn(Membership.join);
      when(childRoom.getLocalizedDisplayname()).thenReturn('Room');

      when(mockClient.rooms).thenReturn([parentSpace, childSpace, childRoom]);
      when(mockClient.getRoomById('!child_space:e.com')).thenReturn(childSpace);
      when(mockClient.getRoomById('!room:e.com')).thenReturn(childRoom);

      service.invalidateSpaceTree();
      final tree = service.spaceTree;

      expect(tree, hasLength(1));
      expect(tree[0].room.id, '!parent:e.com');
      expect(tree[0].subspaces, hasLength(1));
      expect(tree[0].directChildRoomIds, ['!room:e.com']);
    });
  });

  group('rooms', () {
    test('returns non-space joined rooms sorted by recency', () {
      final room1 = MockRoom();
      final room2 = MockRoom();

      when(room1.id).thenReturn('!r1:e.com');
      when(room1.isSpace).thenReturn(false);
      when(room1.membership).thenReturn(Membership.join);
      when(room1.getLocalizedDisplayname()).thenReturn('Room 1');
      when(room1.lastEvent).thenReturn(
        Event(
          type: 'm.room.message',
          content: {'body': 'old'},
          senderId: '@a:e.com',
          eventId: r'$1',
          originServerTs: DateTime(2024),
          room: room1,
        ),
      );

      when(room2.id).thenReturn('!r2:e.com');
      when(room2.isSpace).thenReturn(false);
      when(room2.membership).thenReturn(Membership.join);
      when(room2.getLocalizedDisplayname()).thenReturn('Room 2');
      when(room2.lastEvent).thenReturn(
        Event(
          type: 'm.room.message',
          content: {'body': 'new'},
          senderId: '@a:e.com',
          eventId: r'$2',
          originServerTs: DateTime(2024, 6),
          room: room2,
        ),
      );

      when(mockClient.rooms).thenReturn([room1, room2]);
      service.invalidateSpaceTree();

      final rooms = service.rooms;

      expect(rooms[0].id, '!r2:e.com');
      expect(rooms[1].id, '!r1:e.com');
    });
  });

  group('invitedRooms', () {
    test('filters correctly', () {
      final invited = MockRoom();
      final joined = MockRoom();

      when(invited.isSpace).thenReturn(false);
      when(invited.membership).thenReturn(Membership.invite);
      when(invited.getLocalizedDisplayname()).thenReturn('Invited Room');

      when(joined.isSpace).thenReturn(false);
      when(joined.membership).thenReturn(Membership.join);

      when(mockClient.rooms).thenReturn([invited, joined]);

      expect(service.invitedRooms, hasLength(1));
      expect(
        service.invitedRooms[0].getLocalizedDisplayname(),
        'Invited Room',
      );
    });
  });

  group('invitedSpaces', () {
    test('filters correctly', () {
      final invitedSpace = MockRoom();
      final invitedRoom = MockRoom();

      when(invitedSpace.isSpace).thenReturn(true);
      when(invitedSpace.membership).thenReturn(Membership.invite);
      when(invitedSpace.getLocalizedDisplayname()).thenReturn('Space');

      when(invitedRoom.isSpace).thenReturn(false);
      when(invitedRoom.membership).thenReturn(Membership.invite);

      when(mockClient.rooms).thenReturn([invitedSpace, invitedRoom]);

      expect(service.invitedSpaces, hasLength(1));
    });
  });

  group('orphanRooms', () {
    test('excludes rooms in any space', () {
      final space = MockRoom();
      final roomInSpace = MockRoom();
      final orphan = MockRoom();

      when(space.id).thenReturn('!space:e.com');
      when(space.isSpace).thenReturn(true);
      when(space.membership).thenReturn(Membership.join);
      when(space.getLocalizedDisplayname()).thenReturn('Space');
      when(space.spaceChildren)
          .thenReturn([_fakeSpaceChild('!in_space:e.com')]);

      when(roomInSpace.id).thenReturn('!in_space:e.com');
      when(roomInSpace.isSpace).thenReturn(false);
      when(roomInSpace.membership).thenReturn(Membership.join);
      when(roomInSpace.getLocalizedDisplayname()).thenReturn('In Space');
      when(roomInSpace.lastEvent).thenReturn(null);

      when(orphan.id).thenReturn('!orphan:e.com');
      when(orphan.isSpace).thenReturn(false);
      when(orphan.membership).thenReturn(Membership.join);
      when(orphan.getLocalizedDisplayname()).thenReturn('Orphan');
      when(orphan.lastEvent).thenReturn(null);

      when(mockClient.rooms).thenReturn([space, roomInSpace, orphan]);
      when(mockClient.getRoomById('!in_space:e.com')).thenReturn(roomInSpace);

      service.invalidateSpaceTree();

      expect(service.orphanRooms.map((r) => r.id), ['!orphan:e.com']);
    });
  });

  group('spaceMemberships', () {
    test('returns correct space set', () {
      final space = MockRoom();
      final room = MockRoom();

      when(space.id).thenReturn('!space:e.com');
      when(space.isSpace).thenReturn(true);
      when(space.membership).thenReturn(Membership.join);
      when(space.getLocalizedDisplayname()).thenReturn('Space');
      when(space.spaceChildren).thenReturn([_fakeSpaceChild('!room:e.com')]);

      when(room.id).thenReturn('!room:e.com');
      when(room.isSpace).thenReturn(false);
      when(room.membership).thenReturn(Membership.join);
      when(room.lastEvent).thenReturn(null);

      when(mockClient.rooms).thenReturn([space, room]);
      when(mockClient.getRoomById('!room:e.com')).thenReturn(room);

      service.invalidateSpaceTree();

      expect(service.spaceMemberships('!room:e.com'), {'!space:e.com'});
      expect(service.spaceMemberships('!unknown:e.com'), isEmpty);
    });
  });

  group('unreadCountForSpace', () {
    test('aggregates including subspaces', () {
      final parentSpace = MockRoom();
      final childSpace = MockRoom();
      final room1 = MockRoom();
      final room2 = MockRoom();

      when(parentSpace.id).thenReturn('!parent:e.com');
      when(parentSpace.isSpace).thenReturn(true);
      when(parentSpace.membership).thenReturn(Membership.join);
      when(parentSpace.getLocalizedDisplayname()).thenReturn('Parent');
      when(parentSpace.spaceChildren).thenReturn([
        _fakeSpaceChild('!child:e.com'),
        _fakeSpaceChild('!r1:e.com'),
      ]);

      when(childSpace.id).thenReturn('!child:e.com');
      when(childSpace.isSpace).thenReturn(true);
      when(childSpace.membership).thenReturn(Membership.join);
      when(childSpace.getLocalizedDisplayname()).thenReturn('Child');
      when(childSpace.spaceChildren).thenReturn([_fakeSpaceChild('!r2:e.com')]);

      when(room1.id).thenReturn('!r1:e.com');
      when(room1.isSpace).thenReturn(false);
      when(room1.membership).thenReturn(Membership.join);
      when(room1.notificationCount).thenReturn(3);
      when(room1.lastEvent).thenReturn(null);

      when(room2.id).thenReturn('!r2:e.com');
      when(room2.isSpace).thenReturn(false);
      when(room2.membership).thenReturn(Membership.join);
      when(room2.notificationCount).thenReturn(5);
      when(room2.lastEvent).thenReturn(null);

      when(mockClient.rooms)
          .thenReturn([parentSpace, childSpace, room1, room2]);
      when(mockClient.getRoomById('!child:e.com')).thenReturn(childSpace);
      when(mockClient.getRoomById('!r1:e.com')).thenReturn(room1);
      when(mockClient.getRoomById('!r2:e.com')).thenReturn(room2);

      service.invalidateSpaceTree();

      expect(service.unreadCountForSpace('!parent:e.com'), 8);
    });
  });

  group('invalidateSpaceTree', () {
    test('marks cache dirty', () {
      service.invalidateSpaceTree();
      expect(service.spaceTree, isEmpty);
    });
  });
}
