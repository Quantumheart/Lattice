import 'dart:async';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lattice/core/services/matrix_service.dart';
import 'package:lattice/core/services/mixins/call_mixin.dart';
import 'package:matrix/matrix.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

@GenerateNiceMocks([
  MockSpec<Client>(),
  MockSpec<Room>(),
  MockSpec<FlutterSecureStorage>(),
  MockSpec<VoIP>(),
  MockSpec<GroupCallSession>(),
])
import 'call_mixin_test.mocks.dart';

void main() {
  late MockClient mockClient;
  late MockFlutterSecureStorage mockStorage;
  late MatrixService service;
  late MockVoIP mockVoip;

  setUp(() {
    mockClient = MockClient();
    mockStorage = MockFlutterSecureStorage();
    mockVoip = MockVoIP();
    when(mockClient.rooms).thenReturn([]);
    service = MatrixService(
      client: mockClient,
      storage: mockStorage,
      clientName: 'test',
    );
  });

  void injectVoip() {
    service.voipForTest = mockVoip;
  }

  group('CallMixin initial state', () {
    test('callState starts as idle', () {
      expect(service.callState, LatticeCallState.idle);
    });

    test('activeGroupCall starts as null', () {
      expect(service.activeGroupCall, isNull);
    });

    test('activeCallRoomId starts as null', () {
      expect(service.activeCallRoomId, isNull);
    });

    test('voip starts as null before init', () {
      expect(service.voip, isNull);
    });
  });

  group('roomHasActiveCall', () {
    test('returns false when voip is null', () {
      expect(service.roomHasActiveCall('!room:example.com'), isFalse);
    });

    test('returns false for unknown room', () {
      injectVoip();
      when(mockClient.getRoomById(any)).thenReturn(null);
      expect(service.roomHasActiveCall('!room:example.com'), isFalse);
    });
  });

  group('activeCallIdsForRoom', () {
    test('returns empty when voip is null', () {
      expect(service.activeCallIdsForRoom('!room:example.com'), isEmpty);
    });

    test('returns empty for unknown room', () {
      injectVoip();
      when(mockClient.getRoomById(any)).thenReturn(null);
      expect(service.activeCallIdsForRoom('!room:example.com'), isEmpty);
    });
  });

  group('callParticipantCount', () {
    test('returns 0 when voip is null', () {
      expect(service.callParticipantCount('!room:example.com', 'call1'), 0);
    });

    test('returns 0 for unknown room', () {
      injectVoip();
      when(mockClient.getRoomById(any)).thenReturn(null);
      expect(service.callParticipantCount('!room:example.com', 'call1'), 0);
    });
  });

  group('callMembershipsForRoom', () {
    test('returns empty when voip is null', () {
      expect(service.callMembershipsForRoom('!room:example.com'), isEmpty);
    });

    test('returns empty for unknown room', () {
      injectVoip();
      when(mockClient.getRoomById(any)).thenReturn(null);
      expect(service.callMembershipsForRoom('!room:example.com'), isEmpty);
    });
  });

  group('joinCall', () {
    test('does nothing when voip is null', () async {
      await service.joinCall('!room:example.com');
      expect(service.callState, LatticeCallState.idle);
    });

    test('returns early when room not found', () async {
      injectVoip();
      when(mockClient.getRoomById(any)).thenReturn(null);

      await service.joinCall('!room:example.com');
      expect(service.callState, LatticeCallState.idle);
    });

    test('transitions to failed when enter throws', () async {
      final mockRoom = MockRoom();
      final eventStreamController =
          StreamController<MatrixRTCCallEvent>.broadcast();

      injectVoip();
      when(mockClient.getRoomById('!room:example.com')).thenReturn(mockRoom);
      when(mockRoom.id).thenReturn('!room:example.com');
      when(mockRoom.activeGroupCallIds(mockVoip)).thenReturn([]);
      when(mockRoom.getCallMembershipsFromRoom(mockVoip)).thenReturn({});
      when(mockVoip.groupCalls).thenReturn({});

      await service.joinCall('!room:example.com');

      expect(service.callState, LatticeCallState.failed);
      expect(service.activeGroupCall, isNull);

      await eventStreamController.close();
    });

    test('notifies listeners on joining transition', () async {
      final mockRoom = MockRoom();

      injectVoip();
      when(mockClient.getRoomById('!room:example.com')).thenReturn(mockRoom);
      when(mockRoom.id).thenReturn('!room:example.com');
      when(mockRoom.activeGroupCallIds(mockVoip)).thenReturn([]);
      when(mockRoom.getCallMembershipsFromRoom(mockVoip)).thenReturn({});
      when(mockVoip.groupCalls).thenReturn({});

      final states = <LatticeCallState>[];
      service.addListener(() => states.add(service.callState));

      await service.joinCall('!room:example.com');

      expect(states, contains(LatticeCallState.joining));
    });
  });

  group('leaveCall', () {
    test('does nothing when no active call', () async {
      await service.leaveCall();
      expect(service.callState, LatticeCallState.idle);
    });

    test('does not notify when no active call', () async {
      var notified = false;
      service.addListener(() => notified = true);

      await service.leaveCall();
      expect(notified, isFalse);
    });
  });

  group('fetchTurnServers', () {
    test('returns null on error', () async {
      when(mockClient.getTurnServer()).thenThrow(Exception('no server'));
      final result = await service.fetchTurnServers();
      expect(result, isNull);
    });
  });

  group('dispose', () {
    test('resets call state', () {
      injectVoip();
      service.dispose();
      expect(service.callState, LatticeCallState.idle);
      expect(service.activeGroupCall, isNull);
      expect(service.voip, isNull);
    });
  });
}
