import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:matrix/matrix.dart';
import 'package:matrix/src/utils/cached_stream_controller.dart';
import 'package:matrix/src/utils/space_child.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:lattice/services/matrix_service.dart';

@GenerateNiceMocks([
  MockSpec<Client>(),
  MockSpec<Room>(),
  MockSpec<FlutterSecureStorage>(),
])
import 'matrix_service_test.mocks.dart';

void main() {
  late MockClient mockClient;
  late MockFlutterSecureStorage mockStorage;
  late MatrixService service;

  setUp(() {
    mockClient = MockClient();
    mockStorage = MockFlutterSecureStorage();
    when(mockClient.rooms).thenReturn([]);
    service = MatrixService(client: mockClient, storage: mockStorage);
  });

  group('selectSpace', () {
    test('updates selectedSpaceId and notifies listeners', () {
      var notified = false;
      service.addListener(() => notified = true);

      service.selectSpace('!space:example.com');

      expect(service.selectedSpaceId, '!space:example.com');
      expect(notified, isTrue);
    });

    test('can be cleared to null', () {
      service.selectSpace('!space:example.com');
      service.selectSpace(null);

      expect(service.selectedSpaceId, isNull);
    });
  });

  group('selectRoom', () {
    test('updates selectedRoomId and notifies listeners', () {
      var notified = false;
      service.addListener(() => notified = true);

      service.selectRoom('!room:example.com');

      expect(service.selectedRoomId, '!room:example.com');
      expect(notified, isTrue);
    });

    test('can be cleared to null', () {
      service.selectRoom('!room:example.com');
      service.selectRoom(null);

      expect(service.selectedRoomId, isNull);
    });
  });

  group('spaces getter', () {
    test('filters rooms to only spaces and sorts alphabetically', () {
      final space1 = MockRoom();
      when(space1.isSpace).thenReturn(true);
      when(space1.displayname).thenReturn('B Space');

      final space2 = MockRoom();
      when(space2.isSpace).thenReturn(true);
      when(space2.displayname).thenReturn('A Space');

      final room1 = MockRoom();
      when(room1.isSpace).thenReturn(false);

      when(mockClient.rooms).thenReturn([space1, room1, space2]);

      final spaces = service.spaces;
      expect(spaces, hasLength(2));
      expect(spaces[0].displayname, 'A Space');
      expect(spaces[1].displayname, 'B Space');
    });
  });

  group('rooms getter', () {
    test('filters out spaces and sorts by last event timestamp', () {
      final space = MockRoom();
      when(space.isSpace).thenReturn(true);

      final olderRoom = MockRoom();
      when(olderRoom.isSpace).thenReturn(false);
      when(olderRoom.id).thenReturn('!old:example.com');
      when(olderRoom.lastEvent).thenReturn(_fakeEvent(
        room: olderRoom,
        ts: DateTime(2024, 1, 1),
      ));

      final newerRoom = MockRoom();
      when(newerRoom.isSpace).thenReturn(false);
      when(newerRoom.id).thenReturn('!new:example.com');
      when(newerRoom.lastEvent).thenReturn(_fakeEvent(
        room: newerRoom,
        ts: DateTime(2024, 6, 1),
      ));

      when(mockClient.rooms).thenReturn([space, olderRoom, newerRoom]);

      final rooms = service.rooms;
      expect(rooms, hasLength(2));
      // Newer first (descending)
      expect(rooms[0].id, '!new:example.com');
      expect(rooms[1].id, '!old:example.com');
    });

    test('filters by selected space children when space is selected', () {
      final childRoom = MockRoom();
      when(childRoom.isSpace).thenReturn(false);
      when(childRoom.id).thenReturn('!child:example.com');
      when(childRoom.lastEvent).thenReturn(null);

      final otherRoom = MockRoom();
      when(otherRoom.isSpace).thenReturn(false);
      when(otherRoom.id).thenReturn('!other:example.com');
      when(otherRoom.lastEvent).thenReturn(null);

      final space = MockRoom();
      when(space.isSpace).thenReturn(true);
      when(space.id).thenReturn('!space:example.com');
      when(space.spaceChildren).thenReturn([
        _fakeSpaceChild('!child:example.com'),
      ]);

      when(mockClient.rooms).thenReturn([space, childRoom, otherRoom]);
      when(mockClient.getRoomById('!space:example.com')).thenReturn(space);

      service.selectSpace('!space:example.com');

      final rooms = service.rooms;
      expect(rooms, hasLength(1));
      expect(rooms[0].id, '!child:example.com');
    });
  });

  group('login', () {
    test('returns true on success and persists credentials', () async {
      when(mockClient.checkHomeserver(any)).thenAnswer((_) async => (
            null,
            GetVersionsResponse.fromJson({'versions': ['v1.1']}),
            <LoginFlow>[],
            null,
          ));
      when(mockClient.login(
        any,
        identifier: anyNamed('identifier'),
        password: anyNamed('password'),
        initialDeviceDisplayName: anyNamed('initialDeviceDisplayName'),
      )).thenAnswer((_) async => LoginResponse.fromJson({
            'access_token': 'token123',
            'device_id': 'DEV1',
            'user_id': '@user:example.com',
          }));
      when(mockClient.accessToken).thenReturn('token123');
      when(mockClient.userID).thenReturn('@user:example.com');
      when(mockClient.homeserver).thenReturn(Uri.parse('https://example.com'));
      when(mockClient.deviceID).thenReturn('DEV1');
      when(mockClient.onSync).thenReturn(CachedStreamController());

      final result = await service.login(
        homeserver: 'example.com',
        username: 'user',
        password: 'pass',
      );

      expect(result, isTrue);
      expect(service.isLoggedIn, isTrue);
      verify(mockStorage.write(
              key: 'lattice_access_token', value: 'token123'))
          .called(1);
      verify(mockStorage.write(
              key: 'lattice_user_id', value: '@user:example.com'))
          .called(1);
    });

    test('returns false on failure and sets loginError', () async {
      when(mockClient.checkHomeserver(any))
          .thenThrow(Exception('Connection refused'));

      final result = await service.login(
        homeserver: 'bad.server',
        username: 'user',
        password: 'pass',
      );

      expect(result, isFalse);
      expect(service.isLoggedIn, isFalse);
      expect(service.loginError, contains('Connection refused'));
    });
  });

  group('logout', () {
    test('clears state and secure storage', () async {
      // First log in
      when(mockClient.checkHomeserver(any)).thenAnswer((_) async => (
            null,
            GetVersionsResponse.fromJson({'versions': ['v1.1']}),
            <LoginFlow>[],
            null,
          ));
      when(mockClient.login(
        any,
        identifier: anyNamed('identifier'),
        password: anyNamed('password'),
        initialDeviceDisplayName: anyNamed('initialDeviceDisplayName'),
      )).thenAnswer((_) async => LoginResponse.fromJson({
            'access_token': 'token123',
            'device_id': 'DEV1',
            'user_id': '@user:example.com',
          }));
      when(mockClient.accessToken).thenReturn('token123');
      when(mockClient.userID).thenReturn('@user:example.com');
      when(mockClient.homeserver).thenReturn(Uri.parse('https://example.com'));
      when(mockClient.deviceID).thenReturn('DEV1');
      when(mockClient.onSync).thenReturn(CachedStreamController());

      await service.login(
        homeserver: 'example.com',
        username: 'user',
        password: 'pass',
      );
      service.selectSpace('!space:example.com');
      service.selectRoom('!room:example.com');

      await service.logout();

      expect(service.isLoggedIn, isFalse);
      expect(service.selectedSpaceId, isNull);
      expect(service.selectedRoomId, isNull);
      verify(mockStorage.deleteAll()).called(1);
    });
  });
}

/// Creates a real [Event] with the given timestamp.
Event _fakeEvent({required Room room, required DateTime ts}) {
  return Event(
    content: {'body': 'test', 'msgtype': 'm.text'},
    type: EventTypes.Message,
    eventId: '\$evt_${ts.millisecondsSinceEpoch}',
    senderId: '@user:example.com',
    originServerTs: ts,
    room: room,
  );
}

/// Creates a [SpaceChild] from a synthetic state event.
SpaceChild _fakeSpaceChild(String roomId) {
  return SpaceChild.fromState(StrippedStateEvent(
    type: EventTypes.SpaceChild,
    content: {'via': ['example.com']},
    senderId: '@admin:example.com',
    stateKey: roomId,
  ));
}
