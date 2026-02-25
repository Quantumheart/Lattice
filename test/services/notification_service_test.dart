import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:matrix/matrix.dart';
import 'package:matrix/src/utils/cached_stream_controller.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lattice/services/matrix_service.dart';
import 'package:lattice/services/notification_service.dart';
import 'package:lattice/services/preferences_service.dart';

@GenerateNiceMocks([
  MockSpec<MatrixService>(),
  MockSpec<Client>(),
  MockSpec<Room>(),
  MockSpec<FlutterLocalNotificationsPlugin>(),
])
import 'notification_service_test.mocks.dart';

void main() {
  late MockMatrixService mockMatrix;
  late MockClient mockClient;
  late MockRoom mockRoom;
  late MockFlutterLocalNotificationsPlugin mockPlugin;
  late PreferencesService prefs;
  late NotificationService service;

  const roomId = '!room:example.com';
  const ownUserId = '@me:example.com';
  const otherUserId = '@alice:example.com';

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final sp = await SharedPreferences.getInstance();
    prefs = PreferencesService(prefs: sp);

    mockMatrix = MockMatrixService();
    mockClient = MockClient();
    mockRoom = MockRoom();
    mockPlugin = MockFlutterLocalNotificationsPlugin();

    final cachedController = CachedStreamController<SyncUpdate>();

    when(mockMatrix.client).thenReturn(mockClient);
    when(mockMatrix.selectedRoomId).thenReturn(null);
    when(mockClient.userID).thenReturn(ownUserId);
    when(mockClient.getRoomById(roomId)).thenReturn(mockRoom);
    when(mockClient.onSync).thenReturn(cachedController);
    when(mockRoom.client).thenReturn(mockClient);
    when(mockRoom.id).thenReturn(roomId);
    when(mockRoom.pushRuleState).thenReturn(PushRuleState.notify);
    when(mockRoom.getLocalizedDisplayname()).thenReturn('General');
    when(mockRoom.highlightCount).thenReturn(0);
    when(mockRoom.unsafeGetUserFromMemoryOrFallback(otherUserId))
        .thenReturn(User(otherUserId, room: mockRoom, displayName: 'Alice'));
    when(mockRoom.unsafeGetUserFromMemoryOrFallback(ownUserId))
        .thenReturn(User(ownUserId, room: mockRoom, displayName: 'Me'));

    service = NotificationService(
      matrixService: mockMatrix,
      preferencesService: prefs,
      plugin: mockPlugin,
    );
  });

  tearDown(() {
    service.dispose();
  });

  SyncUpdate makeSyncUpdate({
    required String roomId,
    required List<MatrixEvent> events,
  }) {
    return SyncUpdate(
      nextBatch: 'batch_1',
      rooms: RoomsUpdate(
        join: {
          roomId: JoinedRoomUpdate(
            timeline: TimelineUpdate(events: events),
          ),
        },
      ),
    );
  }

  MatrixEvent makeMessageEvent({
    String senderId = otherUserId,
    String body = 'hello world',
    String type = EventTypes.Message,
  }) {
    return MatrixEvent(
      type: type,
      content: type == EventTypes.Message ? {'msgtype': 'm.text', 'body': body} : {},
      senderId: senderId,
      eventId: '\$evt_${DateTime.now().microsecondsSinceEpoch}',
      originServerTs: DateTime.now(),
    );
  }

  group('sync lifecycle', () {
    test('first sync is skipped', () async {
      service.startListening();

      final update = makeSyncUpdate(
        roomId: roomId,
        events: [makeMessageEvent()],
      );

      // Emit via the client's onSync stream.
      mockClient.onSync.add(update);
      await Future.delayed(Duration.zero);

      verifyNever(mockPlugin.show(any, any, any, any, payload: anyNamed('payload')));
    });

    test('second sync triggers notification', () async {
      service.startListening();

      // First sync (skipped).
      mockClient.onSync.add(SyncUpdate(nextBatch: 'batch_0'));
      await Future.delayed(Duration.zero);

      // Second sync with a message.
      final update = makeSyncUpdate(
        roomId: roomId,
        events: [makeMessageEvent()],
      );
      mockClient.onSync.add(update);
      await Future.delayed(const Duration(milliseconds: 50));

      verify(mockPlugin.show(any, any, any, any, payload: roomId)).called(1);
    });
  });

  group('filtering', () {
    /// Helper to emit past the first-sync skip and send a real event.
    Future<void> emitMessage({
      String senderId = otherUserId,
      String body = 'hello',
      String type = EventTypes.Message,
    }) async {
      service.startListening();
      // Skip first sync.
      mockClient.onSync.add(SyncUpdate(nextBatch: 'batch_0'));
      await Future.delayed(Duration.zero);

      final update = makeSyncUpdate(
        roomId: roomId,
        events: [makeMessageEvent(senderId: senderId, body: body, type: type)],
      );
      mockClient.onSync.add(update);
      await Future.delayed(const Duration(milliseconds: 50));
    }

    test('own messages are ignored', () async {
      await emitMessage(senderId: ownUserId);
      verifyNever(mockPlugin.show(any, any, any, any, payload: anyNamed('payload')));
    });

    test('osNotificationsEnabled=false suppresses all', () async {
      await prefs.setOsNotificationsEnabled(false);
      await emitMessage();
      verifyNever(mockPlugin.show(any, any, any, any, payload: anyNamed('payload')));
    });

    test('notification level off suppresses all', () async {
      await prefs.setNotificationLevel(NotificationLevel.off);
      await emitMessage();
      verifyNever(mockPlugin.show(any, any, any, any, payload: anyNamed('payload')));
    });

    test('per-room dontNotify suppresses notification', () async {
      when(mockRoom.pushRuleState).thenReturn(PushRuleState.dontNotify);
      await emitMessage();
      verifyNever(mockPlugin.show(any, any, any, any, payload: anyNamed('payload')));
    });

    test('currently selected room suppresses notification', () async {
      when(mockMatrix.selectedRoomId).thenReturn(roomId);
      await emitMessage();
      verifyNever(mockPlugin.show(any, any, any, any, payload: anyNamed('payload')));
    });

    test('foreground toggle overrides selected room suppression', () async {
      when(mockMatrix.selectedRoomId).thenReturn(roomId);
      await prefs.setForegroundNotificationsEnabled(true);
      await emitMessage();
      verify(mockPlugin.show(any, any, any, any, payload: roomId)).called(1);
    });

    test('mentionsOnly with no match suppresses', () async {
      await prefs.setNotificationLevel(NotificationLevel.mentionsOnly);
      await emitMessage(body: 'just chatting');
      verifyNever(mockPlugin.show(any, any, any, any, payload: anyNamed('payload')));
    });

    test('mentionsOnly with keyword match fires notification', () async {
      await prefs.setNotificationLevel(NotificationLevel.mentionsOnly);
      await prefs.addNotificationKeyword('urgent');
      await emitMessage(body: 'this is URGENT');
      verify(mockPlugin.show(any, any, any, any, payload: roomId)).called(1);
    });

    test('mentionsOnly with user mention fires notification', () async {
      await prefs.setNotificationLevel(NotificationLevel.mentionsOnly);
      await emitMessage(body: 'hey @me:example.com check this');
      verify(mockPlugin.show(any, any, any, any, payload: roomId)).called(1);
    });

    test('mentionsOnly with display name mention fires notification', () async {
      await prefs.setNotificationLevel(NotificationLevel.mentionsOnly);
      await emitMessage(body: 'hey Me, are you there?');
      verify(mockPlugin.show(any, any, any, any, payload: roomId)).called(1);
    });
  });

  group('invite notifications', () {
    SyncUpdate makeInviteSyncUpdate({
      required String roomId,
      List<StrippedStateEvent>? inviteState,
    }) {
      return SyncUpdate(
        nextBatch: 'batch_1',
        rooms: RoomsUpdate(
          invite: {
            roomId: InvitedRoomUpdate(
              inviteState: inviteState,
            ),
          },
        ),
      );
    }

    Future<void> skipFirstSync() async {
      service.startListening();
      mockClient.onSync.add(SyncUpdate(nextBatch: 'batch_0'));
      await Future.delayed(Duration.zero);
    }

    test('shows notification for invite', () async {
      service.isAppResumed = false;
      await skipFirstSync();

      final update = makeInviteSyncUpdate(
        roomId: roomId,
        inviteState: [
          StrippedStateEvent(
            type: EventTypes.RoomMember,
            content: {'membership': 'invite'},
            senderId: otherUserId,
            stateKey: ownUserId,
          ),
        ],
      );
      mockClient.onSync.add(update);
      await Future.delayed(const Duration(milliseconds: 50));

      verify(mockPlugin.show(any, 'General', argThat(contains('invited you to join')), any,
              payload: roomId))
          .called(1);
    });

    test('deduplicates invite notifications across syncs', () async {
      service.isAppResumed = false;
      await skipFirstSync();

      final update = makeInviteSyncUpdate(roomId: roomId);
      mockClient.onSync.add(update);
      await Future.delayed(const Duration(milliseconds: 50));

      // Same invite again in next sync.
      mockClient.onSync.add(update);
      await Future.delayed(const Duration(milliseconds: 50));

      verify(mockPlugin.show(any, any, any, any, payload: roomId)).called(1);
    });

    test('suppressed when app is in foreground', () async {
      service.isAppResumed = true;
      await skipFirstSync();

      final update = makeInviteSyncUpdate(roomId: roomId);
      mockClient.onSync.add(update);
      await Future.delayed(const Duration(milliseconds: 50));

      verifyNever(mockPlugin.show(any, any, any, any, payload: anyNamed('payload')));
    });

    test('shown when app in foreground but foreground notifications enabled', () async {
      service.isAppResumed = true;
      await prefs.setForegroundNotificationsEnabled(true);
      await skipFirstSync();

      final update = makeInviteSyncUpdate(roomId: roomId);
      mockClient.onSync.add(update);
      await Future.delayed(const Duration(milliseconds: 50));

      verify(mockPlugin.show(any, any, any, any, payload: roomId)).called(1);
    });

    test('suppressed when room push rule is dontNotify', () async {
      when(mockRoom.pushRuleState).thenReturn(PushRuleState.dontNotify);
      service.isAppResumed = false;
      await skipFirstSync();

      final update = makeInviteSyncUpdate(roomId: roomId);
      mockClient.onSync.add(update);
      await Future.delayed(const Duration(milliseconds: 50));

      verifyNever(mockPlugin.show(any, any, any, any, payload: anyNamed('payload')));
    });

    test('allows re-invite notification after room is left', () async {
      service.isAppResumed = false;
      await skipFirstSync();

      // First invite — should notify.
      final invite1 = makeInviteSyncUpdate(roomId: roomId);
      mockClient.onSync.add(invite1);
      await Future.delayed(const Duration(milliseconds: 50));
      verify(mockPlugin.show(any, any, any, any, payload: roomId)).called(1);

      // Room left (declined).
      final leaveSync = SyncUpdate(
        nextBatch: 'batch_2',
        rooms: RoomsUpdate(leave: {roomId: LeftRoomUpdate()}),
      );
      mockClient.onSync.add(leaveSync);
      await Future.delayed(const Duration(milliseconds: 50));

      // Re-invite — should notify again.
      mockClient.onSync.add(invite1);
      await Future.delayed(const Duration(milliseconds: 50));
      verify(mockPlugin.show(any, any, any, any, payload: roomId)).called(1);
    });

    test('allows re-invite notification after room is joined', () async {
      service.isAppResumed = false;
      await skipFirstSync();

      // First invite — should notify.
      final invite1 = makeInviteSyncUpdate(roomId: roomId);
      mockClient.onSync.add(invite1);
      await Future.delayed(const Duration(milliseconds: 50));
      verify(mockPlugin.show(any, any, any, any, payload: roomId)).called(1);

      // Room joined.
      final joinSync = SyncUpdate(
        nextBatch: 'batch_2',
        rooms: RoomsUpdate(join: {roomId: JoinedRoomUpdate()}),
      );
      mockClient.onSync.add(joinSync);
      await Future.delayed(const Duration(milliseconds: 50));

      // Re-invite — should notify again.
      mockClient.onSync.add(invite1);
      await Future.delayed(const Duration(milliseconds: 50));
      verify(mockPlugin.show(any, any, any, any, payload: roomId)).called(1);
    });
  });

  group('notification content', () {
    test('notification ID is derived from stable FNV-1a hash of roomId', () async {
      service.startListening();
      mockClient.onSync.add(SyncUpdate(nextBatch: 'batch_0'));
      await Future.delayed(Duration.zero);

      final update = makeSyncUpdate(
        roomId: roomId,
        events: [makeMessageEvent()],
      );
      mockClient.onSync.add(update);
      await Future.delayed(const Duration(milliseconds: 50));

      // FNV-1a 32-bit, matching _stableNotificationId in the service.
      var hash = 0x811c9dc5;
      for (var i = 0; i < roomId.length; i++) {
        hash ^= roomId.codeUnitAt(i);
        hash = (hash * 0x01000193) & 0xFFFFFFFF;
      }
      final expectedId = hash & 0x7FFFFFFF;
      verify(mockPlugin.show(expectedId, any, any, any, payload: roomId)).called(1);
    });

    test('notification shows room name as title', () async {
      service.startListening();
      mockClient.onSync.add(SyncUpdate(nextBatch: 'batch_0'));
      await Future.delayed(Duration.zero);

      final update = makeSyncUpdate(
        roomId: roomId,
        events: [makeMessageEvent(body: 'hey')],
      );
      mockClient.onSync.add(update);
      await Future.delayed(const Duration(milliseconds: 50));

      verify(mockPlugin.show(any, 'General', 'Alice: hey', any, payload: roomId))
          .called(1);
    });
  });

  group('encrypted events', () {
    test('falls back to "Encrypted message" for encrypted events', () async {
      service.startListening();
      mockClient.onSync.add(SyncUpdate(nextBatch: 'batch_0'));
      await Future.delayed(Duration.zero);

      // Encrypted event with no encryption available (client.encryption is null).
      when(mockClient.encryption).thenReturn(null);
      final update = makeSyncUpdate(
        roomId: roomId,
        events: [makeMessageEvent(type: EventTypes.Encrypted)],
      );
      mockClient.onSync.add(update);
      await Future.delayed(const Duration(milliseconds: 50));

      verify(mockPlugin.show(any, any, argThat(contains('Encrypted message')), any,
              payload: roomId))
          .called(1);
    });
  });
}
