import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/features/calling/services/rtc_membership_service.dart';
import 'package:matrix/matrix.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

import 'call_test_helpers.dart';
@GenerateNiceMocks([MockSpec<Client>(), MockSpec<Room>()])
import 'rtc_membership_service_test.mocks.dart';

void main() {
  late MockClient mockClient;
  late RtcMembershipService service;

  setUp(() {
    mockClient = MockClient();
    when(mockClient.userID).thenReturn('@alice:example.com');
    when(mockClient.deviceID).thenReturn('DEV1');
    service = RtcMembershipService(client: mockClient);
  });

  // ── membershipStateKey ──────────────────────────────────────

  group('membershipStateKey', () {
    test('correct format', () {
      expect(service.membershipStateKey, '_@alice:example.com_DEV1_m.call');
    });
  });

  // ── makeMembershipContent ───────────────────────────────────

  group('makeMembershipContent', () {
    test('MSC3401 structure with livekit url/alias', () {
      final content = service.makeMembershipContent(
        'https://lk.example.com',
        'room-alias',
      );
      expect(content['application'], 'm.call');
      expect(content['call_id'], '');
      expect(content['scope'], 'm.room');
      expect(content['device_id'], 'DEV1');
      expect(content['expires'], membershipExpiresMs);
      expect(content['focus_active'], isA<Map<String, dynamic>>());
      expect(content['foci_preferred'], isA<List<dynamic>>());
      final foci = content['foci_preferred'] as List<dynamic>;
      final firstFoci = foci.first as Map<String, dynamic>;
      expect(firstFoci['livekit_service_url'], 'https://lk.example.com');
      expect(firstFoci['livekit_alias'], 'room-alias');
    });
  });

  // ── sendMembershipEvent ─────────────────────────────────────

  group('sendMembershipEvent', () {
    test('calls setRoomStateWithKey with correct params', () async {
      when(mockClient.setRoomStateWithKey(any, any, any, any))
          .thenAnswer((_) async => 'ev1');

      await service.sendMembershipEvent(
        '!room:x',
        'alias',
        livekitServiceUrl: 'https://lk.example.com',
      );

      verify(mockClient.setRoomStateWithKey(
        '!room:x',
        callMemberEventType,
        '_@alice:example.com_DEV1_m.call',
        argThat(isA<Map<String, dynamic>>()),
      ),).called(1);
    });
  });

  // ── removeMembershipEvent ───────────────────────────────────

  group('removeMembershipEvent', () {
    test('sends empty content', () async {
      when(mockClient.setRoomStateWithKey(any, any, any, any))
          .thenAnswer((_) async => 'ev1');

      await service.removeMembershipEvent('!room:x');

      verify(mockClient.setRoomStateWithKey(
        '!room:x',
        callMemberEventType,
        '_@alice:example.com_DEV1_m.call',
        {},
      ),).called(1);
    });
  });

  // ── membership renewal ──────────────────────────────────────

  group('membership renewal', () {
    test('periodic sends', () {
      fakeAsync((async) {
        when(mockClient.setRoomStateWithKey(any, any, any, any))
            .thenAnswer((_) async => 'ev1');

        service.startMembershipRenewal(
          '!room:x',
          'alias',
          livekitServiceUrl: 'https://lk.example.com',
        );

        async.elapse(const Duration(minutes: 5));
        verify(mockClient.setRoomStateWithKey(any, any, any, any)).called(1);

        async.elapse(const Duration(minutes: 5));
        verify(mockClient.setRoomStateWithKey(any, any, any, any)).called(1);

        service.cancelMembershipRenewal();
      });
    });

    test('cancel stops timer', () {
      fakeAsync((async) {
        when(mockClient.setRoomStateWithKey(any, any, any, any))
            .thenAnswer((_) async => 'ev1');

        service.startMembershipRenewal(
          '!room:x',
          'alias',
          livekitServiceUrl: 'https://lk.example.com',
        );
        service.cancelMembershipRenewal();

        async.elapse(const Duration(minutes: 10));
        verifyNever(mockClient.setRoomStateWithKey(any, any, any, any));
      });
    });

    test('restart replaces timer', () {
      fakeAsync((async) {
        when(mockClient.setRoomStateWithKey(any, any, any, any))
            .thenAnswer((_) async => 'ev1');

        service.startMembershipRenewal(
          '!room:x',
          'alias1',
          livekitServiceUrl: 'https://lk.example.com',
        );
        service.startMembershipRenewal(
          '!room:y',
          'alias2',
          livekitServiceUrl: 'https://lk2.example.com',
        );

        async.elapse(const Duration(minutes: 5));

        final captured = verify(mockClient.setRoomStateWithKey(
          captureAny,
          any,
          any,
          any,
        ),).captured;
        expect(captured.last, '!room:y');
      });
    });

    test('error handled gracefully', () {
      fakeAsync((async) {
        when(mockClient.setRoomStateWithKey(any, any, any, any))
            .thenThrow(Exception('network error'));

        service.startMembershipRenewal(
          '!room:x',
          'alias',
          livekitServiceUrl: 'https://lk.example.com',
        );

        expect(() => async.elapse(const Duration(minutes: 5)), returnsNormally);
        service.cancelMembershipRenewal();
      });
    });
  });

  // ── roomHasActiveCall ───────────────────────────────────────

  group('roomHasActiveCall', () {
    test('null room returns false', () {
      when(mockClient.getRoomById(any)).thenReturn(null);
      expect(RtcMembershipService.roomHasActiveCall(mockClient, '!r:x'), false);
    });

    test('no states returns false', () {
      final mockRoom = MockRoom();
      when(mockClient.getRoomById('!r:x')).thenReturn(mockRoom);
      when(mockRoom.states).thenReturn({});
      expect(RtcMembershipService.roomHasActiveCall(mockClient, '!r:x'), false);
    });

    test('active membership returns true', () {
      final mockRoom = MockRoom();
      when(mockClient.getRoomById('!r:x')).thenReturn(mockRoom);
      final now = DateTime.now().millisecondsSinceEpoch;
      when(mockRoom.states).thenReturn({
        callMemberEventType: {
          '_@bob:x_D1_m.call': FakeEvent(
            content: {'expires_ts': now + 60000},
            originServerTs: now,
          ),
        },
      });
      expect(RtcMembershipService.roomHasActiveCall(mockClient, '!r:x'), true);
    });

    test('expired membership returns false', () {
      final mockRoom = MockRoom();
      when(mockClient.getRoomById('!r:x')).thenReturn(mockRoom);
      final now = DateTime.now().millisecondsSinceEpoch;
      when(mockRoom.states).thenReturn({
        callMemberEventType: {
          '_@bob:x_D1_m.call': FakeEvent(
            content: {'expires_ts': now - 60000},
            originServerTs: now,
          ),
        },
      });
      expect(RtcMembershipService.roomHasActiveCall(mockClient, '!r:x'), false);
    });

    test('nested list format', () {
      final mockRoom = MockRoom();
      when(mockClient.getRoomById('!r:x')).thenReturn(mockRoom);
      final now = DateTime.now().millisecondsSinceEpoch;
      when(mockRoom.states).thenReturn({
        callMemberEventType: {
          '_@bob:x_D1_m.call': FakeEvent(
            content: {
              'memberships': [
                {'call_id': 'c1', 'expires_ts': now + 60000},
              ],
            },
            originServerTs: now,
          ),
        },
      });
      expect(RtcMembershipService.roomHasActiveCall(mockClient, '!r:x'), true);
    });

    test('empty content returns false', () {
      final mockRoom = MockRoom();
      when(mockClient.getRoomById('!r:x')).thenReturn(mockRoom);
      when(mockRoom.states).thenReturn({
        callMemberEventType: {
          '_@bob:x_D1_m.call': FakeEvent(
            content: {},
            originServerTs: 0,
          ),
        },
      });
      expect(RtcMembershipService.roomHasActiveCall(mockClient, '!r:x'), false);
    });
  });

  // ── roomHasRemoteActiveCall ─────────────────────────────────

  group('roomHasRemoteActiveCall', () {
    test('remote active returns true', () {
      final mockRoom = MockRoom();
      when(mockClient.getRoomById('!r:x')).thenReturn(mockRoom);
      final now = DateTime.now().millisecondsSinceEpoch;
      when(mockRoom.states).thenReturn({
        callMemberEventType: {
          '_@bob:y_D2_m.call': FakeEvent(
            content: {'expires_ts': now + 60000},
            originServerTs: now,
          ),
        },
      });
      expect(
        RtcMembershipService.roomHasRemoteActiveCall(mockClient, '!r:x'),
        true,
      );
    });

    test('only local returns false', () {
      final mockRoom = MockRoom();
      when(mockClient.getRoomById('!r:x')).thenReturn(mockRoom);
      final now = DateTime.now().millisecondsSinceEpoch;
      when(mockRoom.states).thenReturn({
        callMemberEventType: {
          '_@alice:example.com_DEV1_m.call': FakeEvent(
            content: {'expires_ts': now + 60000},
            originServerTs: now,
          ),
        },
      });
      expect(
        RtcMembershipService.roomHasRemoteActiveCall(mockClient, '!r:x'),
        false,
      );
    });

    test('null room returns false', () {
      when(mockClient.getRoomById(any)).thenReturn(null);
      expect(
        RtcMembershipService.roomHasRemoteActiveCall(mockClient, '!r:x'),
        false,
      );
    });
  });

  // ── activeCallIdsForRoom ────────────────────────────────────

  group('activeCallIdsForRoom', () {
    test('collects unique IDs', () {
      final mockRoom = MockRoom();
      when(mockClient.getRoomById('!r:x')).thenReturn(mockRoom);
      final now = DateTime.now().millisecondsSinceEpoch;
      when(mockRoom.states).thenReturn({
        callMemberEventType: {
          '_@a:x_D1_m.call': FakeEvent(
            content: {'call_id': 'c1', 'expires_ts': now + 60000},
            originServerTs: now,
          ),
          '_@b:x_D2_m.call': FakeEvent(
            content: {'call_id': 'c1', 'expires_ts': now + 60000},
            originServerTs: now,
          ),
        },
      });
      final ids = RtcMembershipService.activeCallIdsForRoom(mockClient, '!r:x');
      expect(ids, ['c1']);
    });

    test('empty string default for missing call_id', () {
      final mockRoom = MockRoom();
      when(mockClient.getRoomById('!r:x')).thenReturn(mockRoom);
      final now = DateTime.now().millisecondsSinceEpoch;
      when(mockRoom.states).thenReturn({
        callMemberEventType: {
          '_@a:x_D1_m.call': FakeEvent(
            content: {'expires_ts': now + 60000},
            originServerTs: now,
          ),
        },
      });
      final ids = RtcMembershipService.activeCallIdsForRoom(mockClient, '!r:x');
      expect(ids, ['']);
    });

    test('null room returns empty', () {
      when(mockClient.getRoomById(any)).thenReturn(null);
      expect(
        RtcMembershipService.activeCallIdsForRoom(mockClient, '!r:x'),
        isEmpty,
      );
    });
  });

  // ── callParticipantCount ────────────────────────────────────

  group('callParticipantCount', () {
    test('counts matching groupCallId', () {
      final mockRoom = MockRoom();
      when(mockClient.getRoomById('!r:x')).thenReturn(mockRoom);
      final now = DateTime.now().millisecondsSinceEpoch;
      when(mockRoom.states).thenReturn({
        callMemberEventType: {
          '_@a:x_D1_m.call': FakeEvent(
            content: {'call_id': 'g1', 'expires_ts': now + 60000},
            originServerTs: now,
          ),
          '_@b:x_D2_m.call': FakeEvent(
            content: {'call_id': 'g1', 'expires_ts': now + 60000},
            originServerTs: now,
          ),
          '_@c:x_D3_m.call': FakeEvent(
            content: {'call_id': 'g2', 'expires_ts': now + 60000},
            originServerTs: now,
          ),
        },
      });
      expect(
        RtcMembershipService.callParticipantCount(mockClient, '!r:x', 'g1'),
        2,
      );
    });

    test('ignores expired memberships', () {
      final mockRoom = MockRoom();
      when(mockClient.getRoomById('!r:x')).thenReturn(mockRoom);
      final now = DateTime.now().millisecondsSinceEpoch;
      when(mockRoom.states).thenReturn({
        callMemberEventType: {
          '_@a:x_D1_m.call': FakeEvent(
            content: {'call_id': 'g1', 'expires_ts': now - 60000},
            originServerTs: now,
          ),
        },
      });
      expect(
        RtcMembershipService.callParticipantCount(mockClient, '!r:x', 'g1'),
        0,
      );
    });
  });

  // ── membership expiry ───────────────────────────────────────

  group('membership expiry', () {
    test('absolute expires_ts active', () {
      final mockRoom = MockRoom();
      when(mockClient.getRoomById('!r:x')).thenReturn(mockRoom);
      final now = DateTime.now().millisecondsSinceEpoch;
      when(mockRoom.states).thenReturn({
        callMemberEventType: {
          '_@a:x_D1_m.call': FakeEvent(
            content: {'expires_ts': now + 60000},
            originServerTs: now,
          ),
        },
      });
      expect(RtcMembershipService.roomHasActiveCall(mockClient, '!r:x'), true);
    });

    test('absolute expires_ts expired', () {
      final mockRoom = MockRoom();
      when(mockClient.getRoomById('!r:x')).thenReturn(mockRoom);
      final now = DateTime.now().millisecondsSinceEpoch;
      when(mockRoom.states).thenReturn({
        callMemberEventType: {
          '_@a:x_D1_m.call': FakeEvent(
            content: {'expires_ts': now - 1},
            originServerTs: now,
          ),
        },
      });
      expect(RtcMembershipService.roomHasActiveCall(mockClient, '!r:x'), false);
    });

    test('relative expires active', () {
      final mockRoom = MockRoom();
      when(mockClient.getRoomById('!r:x')).thenReturn(mockRoom);
      final now = DateTime.now().millisecondsSinceEpoch;
      when(mockRoom.states).thenReturn({
        callMemberEventType: {
          '_@a:x_D1_m.call': FakeEvent(
            content: {'expires': 120000},
            originServerTs: now,
          ),
        },
      });
      expect(RtcMembershipService.roomHasActiveCall(mockClient, '!r:x'), true);
    });

    test('relative expires expired', () {
      final mockRoom = MockRoom();
      when(mockClient.getRoomById('!r:x')).thenReturn(mockRoom);
      final past = DateTime.now().millisecondsSinceEpoch - 200000;
      when(mockRoom.states).thenReturn({
        callMemberEventType: {
          '_@a:x_D1_m.call': FakeEvent(
            content: {'expires': 100000},
            originServerTs: past,
          ),
        },
      });
      expect(RtcMembershipService.roomHasActiveCall(mockClient, '!r:x'), false);
    });

    test('neither expires_ts nor expires returns false', () {
      final mockRoom = MockRoom();
      when(mockClient.getRoomById('!r:x')).thenReturn(mockRoom);
      final now = DateTime.now().millisecondsSinceEpoch;
      when(mockRoom.states).thenReturn({
        callMemberEventType: {
          '_@a:x_D1_m.call': FakeEvent(
            content: {'call_id': 'c1'},
            originServerTs: now,
          ),
        },
      });
      expect(RtcMembershipService.roomHasActiveCall(mockClient, '!r:x'), false);
    });

    test('expires_ts takes precedence over expires', () {
      final mockRoom = MockRoom();
      when(mockClient.getRoomById('!r:x')).thenReturn(mockRoom);
      final now = DateTime.now().millisecondsSinceEpoch;
      when(mockRoom.states).thenReturn({
        callMemberEventType: {
          '_@a:x_D1_m.call': FakeEvent(
            content: {
              'expires_ts': now + 60000,
              'expires': 1,
            },
            originServerTs: now - 100000,
          ),
        },
      });
      expect(RtcMembershipService.roomHasActiveCall(mockClient, '!r:x'), true);
    });
  });

  // ── membership format ───────────────────────────────────────

  group('membership format', () {
    test('nested memberships list', () {
      final mockRoom = MockRoom();
      when(mockClient.getRoomById('!r:x')).thenReturn(mockRoom);
      final now = DateTime.now().millisecondsSinceEpoch;
      when(mockRoom.states).thenReturn({
        callMemberEventType: {
          '_@a:x_D1_m.call': FakeEvent(
            content: {
              'memberships': [
                {'call_id': 'c1', 'expires_ts': now + 60000},
                {'call_id': 'c2', 'expires_ts': now + 60000},
              ],
            },
            originServerTs: now,
          ),
        },
      });
      final ids = RtcMembershipService.activeCallIdsForRoom(mockClient, '!r:x');
      expect(ids.length, 2);
      expect(ids, containsAll(['c1', 'c2']));
    });

    test('flat content (no memberships key)', () {
      final mockRoom = MockRoom();
      when(mockClient.getRoomById('!r:x')).thenReturn(mockRoom);
      final now = DateTime.now().millisecondsSinceEpoch;
      when(mockRoom.states).thenReturn({
        callMemberEventType: {
          '_@a:x_D1_m.call': FakeEvent(
            content: {'call_id': 'c1', 'expires_ts': now + 60000},
            originServerTs: now,
          ),
        },
      });
      final ids = RtcMembershipService.activeCallIdsForRoom(mockClient, '!r:x');
      expect(ids, ['c1']);
    });

    test('non-map entries in memberships list skipped', () {
      final mockRoom = MockRoom();
      when(mockClient.getRoomById('!r:x')).thenReturn(mockRoom);
      final now = DateTime.now().millisecondsSinceEpoch;
      when(mockRoom.states).thenReturn({
        callMemberEventType: {
          '_@a:x_D1_m.call': FakeEvent(
            content: {
              'memberships': [
                'not-a-map',
                42,
                {'call_id': 'c1', 'expires_ts': now + 60000},
              ],
            },
            originServerTs: now,
          ),
        },
      });
      final ids = RtcMembershipService.activeCallIdsForRoom(mockClient, '!r:x');
      expect(ids, ['c1']);
    });
  });

  // ── activeCallParticipantUserIds ────────────────────────────

  group('activeCallParticipantUserIds', () {
    test('returns correct user IDs from state keys', () {
      final mockRoom = MockRoom();
      when(mockClient.getRoomById('!r:x')).thenReturn(mockRoom);
      final now = DateTime.now().millisecondsSinceEpoch;
      when(mockRoom.states).thenReturn({
        callMemberEventType: {
          '_@alice:example.com_DEV1_m.call': FakeEvent(
            content: {'expires_ts': now + 60000},
            originServerTs: now,
          ),
          '_@bob:server.org_ABCD_m.call': FakeEvent(
            content: {'expires_ts': now + 60000},
            originServerTs: now,
          ),
        },
      });

      final userIds = RtcMembershipService.activeCallParticipantUserIds(
        mockClient,
        '!r:x',
      );
      expect(userIds, {'@alice:example.com', '@bob:server.org'});
    });

    test('returns empty set when no active memberships', () {
      final mockRoom = MockRoom();
      when(mockClient.getRoomById('!r:x')).thenReturn(mockRoom);
      when(mockRoom.states).thenReturn({});

      final userIds = RtcMembershipService.activeCallParticipantUserIds(
        mockClient,
        '!r:x',
      );
      expect(userIds, isEmpty);
    });

    test('returns empty set when room is null', () {
      when(mockClient.getRoomById(any)).thenReturn(null);
      final userIds = RtcMembershipService.activeCallParticipantUserIds(
        mockClient,
        '!r:x',
      );
      expect(userIds, isEmpty);
    });

    test('deduplicates user across multiple devices', () {
      final mockRoom = MockRoom();
      when(mockClient.getRoomById('!r:x')).thenReturn(mockRoom);
      final now = DateTime.now().millisecondsSinceEpoch;
      when(mockRoom.states).thenReturn({
        callMemberEventType: {
          '_@alice:example.com_DEV1_m.call': FakeEvent(
            content: {'expires_ts': now + 60000},
            originServerTs: now,
          ),
          '_@alice:example.com_DEV2_m.call': FakeEvent(
            content: {'expires_ts': now + 60000},
            originServerTs: now,
          ),
        },
      });

      final userIds = RtcMembershipService.activeCallParticipantUserIds(
        mockClient,
        '!r:x',
      );
      expect(userIds, {'@alice:example.com'});
    });

    test('excludes expired memberships', () {
      final mockRoom = MockRoom();
      when(mockClient.getRoomById('!r:x')).thenReturn(mockRoom);
      final now = DateTime.now().millisecondsSinceEpoch;
      when(mockRoom.states).thenReturn({
        callMemberEventType: {
          '_@alice:example.com_DEV1_m.call': FakeEvent(
            content: {'expires_ts': now + 60000},
            originServerTs: now,
          ),
          '_@bob:server.org_ABCD_m.call': FakeEvent(
            content: {'expires_ts': now - 60000},
            originServerTs: now,
          ),
        },
      });

      final userIds = RtcMembershipService.activeCallParticipantUserIds(
        mockClient,
        '!r:x',
      );
      expect(userIds, {'@alice:example.com'});
    });

    test('handles nested memberships list format', () {
      final mockRoom = MockRoom();
      when(mockClient.getRoomById('!r:x')).thenReturn(mockRoom);
      final now = DateTime.now().millisecondsSinceEpoch;
      when(mockRoom.states).thenReturn({
        callMemberEventType: {
          '_@alice:example.com_DEV1_m.call': FakeEvent(
            content: {
              'memberships': [
                {'call_id': 'c1', 'expires_ts': now + 60000},
              ],
            },
            originServerTs: now,
          ),
        },
      });

      final userIds = RtcMembershipService.activeCallParticipantUserIds(
        mockClient,
        '!r:x',
      );
      expect(userIds, {'@alice:example.com'});
    });
  });
}
