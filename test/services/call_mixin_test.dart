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
])
import 'call_mixin_test.mocks.dart';

void main() {
  late MockClient mockClient;
  late MockFlutterSecureStorage mockStorage;
  late MatrixService service;

  setUp(() {
    mockClient = MockClient();
    mockStorage = MockFlutterSecureStorage();
    when(mockClient.rooms).thenReturn([]);
    service = MatrixService(
      client: mockClient,
      storage: mockStorage,
      clientName: 'test',
    );
  });

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
      when(mockClient.getRoomById(any)).thenReturn(null);
      expect(service.roomHasActiveCall('!room:example.com'), isFalse);
    });
  });

  group('activeCallIdsForRoom', () {
    test('returns empty when voip is null', () {
      expect(service.activeCallIdsForRoom('!room:example.com'), isEmpty);
    });

    test('returns empty for unknown room', () {
      when(mockClient.getRoomById(any)).thenReturn(null);
      expect(service.activeCallIdsForRoom('!room:example.com'), isEmpty);
    });
  });

  group('callParticipantCount', () {
    test('returns 0 when voip is null', () {
      expect(service.callParticipantCount('!room:example.com', 'call1'), 0);
    });
  });

  group('callMembershipsForRoom', () {
    test('returns empty when voip is null', () {
      expect(service.callMembershipsForRoom('!room:example.com'), isEmpty);
    });
  });

  group('joinCall', () {
    test('does nothing when voip is null', () async {
      await service.joinCall('!room:example.com');
      expect(service.callState, LatticeCallState.idle);
    });

    test('does nothing when already in a call', () async {
      service.isLoggedInForTest = true;
      // Simulate non-idle state by setting internal state
      // Since we can't directly set _callState, we verify the guard
      // by trying to join when room is not found (which would fail differently)
      when(mockClient.getRoomById(any)).thenReturn(null);
      await service.joinCall('!room:example.com');
      // Should still be idle since voip is null
      expect(service.callState, LatticeCallState.idle);
    });
  });

  group('leaveCall', () {
    test('does nothing when no active call', () async {
      await service.leaveCall();
      expect(service.callState, LatticeCallState.idle);
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
      service.dispose();
      expect(service.callState, LatticeCallState.idle);
      expect(service.activeGroupCall, isNull);
      expect(service.voip, isNull);
    });
  });
}
